import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/diagnostics.dart';
import 'package:chronicler/src/lifecycle.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/transport.dart';
import 'package:conflux/effect.dart';

/// Owns buffered records, export attempts, retries, and exporter shutdown.
///
/// Pending and active records retain their capacity until terminal disposition.
/// Flush and close retain disposition tokens, so later queue transitions cannot
/// change which records belong to their reports.
final class DeliveryQueue {
  /// Creates delivery with the runtime's monotonic clock and jitter source.
  DeliveryQueue({
    required this._options,
    required this._exporter,
    required this._diagnostics,
    required this._nextRandom,
    required this._runtime,
  });

  final Runtime _runtime;

  final DeliveryOptions _options;
  final ChroniclerExporter _exporter;
  final DiagnosticChannel _diagnostics;
  Duration _elapsed() => _runtime.clock.monotonic();
  final double Function() _nextRandom;
  final _pending = Queue<_PendingRecord>();
  final _active = <_ActiveExport>{};
  final _flushWaiters = <_FlushWaiter>{};
  var _bufferedBytes = 0;
  var _nextSequence = 0;
  var _pumpScheduled = false;
  Fiber<void, Never>? _wakeTask;
  ChroniclerRuntimeState _state = ChroniclerRuntimeState.running;
  bool _deliveryOpen = true;
  Future<DeliveryReport>? _closeFuture;
  _Shutdown? _shutdown;

  /// Current lifecycle state shared with capture gating.
  ChroniclerRuntimeState get state => _state;

  /// Creates terminal accounting for a record rejected before enqueueing.
  DeliveryDisposition dropped(DropReason reason) {
    final disposition = DeliveryDisposition._();
    _dropDisposition(disposition, reason);
    return disposition;
  }

  /// Admits one validated, encoded record to the bounded delivery queue.
  DeliveryDisposition enqueue(
    ChroniclerRecord record,
    int encodedBytes, {
    bool allowDuringClosing = false,
  }) {
    final disposition = DeliveryDisposition._();
    if (_pending.length + _activeRecordCount >= _options.maxPendingRecords ||
        _bufferedBytes + encodedBytes > _options.maxPendingBytes) {
      _dropDisposition(disposition, DropReason.queueFull);
      return disposition;
    }
    if (_state != ChroniclerRuntimeState.running && !allowDuringClosing) {
      _dropDisposition(disposition, DropReason.runtimeClosed);
      return disposition;
    }
    final pending = _PendingRecord(
      record,
      encodedBytes,
      _nextSequence++,
      _elapsed() + _options.batchInterval,
      disposition,
    );
    _pending.add(pending);
    _bufferedBytes += encodedBytes;
    if (_pending.where((record) => !record.isRetry).length >= _options.maxBatchRecords) {
      final now = _elapsed();
      for (final record in _pending.where((record) => !record.isRetry)) {
        record.readyAt = now;
      }
      _schedulePump();
    } else {
      _scheduleWakeup();
    }
    return disposition;
  }

  /// Stops queued delivery and future retries for a disabled signal.
  void disableCollection(ChroniclerSignal signal) {
    for (final record in _pending.where((record) => _signalFor(record.record) == signal).toList()) {
      _pending.remove(record);
      _drop(record, DropReason.collectionDisabled);
    }
    for (final export in _active) {
      for (final record in export.records) {
        if (_signalFor(record.record) == signal) record.retryEligible = false;
      }
    }
    _scheduleWakeup();
  }

  ChroniclerSignal _signalFor(ChroniclerRecord record) => switch (record.signalKind) {
    ChroniclerSignalKind.logs => ChroniclerSignal.logs,
    ChroniclerSignalKind.events => ChroniclerSignal.events,
    ChroniclerSignalKind.traces => ChroniclerSignal.traces,
    ChroniclerSignalKind.errors => ChroniclerSignal.errors,
    ChroniclerSignalKind.metrics => ChroniclerSignal.metrics,
  };

  /// Finalizes capture synchronously, then waits on the resulting snapshot.
  Future<DeliveryReport> flush(
    Duration timeout, {
    required Iterable<DeliveryDisposition> Function() finalize,
  }) {
    if (timeout <= Duration.zero) {
      throw const ChroniclerConfigurationException('timeout', 'must be positive');
    }
    final finalizedByCall = <DeliveryDisposition>[];
    if (_state == ChroniclerRuntimeState.running) {
      finalizedByCall.addAll(finalize());
    }
    final snapshot = <DeliveryDisposition>{
      for (final record in _pending) record.disposition,
      for (final export in _active)
        for (final record in export.records) record.disposition,
      ...finalizedByCall,
    };
    if (_state != ChroniclerRuntimeState.running || snapshot.every((state) => state._isTerminal)) {
      return Future.value(_report(snapshot, timedOut: false));
    }
    final now = _elapsed();
    for (final record in _pending) {
      if (snapshot.contains(record.disposition)) record.readyAt = now;
    }
    final waiter = _FlushWaiter(snapshot);
    _flushWaiters.add(waiter);
    waiter.deadlineTask = _after(timeout, () => _completeFlush(waiter, timedOut: true));
    _schedulePump();
    return waiter.completer.future;
  }

  /// Stops recording and closes the owned exporter within one deadline.
  ///
  /// [finalize] runs synchronously after entering closing state and before the
  /// delivery snapshot is captured. It may admit final records during closing.
  Future<DeliveryReport> close({required Iterable<DeliveryDisposition> Function() finalize}) {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completer = Completer<DeliveryReport>();
    _closeFuture = completer.future;
    _beginClose(completer, finalize);
    return completer.future;
  }

  void _beginClose(
    Completer<DeliveryReport> completer,
    Iterable<DeliveryDisposition> Function() finalize,
  ) {
    _state = ChroniclerRuntimeState.closing;
    _diagnostics.close();
    final startedAt = _elapsed();
    final finalizations = finalize().toList();
    final snapshot = <DeliveryDisposition>{
      for (final record in _pending) record.disposition,
      for (final export in _active)
        for (final record in export.records) record.disposition,
      ...finalizations,
    };
    final shutdown = _Shutdown(snapshot);
    _shutdown = shutdown;
    final resolved = shutdown.deliveryResolved;
    if (snapshot.every((state) => state._isTerminal)) resolved.complete();
    final now = _elapsed();
    for (final record in _pending) {
      record.readyAt = now;
    }
    _schedulePump();
    unawaited(_finishClose(completer, snapshot, resolved.future, startedAt));
  }

  Future<void> _finishClose(
    Completer<DeliveryReport> completer,
    Set<DeliveryDisposition> snapshot,
    Future<void> deliveryResolved,
    Duration startedAt,
  ) async {
    final exit = await _runtime.run(_runClose(snapshot, deliveryResolved, startedAt));
    final DeliveryReport report;
    switch (exit) {
      case Succeeded(:final value):
        report = value;
      case Failed():
        _finishOutstandingAtShutdown();
        _state = ChroniclerRuntimeState.closed;
        _shutdown = null;
        _notifyDispositionWaiters();
        report = _report(snapshot, timedOut: true, cleanupIncomplete: true);
    }
    completer.complete(report);
  }

  Effect<DeliveryReport, Never> _runClose(
    Set<DeliveryDisposition> snapshot,
    Future<void> deliveryResolved,
    Duration startedAt,
  ) => Effect.build(($) async {
    final totalDeadline = startedAt + _options.closeTimeout;
    final deliveryDeadline = totalDeadline - _options.cleanupReserve;
    final deliveryCompleted = await $(_completesBy(deliveryResolved, deliveryDeadline));
    _deliveryOpen = false;
    unawaited(_wakeTask?.interrupt());
    _wakeTask = null;
    if (!deliveryCompleted) {
      for (final record in _pending.toList()) {
        _pending.remove(record);
        _drop(record, DropReason.shutdown);
      }
      for (final active in _active) {
        for (final record in active.records) {
          record.disposition._uncertain = true;
        }
        _requestCancellation(active);
      }
    }

    var cleanupFailed = false;
    Future<void> exporterCleanup;
    try {
      exporterCleanup = _exporter.close();
    } on Object {
      cleanupFailed = true;
      _diagnostics.record(DiagnosticReason.exportCleanupFailed);
      exporterCleanup = Future.value();
    }
    final observedCleanup = exporterCleanup.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        cleanupFailed = true;
        _diagnostics.record(DiagnosticReason.exportCleanupFailed);
      },
    );
    final activeDrained = Completer<void>();
    _shutdown!.activeDrained = activeDrained;
    if (_active.isEmpty) activeDrained.complete();
    final cleanupCompleted = await $(
      _completesBy(
        Future.wait([observedCleanup, activeDrained.future]),
        totalDeadline,
      ),
    );
    if (!cleanupCompleted) _finishOutstandingAtShutdown();
    _state = ChroniclerRuntimeState.closed;
    _shutdown = null;
    _notifyDispositionWaiters();
    return _report(
      snapshot,
      timedOut: !deliveryCompleted || !cleanupCompleted,
      cleanupIncomplete: cleanupFailed || !cleanupCompleted,
    );
  });

  /// Stops observing foreign work at the deadline, without claiming it stopped.
  /// No exporter cleanup is registered as a protected Effect finalizer: a
  /// transport that never settles must not prevent bounded shutdown.
  Effect<bool, Never> _completesBy(Future<void> operation, Duration deadline) {
    final remaining = deadline - _elapsed();
    if (remaining <= Duration.zero) return Effect.succeed(false);
    final observed = Effect.tryFuture<bool, Never>(
      (_) => operation.then((_) => true, onError: (Object _, StackTrace _) => true),
      onError: (error, stackTrace, _) => Error.throwWithStackTrace(error, stackTrace),
    );
    final expired = Effect.defer<bool, Never>((_) {
      final remaining = deadline - _elapsed();
      return Effect.sleep(remaining > Duration.zero ? remaining : Duration.zero)
          .map((_, _) => false);
    });
    return Effect.race([observed, expired]);
  }

  Fiber<void, Never> _after(Duration delay, void Function() action) {
    final deadline = _elapsed() + delay;
    return _runtime.fork(
      Effect.defer((_) {
        final remaining = deadline - _elapsed();
        return Effect.sleep(remaining > Duration.zero ? remaining : Duration.zero)
            .map((_, _) => action());
      }),
    );
  }

  int get _activeRecordCount => _active.fold(0, (count, export) => count + export.records.length);

  void _schedulePump() {
    if (_pumpScheduled || !_deliveryOpen) return;
    _pumpScheduled = true;
    _after(Duration.zero, () {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (!_deliveryOpen) return;
    unawaited(_wakeTask?.interrupt());
    _wakeTask = null;
    while (_active.length < _options.maxConcurrentExports) {
      final now = _elapsed();
      final eligible = _pending.where((record) => record.readyAt <= now).toList()
        ..sort((left, right) => left.sequence.compareTo(right.sequence));
      if (eligible.isEmpty) break;
      final records = <_PendingRecord>[];
      var batchBytes = 32;
      for (final next in eligible) {
        if (records.length >= _options.maxBatchRecords) break;
        final candidateBytes = batchBytes + next.encodedBytes + (records.isEmpty ? 0 : 1);
        if (candidateBytes > _options.maxBatchBytes) break;
        _pending.remove(next);
        records.add(next);
        batchBytes = candidateBytes;
      }
      if (records.isEmpty) break;
      for (final record in records) {
        record.attempts++;
      }
      final active = _ActiveExport(
        records,
        _elapsed() + _options.attemptTimeout,
      );
      _active.add(active);
      _runtime.fork(
        Effect.tryFuture<ExportResult, Object>(
          (_) {
            // Create and observe the future in the same turn, including an
            // exporter that returns an already-failed future.
            final attempt = _exporter.export(
              ChroniclerBatch(records.map((pending) => pending.record)),
            );
            active.attempt = attempt;
            final result = attempt.result;
            _scheduleAttemptTimeout(active);
            return result;
          },
          onError: (error, _, _) => error,
        ).onExit(
          (exit, _) => Effect.sync((_) {
            switch (exit) {
              case Succeeded(:final value):
                _handleResult(active, value);
              case Failed():
                // Shutdown has already terminally accounted for abandoned work.
                _handleFailure(active);
            }
          }),
        ),
      );
    }
    _scheduleWakeup();
  }

  void _scheduleAttemptTimeout(_ActiveExport active) {
    final remaining = active.deadline - _elapsed();
    if (remaining <= Duration.zero) {
      _timeOut(active);
    } else {
      active.timeout = _after(remaining, () => _timeOut(active));
    }
  }

  void _timeOut(_ActiveExport active) {
    if (!_active.contains(active) || active.timedOut) return;
    // Cancellation is a request, not proof that transport stopped. Retain the
    // slot and capacity until settlement; close bounds a stuck exporter's wait.
    active.timedOut = true;
    for (final record in active.records) {
      record.disposition._uncertain = true;
    }
    _diagnostics.record(DiagnosticReason.exportTimedOut);
    _requestCancellation(active);
  }

  void _requestCancellation(_ActiveExport active) {
    if (active.cancellationRequested) return;
    active.cancellationRequested = true;
    unawaited(active.timeout?.interrupt());
    try {
      active.attempt?.cancel();
    } on Object {
      _diagnostics.record(DiagnosticReason.exportCancellationFailed);
    }
  }

  void _handleResult(_ActiveExport active, ExportResult result) {
    if (!_active.remove(active)) return;
    unawaited(active.timeout?.interrupt());
    final outcomes = _validatedOutcomes(active.records, result);
    if (outcomes == null) {
      _diagnostics.record(DiagnosticReason.invalidExportResult);
      for (final record in active.records) {
        record.disposition._uncertain = true;
        _retry(record);
      }
      _notifyActiveDrained();
      _schedulePump();
      return;
    }
    for (final record in active.records) {
      switch (outcomes[record.record.envelope.eventId]!) {
        case ExportDisposition.accepted:
          _accept(record);
        case ExportDisposition.rejected:
          _drop(record, DropReason.exportRejected);
        case ExportDisposition.retryable:
          record.disposition._uncertain = true;
          _retry(record);
      }
    }
    _notifyActiveDrained();
    _schedulePump();
  }

  void _handleFailure(_ActiveExport active) {
    if (!_active.remove(active)) return;
    unawaited(active.timeout?.interrupt());
    _diagnostics.record(DiagnosticReason.exportFailed);
    for (final record in active.records) {
      record.disposition._uncertain = true;
      _retry(record);
    }
    _notifyActiveDrained();
    _schedulePump();
  }

  Map<String, ExportDisposition>? _validatedOutcomes(
    List<_PendingRecord> records,
    ExportResult result,
  ) {
    if (result case WholeBatchExportResult(:final disposition)) {
      return {for (final record in records) record.record.envelope.eventId: disposition};
    }
    final submittedIds = records.map((record) => record.record.envelope.eventId).toSet();
    final outcomes = <String, ExportDisposition>{};
    for (final outcome in (result as RecordExportResult).outcomes) {
      if (!submittedIds.contains(outcome.eventId) || outcomes.containsKey(outcome.eventId)) {
        return null;
      }
      outcomes[outcome.eventId] = outcome.disposition;
    }
    return outcomes.length == submittedIds.length ? outcomes : null;
  }

  void _retry(_PendingRecord record) {
    if (!record.retryEligible) {
      _drop(record, DropReason.collectionDisabled);
      return;
    }
    if (!_deliveryOpen) {
      _drop(record, DropReason.shutdown);
      return;
    }
    if (record.attempts >= _options.maxAttempts) {
      _drop(record, DropReason.attemptsExhausted);
      return;
    }
    final ceiling = _retryCeiling(record.attempts);
    final delay = _chooseRetryDelay(ceiling);
    record
      ..isRetry = true
      ..readyAt = _elapsed() + delay;
    _pending.add(record);
  }

  Duration _chooseRetryDelay(Duration ceiling) {
    try {
      final delay = Duration(
        microseconds: min(
          (_nextRandom() * (ceiling.inMicroseconds + 1)).floor(),
          ceiling.inMicroseconds,
        ),
      );
      if (delay < Duration.zero || delay > ceiling) {
        throw StateError('Retry delay must be between zero and its ceiling.');
      }
      return delay;
    } on Object {
      _diagnostics.record(DiagnosticReason.exportFailed);
      return Duration.zero;
    }
  }

  Duration _retryCeiling(int attempts) {
    final maximumMicros = _options.maxRetryDelay.inMicroseconds;
    var ceilingMicros = _options.initialRetryDelay.inMicroseconds;
    for (var retry = 1; retry < attempts; retry++) {
      ceilingMicros = ceilingMicros >= maximumMicros ~/ 2 ? maximumMicros : ceilingMicros * 2;
    }
    return Duration(microseconds: ceilingMicros);
  }

  void _accept(_PendingRecord record) {
    _bufferedBytes -= record.encodedBytes;
    record.disposition._outcome = const _Accepted();
    _notifyDispositionWaiters();
  }

  void _drop(_PendingRecord record, DropReason reason) {
    _bufferedBytes -= record.encodedBytes;
    _dropDisposition(record.disposition, reason);
  }

  void _dropDisposition(DeliveryDisposition disposition, DropReason reason) {
    disposition._outcome = _Dropped(reason);
    _diagnostics.record(_diagnosticFor(reason));
    _notifyDispositionWaiters();
  }

  DiagnosticReason _diagnosticFor(DropReason reason) => switch (reason) {
    DropReason.invalidRecord => DiagnosticReason.invalidRecord,
    DropReason.recordTooLarge => DiagnosticReason.recordTooLarge,
    DropReason.queueFull => DiagnosticReason.queueFull,
    DropReason.collectionDisabled => DiagnosticReason.collectionDisabled,
    DropReason.sampledOut => DiagnosticReason.sampledOut,
    DropReason.hookDropped => DiagnosticReason.hookDropped,
    DropReason.hookFailed => DiagnosticReason.hookFailed,
    DropReason.exportRejected => DiagnosticReason.exportRejected,
    DropReason.attemptsExhausted => DiagnosticReason.attemptsExhausted,
    DropReason.shutdown => DiagnosticReason.shutdown,
    DropReason.runtimeClosed => DiagnosticReason.runtimeClosed,
  };

  void _notifyDispositionWaiters() {
    for (final waiter in _flushWaiters.toList()) {
      if (waiter.snapshot.every((state) => state._isTerminal)) {
        _completeFlush(waiter, timedOut: false);
      }
    }
    final closeSnapshot = _shutdown?.snapshot;
    final closeResolved = _shutdown?.deliveryResolved;
    if (closeSnapshot != null &&
        closeResolved != null &&
        !closeResolved.isCompleted &&
        closeSnapshot.every((state) => state._isTerminal)) {
      closeResolved.complete();
    }
  }

  void _notifyActiveDrained() {
    final activeDrained = _shutdown?.activeDrained;
    if (_active.isEmpty && activeDrained != null && !activeDrained.isCompleted) {
      activeDrained.complete();
    }
  }

  void _finishOutstandingAtShutdown() {
    unawaited(_wakeTask?.interrupt());
    _wakeTask = null;
    for (final record in _pending.toList()) {
      _pending.remove(record);
      _drop(record, DropReason.shutdown);
    }
    for (final active in _active.toList()) {
      _active.remove(active);
      unawaited(active.timeout?.interrupt());
      for (final record in active.records) {
        record.disposition._uncertain = true;
        _drop(record, DropReason.shutdown);
      }
    }
    _notifyActiveDrained();
  }

  void _completeFlush(_FlushWaiter waiter, {required bool timedOut}) {
    if (!_flushWaiters.remove(waiter)) return;
    unawaited(waiter.deadlineTask?.interrupt());
    waiter.completer.complete(_report(waiter.snapshot, timedOut: timedOut));
  }

  DeliveryReport _report(
    Iterable<DeliveryDisposition> snapshot, {
    required bool timedOut,
    bool cleanupIncomplete = false,
  }) {
    var accepted = 0;
    var pending = 0;
    var uncertainDropped = 0;
    final dropped = <DropReason, int>{};
    for (final disposition in snapshot) {
      switch (disposition._outcome) {
        case _Accepted():
          accepted++;
        case _Dropped(:final reason):
          dropped.update(reason, (count) => count + 1, ifAbsent: () => 1);
          if (disposition._uncertain) uncertainDropped++;
        case null:
          pending++;
      }
    }
    return DeliveryReport(
      accepted: accepted,
      dropped: dropped,
      pending: pending,
      uncertainDropped: uncertainDropped,
      timedOut: timedOut,
      runtimeState: _state,
      cleanupIncomplete: cleanupIncomplete,
    );
  }

  void _scheduleWakeup() {
    if (!_deliveryOpen || _pending.isEmpty || _active.length >= _options.maxConcurrentExports) {
      unawaited(_wakeTask?.interrupt());
      _wakeTask = null;
      return;
    }
    final next = _pending
        .map((record) => record.readyAt)
        .reduce((left, right) => left <= right ? left : right);
    final delay = next - _elapsed();
    if (delay <= Duration.zero) {
      _schedulePump();
      return;
    }
    unawaited(_wakeTask?.interrupt());
    _wakeTask = _after(delay, _pump);
  }
}

final class _PendingRecord {
  _PendingRecord(
    this.record,
    this.encodedBytes,
    this.sequence,
    this.readyAt,
    this.disposition,
  );
  final ChroniclerRecord record;
  final int encodedBytes;
  final int sequence;
  final DeliveryDisposition disposition;
  Duration readyAt;
  int attempts = 0;
  bool isRetry = false;
  bool retryEligible = true;
}

/// Opaque accounting token retained by a flush or close snapshot.
final class DeliveryDisposition {
  DeliveryDisposition._();

  _DispositionOutcome? _outcome;
  bool _uncertain = false;

  bool get _isTerminal => _outcome != null;
}

sealed class _DispositionOutcome {
  const _DispositionOutcome();
}

final class _Accepted extends _DispositionOutcome {
  const _Accepted();
}

final class _Dropped extends _DispositionOutcome {
  const _Dropped(this.reason);

  final DropReason reason;
}

final class _FlushWaiter {
  _FlushWaiter(Set<DeliveryDisposition> snapshot) : snapshot = Set.unmodifiable(snapshot);

  final Set<DeliveryDisposition> snapshot;
  final completer = Completer<DeliveryReport>();
  Fiber<void, Never>? deadlineTask;
}

final class _ActiveExport {
  _ActiveExport(this.records, this.deadline);
  final List<_PendingRecord> records;
  final Duration deadline;
  ExportAttempt? attempt;
  Fiber<void, Never>? timeout;
  bool timedOut = false;
  bool cancellationRequested = false;
}

/// State retained only while the shared shutdown operation is running.
final class _Shutdown {
  _Shutdown(this.snapshot);

  final Set<DeliveryDisposition> snapshot;
  final deliveryResolved = Completer<void>();
  Completer<void>? activeDrained;
}

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:chronicler/src/codec.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/diagnostics.dart';
import 'package:chronicler/src/lifecycle.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chronicler/src/transport.dart';
import 'package:chrono_id/chrono_id.dart';

/// Configured owner of capture and export resources.
final class Chronicler {
  /// Creates a runtime and transfers ownership of [exporter] to it.
  Chronicler({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    String? buildId,
    ChroniclerOptions options = const ChroniclerOptions(),
  }) : _runtime = ChroniclerRuntime.create(
         appId: appId,
         release: release,
         source: source,
         exporter: exporter,
         buildId: buildId,
         options: options,
       );

  /// Default field-name terms replaced before buffering.
  static const Set<String> defaultSensitiveFieldTerms =
      ChroniclerOptions.defaultSensitiveFieldTerms;

  final ChroniclerRuntime _runtime;

  /// A borrowed recorder suitable for binding to a request context.
  ChroniclerRecorder get recorder => ChroniclerRecorder._(
    _runtime,
    const _RecorderAttribution(),
  );

  /// An immutable snapshot of exact runtime diagnostic counts.
  Map<DiagnosticReason, BigInt> get diagnosticCounts => _runtime.diagnosticCounts;

  /// Waits for the records owned when this call begins to reach a disposition.
  Future<DeliveryReport> flush({Duration? timeout}) =>
      _runtime.flush(timeout ?? _runtime.options.delivery.flushTimeout);

  /// Stops recording, drains bounded work, and releases the owned exporter.
  Future<DeliveryReport> close() => _runtime.close();

  /// Whether collection currently accepts [signal].
  bool isCollectionEnabled(ChroniclerSignal signal) => _runtime.isCollectionEnabled(signal);

  /// Enables or disables collection for [signal] synchronously.
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setCollectionEnabled(ChroniclerSignal signal, bool enabled) =>
      _runtime.setCollectionEnabled(signal, enabled);

  /// Enables or disables trace-context propagation independently of collection.
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setPropagationEnabled(bool enabled) => _runtime.setPropagationEnabled(enabled);
}

/// Borrowed immutable attribution view over one Chronicler runtime.
final class ChroniclerRecorder {
  const ChroniclerRecorder._(this._runtime, this._attribution);

  final ChroniclerRuntime _runtime;
  final _RecorderAttribution _attribution;

  /// Returns a recorder whose analytics identity is exactly the supplied IDs.
  ///
  /// Omitted IDs are cleared. Runtime configuration and operation correlation
  /// remain shared with this recorder.
  ChroniclerRecorder withIdentity({
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) => _runtime._withIdentity(
    this,
    userId: userId,
    anonymousId: anonymousId,
    sessionId: sessionId,
  );

  /// Records a structured log without waiting for transport work.
  void recordLog(
    LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) => _runtime._recordLog(
    _attribution,
    severity,
    message,
    error: error,
    stackTrace: stackTrace,
    attributes: attributes,
  );

  /// Records an ordinary named product event without waiting for transport.
  void recordEvent(
    String name, {
    Map<String, Object?> properties = const {},
  }) => _runtime._recordEvent(_attribution, name, properties: properties);

  /// Records an explicit anonymous-to-user association.
  void identify({required String anonymousId, required String userId}) =>
      _runtime._recordIdentityLink(
        _attribution,
        anonymousId: anonymousId,
        userId: userId,
      );

  /// Records explicit user properties to set for [userId].
  void setUserProperties({
    required String userId,
    required Map<String, Object?> properties,
  }) => _runtime._recordUserPropertiesSet(
    _attribution,
    userId: userId,
    properties: properties,
  );

  /// Records explicit user-property removals for [userId].
  void unsetUserProperties({
    required String userId,
    required List<String> keys,
  }) => _runtime._recordUserPropertiesUnset(
    _attribution,
    userId: userId,
    keys: keys,
  );
}

final class _RecorderAttribution {
  const _RecorderAttribution({
    this.userId,
    this.anonymousId,
    this.sessionId,
    this.traceId,
    this.spanId,
  });

  final String? userId;
  final String? anonymousId;
  final String? sessionId;
  final String? traceId;
  final String? spanId;
}

/// Internal owner of queue, delivery, and lifecycle state.
final class ChroniclerRuntime {
  ChroniclerRuntime._({
    required this.appId,
    required this.release,
    required this.source,
    required this.exporter,
    required this.buildId,
    required this.options,
  }) : validator = RecordValidator(
         options.limits,
         maxSnapshotBytes: options.delivery.maxRecordBytes,
       ),
       codec = ChroniclerCodec(
         limits: options.limits,
         maxRecordBytes: options.delivery.maxRecordBytes,
         maxBatchBytes: options.delivery.maxBatchBytes,
         maxBatchRecords: options.delivery.maxBatchRecords,
       ),
       diagnostics = DiagnosticChannel(options.diagnostics);

  /// Validates [options] and creates a running delivery state machine.
  factory ChroniclerRuntime.create({
    required String appId,
    required String release,
    required ChroniclerSource source,
    required ChroniclerExporter exporter,
    required String? buildId,
    required ChroniclerOptions options,
  }) {
    final snapshot = _validateAndSnapshotOptions(options);
    final validator = RecordValidator(snapshot.limits);
    _validateConfiguredLabel(validator, appId, 'appId', snapshot.limits.maxIdBytes);
    _validateConfiguredLabel(validator, release, 'release', snapshot.limits.maxLabelBytes);
    if (buildId != null) {
      _validateConfiguredLabel(validator, buildId, 'buildId', snapshot.limits.maxLabelBytes);
    }
    return ChroniclerRuntime._(
      appId: appId,
      release: release,
      source: source,
      exporter: exporter,
      buildId: buildId,
      options: snapshot,
    );
  }

  /// Application identifier copied into every record envelope.
  final String appId;

  /// Application release copied into every record envelope.
  final String release;

  /// Runtime source copied into every record envelope.
  final ChroniclerSource source;

  /// Application exporter owned by this runtime.
  final ChroniclerExporter exporter;

  /// Optional build identifier copied into every record envelope.
  final String? buildId;

  /// Validated immutable runtime options.
  final ChroniclerOptions options;

  /// Validator used before records enter delivery.
  final RecordValidator validator;

  /// Canonical codec used for size accounting and transport values.
  final ChroniclerCodec codec;

  /// Payload-free runtime diagnostic channel.
  final DiagnosticChannel diagnostics;
  final _pending = Queue<_PendingRecord>();
  final _active = <_ActiveExport>{};
  final _flushWaiters = <_FlushWaiter>{};
  final _flushFinalizations = Queue<List<ChroniclerRecord>>();
  final _elapsed = Stopwatch()..start();
  late final Set<ChroniclerSignal> _enabledSignals = Set.of(options.enabledSignals);
  late bool _propagationEnabled = options.tracing.propagationEnabled;
  late final Random _random = Random();
  var _insideHook = false;
  var _pendingBytes = 0;
  var _nextSequence = 0;
  var _pumpScheduled = false;
  Timer? _wakeTimer;
  Duration Function(int attempt, Duration ceiling)? _retryDelayOverride;
  ChroniclerRuntimeState _state = ChroniclerRuntimeState.running;
  bool _deliveryOpen = true;
  Future<DeliveryReport>? _closeFuture;
  Set<_RecordDisposition>? _closeSnapshot;
  Completer<void>? _closeDeliveryResolved;
  Completer<void>? _activeDrained;

  /// An immutable snapshot of exact diagnostic counts.
  Map<DiagnosticReason, BigInt> get diagnosticCounts => diagnostics.counts;

  ChroniclerRecorder _withIdentity(
    ChroniclerRecorder recorder, {
    String? userId,
    String? anonymousId,
    String? sessionId,
  }) {
    try {
      for (final MapEntry(:key, :value) in {
        'userId': userId,
        'anonymousId': anonymousId,
        'sessionId': sessionId,
      }.entries) {
        if (value != null) _validateRequiredId(value, key);
      }
    } on RecordValidationException catch (error) {
      throw ChroniclerConfigurationException('identity', error.reason);
    }
    return ChroniclerRecorder._(
      this,
      _RecorderAttribution(
        userId: userId,
        anonymousId: anonymousId,
        sessionId: sessionId,
        traceId: recorder._attribution.traceId,
        spanId: recorder._attribution.spanId,
      ),
    );
  }

  /// Flushes the current record snapshot within [timeout].
  Future<DeliveryReport> flush(Duration timeout) {
    _requireOutsideCallback('flush');
    if (timeout <= Duration.zero) {
      throw const ChroniclerConfigurationException('timeout', 'must be positive');
    }
    final finalizedByCall = <_RecordDisposition>[];
    if (_state == ChroniclerRuntimeState.running && _flushFinalizations.isNotEmpty) {
      for (final record in _flushFinalizations.removeFirst()) {
        finalizedByCall.add(_finalizeForFlush(record));
      }
    }
    final snapshot = <_RecordDisposition>{
      for (final record in _pending) record.disposition,
      for (final export in _active)
        for (final record in export.records) record.disposition,
      ...finalizedByCall,
    };
    if (_state != ChroniclerRuntimeState.running || snapshot.every((state) => state.isTerminal)) {
      return Future.value(_report(snapshot, timedOut: false));
    }
    final now = _elapsed.elapsed;
    for (final record in _pending) {
      if (snapshot.contains(record.disposition)) record.readyAt = now;
    }
    final waiter = _FlushWaiter(snapshot);
    _flushWaiters.add(waiter);
    waiter.timer = Timer(timeout, () => _completeFlush(waiter, timedOut: true));
    _schedulePump();
    return waiter.completer.future;
  }

  /// Stops recording and closes the owned exporter within one deadline.
  Future<DeliveryReport> close() {
    _requireOutsideCallback('close');
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completer = Completer<DeliveryReport>();
    _closeFuture = completer.future;
    _beginClose(completer);
    return completer.future;
  }

  void _beginClose(Completer<DeliveryReport> completer) {
    _state = ChroniclerRuntimeState.closing;
    diagnostics.close();
    final startedAt = _elapsed.elapsed;
    final finalizations = <_RecordDisposition>[];
    while (_flushFinalizations.isNotEmpty) {
      for (final record in _flushFinalizations.removeFirst()) {
        finalizations.add(_finalizeForClose(record));
      }
    }
    final snapshot = <_RecordDisposition>{
      for (final record in _pending) record.disposition,
      for (final export in _active)
        for (final record in export.records) record.disposition,
      ...finalizations,
    };
    _closeSnapshot = snapshot;
    final resolved = Completer<void>();
    _closeDeliveryResolved = resolved;
    if (snapshot.every((state) => state.isTerminal)) resolved.complete();
    final now = _elapsed.elapsed;
    for (final record in _pending) {
      record.readyAt = now;
    }
    _schedulePump();
    unawaited(
      _runClose(snapshot, resolved.future, startedAt).then(
        completer.complete,
        onError: (Object _, StackTrace _) {
          _finishOutstandingAtShutdown();
          _state = ChroniclerRuntimeState.closed;
          _closeDeliveryResolved = null;
          _closeSnapshot = null;
          _activeDrained = null;
          _notifyDispositionWaiters();
          completer.complete(_report(snapshot, timedOut: true, cleanupIncomplete: true));
        },
      ),
    );
  }

  Future<DeliveryReport> _runClose(
    Set<_RecordDisposition> snapshot,
    Future<void> deliveryResolved,
    Duration startedAt,
  ) async {
    final totalDeadline = startedAt + options.delivery.closeTimeout;
    final deliveryDeadline = totalDeadline - options.delivery.cleanupReserve;
    final deliveryCompleted = await _completesBy(deliveryResolved, deliveryDeadline);
    _deliveryOpen = false;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    if (!deliveryCompleted) {
      for (final record in _pending.toList()) {
        _pending.remove(record);
        _drop(record, DropReason.shutdown);
      }
      for (final active in _active) {
        for (final record in active.records) {
          record.disposition.uncertain = true;
        }
        _requestCancellation(active);
      }
    }

    var cleanupFailed = false;
    Future<void> exporterCleanup;
    try {
      exporterCleanup = exporter.close();
    } on Object {
      cleanupFailed = true;
      diagnostics.record(DiagnosticReason.exportCleanupFailed);
      exporterCleanup = Future.value();
    }
    final observedCleanup = exporterCleanup.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        cleanupFailed = true;
        diagnostics.record(DiagnosticReason.exportCleanupFailed);
      },
    );
    final activeDrained = Completer<void>();
    _activeDrained = activeDrained;
    if (_active.isEmpty) activeDrained.complete();
    final cleanupCompleted = await _completesBy(
      Future.wait([observedCleanup, activeDrained.future]),
      totalDeadline,
    );
    if (!cleanupCompleted) _finishOutstandingAtShutdown();
    _activeDrained = null;
    _state = ChroniclerRuntimeState.closed;
    _closeDeliveryResolved = null;
    _closeSnapshot = null;
    _notifyDispositionWaiters();
    return _report(
      snapshot,
      timedOut: !deliveryCompleted || !cleanupCompleted,
      cleanupIncomplete: cleanupFailed || !cleanupCompleted,
    );
  }

  Future<bool> _completesBy(Future<void> operation, Duration deadline) {
    final remaining = deadline - _elapsed.elapsed;
    if (remaining <= Duration.zero) return Future.value(false);
    final result = Completer<bool>();
    late final Timer timer;
    timer = Timer(remaining, () => result.complete(false));
    unawaited(
      operation.then<void>(
        (_) {
          if (result.isCompleted) return;
          timer.cancel();
          result.complete(true);
        },
        onError: (Object _, StackTrace _) {
          if (result.isCompleted) return;
          timer.cancel();
          result.complete(true);
        },
      ),
    );
    return result.future;
  }

  /// Whether collection currently accepts [signal].
  bool isCollectionEnabled(ChroniclerSignal signal) => _enabledSignals.contains(signal);

  /// Enables or disables collection for [signal].
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setCollectionEnabled(ChroniclerSignal signal, bool enabled) {
    _requireRunningConfiguration();
    if (enabled == _enabledSignals.contains(signal)) return;
    if (enabled) {
      _enabledSignals.add(signal);
      return;
    }
    _enabledSignals.remove(signal);
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

  /// Enables or disables trace-context propagation.
  // API contract uses a positional boolean for symmetric runtime toggles.
  // ignore: avoid_positional_boolean_parameters
  void setPropagationEnabled(bool enabled) {
    _requireRunningConfiguration();
    _propagationEnabled = enabled;
  }

  void _requireRunningConfiguration() {
    _requireOutsideCallback('configuration');
    if (_state != ChroniclerRuntimeState.running) {
      throw const ChroniclerConfigurationException(
        'lifecycle',
        'does not allow configuration changes',
      );
    }
  }

  void _requireOutsideCallback(String operation) {
    if (_insideHook || diagnostics.insideCallback) {
      throw ChroniclerConfigurationException(
        operation,
        'cannot be called from a Chronicler callback',
      );
    }
  }

  void _recordLog(
    _RecorderAttribution attribution,
    LogSeverity severity,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) {
    if (!_canRecord(ChroniclerSignal.logs, options.sampling.logs)) return;
    try {
      validator.validateString(message, options.limits.maxStringBytes, 'message');
      final snapshot = validator.snapshotAttributes(attributes);
      final details = error == null ? null : _convertError(error, stackTrace);
      final standaloneStack = error == null && stackTrace != null
          ? _safeText(stackTrace.toString, '[Stack trace unavailable]')
          : null;
      if (standaloneStack != null) {
        validator.validateString(
          standaloneStack,
          options.limits.maxStackTraceBytes,
          'stackTrace',
        );
      }
      final record = LogRecord(
        envelope: _envelope(attribution),
        payload: LogPayload(
          severity: severity,
          message: message,
          attributes: snapshot,
          error: details,
          stackTrace: standaloneStack,
        ),
      );
      _finalizeAndEnqueue(record);
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  void _recordEvent(
    _RecorderAttribution attribution,
    String name, {
    Map<String, Object?> properties = const {},
  }) {
    if (!_canRecord(ChroniclerSignal.events, options.sampling.events)) return;
    try {
      validator.validateString(name, options.limits.maxLabelBytes, 'event name');
      if (name.isEmpty) {
        throw const RecordValidationException('event name must be nonempty');
      }
      final snapshot = validator.snapshotAttributes(properties);
      _finalizeAndEnqueue(
        ProductEventRecord(
          envelope: _envelope(attribution),
          payload: ProductEventPayload(name: name, properties: snapshot),
        ),
      );
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  void _recordIdentityLink(
    _RecorderAttribution attribution, {
    required String anonymousId,
    required String userId,
  }) {
    _recordEventControl(() {
      _validateRequiredId(anonymousId, 'anonymousId');
      _validateRequiredId(userId, 'userId');
      return IdentityLinkRecord(
        envelope: _envelope(attribution),
        payload: IdentityLinkPayload(anonymousId: anonymousId, userId: userId),
      );
    });
  }

  void _recordUserPropertiesSet(
    _RecorderAttribution attribution, {
    required String userId,
    required Map<String, Object?> properties,
  }) {
    if (properties.isEmpty) return;
    _recordEventControl(() {
      _validateRequiredId(userId, 'userId');
      final snapshot = validator.snapshotAttributes(properties);
      return UserPropertiesSetRecord(
        envelope: _envelope(attribution),
        payload: UserPropertiesSetPayload(userId: userId, properties: snapshot),
      );
    });
  }

  void _recordUserPropertiesUnset(
    _RecorderAttribution attribution, {
    required String userId,
    required List<String> keys,
  }) {
    if (keys.isEmpty) return;
    _recordEventControl(() {
      _validateRequiredId(userId, 'userId');
      final distinctKeys = <String>{};
      for (final key in keys) {
        validator.validateString(key, options.limits.maxKeyBytes, 'property key');
        if (key.isEmpty) {
          throw const RecordValidationException('property key must be nonempty');
        }
        distinctKeys.add(key);
      }
      if (distinctKeys.length > options.limits.maxListItems) {
        throw const RecordValidationException('property key list item limit exceeded');
      }
      return UserPropertiesUnsetRecord(
        envelope: _envelope(attribution),
        payload: UserPropertiesUnsetPayload(userId: userId, keys: distinctKeys),
      );
    });
  }

  void _recordEventControl(ChroniclerRecord Function() createRecord) {
    if (!_canRecord(ChroniclerSignal.events, null)) return;
    try {
      _finalizeAndEnqueue(createRecord());
    } on RecordValidationException {
      diagnostics.record(DiagnosticReason.invalidRecord);
    } on Object {
      diagnostics.record(DiagnosticReason.invalidRecord);
    }
  }

  void _validateRequiredId(String value, String name) {
    validator.validateString(value, options.limits.maxIdBytes, name);
    if (value.isEmpty) throw RecordValidationException('$name must be nonempty');
  }

  bool _canRecord(ChroniclerSignal signal, double? sampleRate) {
    if (_state != ChroniclerRuntimeState.running) {
      diagnostics.record(DiagnosticReason.runtimeClosed);
      return false;
    }
    if (diagnostics.insideCallback || _insideHook) {
      diagnostics.record(DiagnosticReason.reentrantRecording);
      return false;
    }
    return _allowsCapture(signal, sampleRate);
  }

  RecordEnvelope _envelope(_RecorderAttribution attribution) => RecordEnvelope(
    eventId: ChronoID.generate(prefix: 'evt'),
    appId: appId,
    release: release,
    source: source,
    timestamp: DateTime.now().toUtc(),
    buildId: buildId,
    userId: attribution.userId,
    anonymousId: attribution.anonymousId,
    sessionId: attribution.sessionId,
    traceId: attribution.traceId,
    spanId: attribution.spanId,
  );

  bool _allowsCapture(ChroniclerSignal signal, double? sampleRate) {
    if (!_enabledSignals.contains(signal)) {
      diagnostics.record(DiagnosticReason.collectionDisabled);
      return false;
    }
    if (sampleRate != null &&
        (sampleRate == 0 || sampleRate < 1 && _random.nextDouble() >= sampleRate)) {
      diagnostics.record(DiagnosticReason.sampledOut);
      return false;
    }
    return true;
  }

  void _captureFixture(ChroniclerRecord record) {
    if (_state != ChroniclerRuntimeState.running) {
      diagnostics.record(DiagnosticReason.runtimeClosed);
      return;
    }
    final signal = _signalFor(record);
    final sampleRate = switch (record) {
      LogRecord() => options.sampling.logs,
      ProductEventRecord() => options.sampling.events,
      SpanRecord() => options.sampling.traces,
      _ => null,
    };
    if (_allowsCapture(signal, sampleRate)) _finalizeAndEnqueue(record);
  }

  ChroniclerSignal _signalFor(ChroniclerRecord record) => switch (record.signalKind) {
    ChroniclerSignalKind.logs => ChroniclerSignal.logs,
    ChroniclerSignalKind.events => ChroniclerSignal.events,
    ChroniclerSignalKind.traces => ChroniclerSignal.traces,
    ChroniclerSignalKind.errors => ChroniclerSignal.errors,
    ChroniclerSignalKind.metrics => ChroniclerSignal.metrics,
  };

  _RecordDisposition _finalizeForFlush(ChroniclerRecord record) {
    if (!_enabledSignals.contains(_signalFor(record))) {
      final disposition = _RecordDisposition();
      _dropDisposition(disposition, DropReason.collectionDisabled);
      return disposition;
    }
    return _finalizeAndEnqueue(record);
  }

  _RecordDisposition _finalizeForClose(ChroniclerRecord record) {
    if (!_enabledSignals.contains(_signalFor(record))) {
      final disposition = _RecordDisposition();
      _dropDisposition(disposition, DropReason.collectionDisabled);
      return disposition;
    }
    return _finalizeAndEnqueue(record, allowDuringClosing: true);
  }

  _RecordDisposition _finalizeAndEnqueue(
    ChroniclerRecord original, {
    bool allowDuringClosing = false,
  }) {
    final disposition = _RecordDisposition();
    if (_state != ChroniclerRuntimeState.running && !allowDuringClosing) {
      _dropDisposition(disposition, DropReason.runtimeClosed);
      return disposition;
    }
    try {
      // Validate caller data before field-name rules can hide it.
      codec.validateRecord(original);
      var record = _redactRecord(original);
      final hook = options.redaction.beforeRecord;
      if (hook != null) {
        ChroniclerRecord? changed;
        _insideHook = true;
        try {
          changed = hook(record);
        } on Object {
          _dropDisposition(disposition, DropReason.hookFailed);
          return disposition;
        } finally {
          _insideHook = false;
        }
        if (changed == null) {
          _dropDisposition(disposition, DropReason.hookDropped);
          return disposition;
        }
        if (!_preservesProtectedFields(original, changed)) {
          _dropDisposition(disposition, DropReason.invalidRecord);
          return disposition;
        }
        try {
          codec.validateRecord(changed);
        } on Object {
          _dropDisposition(disposition, DropReason.invalidRecord);
          return disposition;
        }
        record = changed;
      }
      record = _redactRecord(record);
      final bytes = codec.encodeRecord(record);
      if (bytes.length > options.delivery.maxRecordBytes) {
        _dropDisposition(disposition, DropReason.recordTooLarge);
        return disposition;
      }
      if (_pending.length + _activeRecordCount >= options.delivery.maxPendingRecords ||
          _pendingBytes + bytes.length > options.delivery.maxPendingBytes) {
        _dropDisposition(disposition, DropReason.queueFull);
        return disposition;
      }
      if (_state != ChroniclerRuntimeState.running && !allowDuringClosing) {
        _dropDisposition(disposition, DropReason.runtimeClosed);
        return disposition;
      }
      final pending = _PendingRecord(
        record,
        bytes.length,
        _nextSequence++,
        _elapsed.elapsed + options.delivery.batchInterval,
        disposition,
      );
      _pending.add(pending);
      _pendingBytes += bytes.length;
      if (_pending.where((record) => !record.isRetry).length >= options.delivery.maxBatchRecords) {
        final now = _elapsed.elapsed;
        for (final record in _pending.where((record) => !record.isRetry)) {
          record.readyAt = now;
        }
        _schedulePump();
      } else {
        _scheduleWakeup();
      }
      return disposition;
    } on RecordValidationException {
      _dropDisposition(disposition, DropReason.invalidRecord);
    } on ChroniclerEncodingException catch (error) {
      _dropDisposition(
        disposition,
        error.reason == 'record byte limit exceeded'
            ? DropReason.recordTooLarge
            : DropReason.invalidRecord,
      );
    } on Object {
      _dropDisposition(disposition, DropReason.invalidRecord);
    }
    return disposition;
  }

  ChroniclerRecord _redactRecord(ChroniclerRecord record) => switch (record) {
    LogRecord() => LogRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: _redactMap(record.payload.attributes)),
    ),
    ProductEventRecord() => ProductEventRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(properties: _redactMap(record.payload.properties)),
    ),
    UserPropertiesSetRecord() => UserPropertiesSetRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(properties: _redactMap(record.payload.properties)),
    ),
    SpanRecord() => SpanRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: _redactMap(record.payload.attributes)),
    ),
    ErrorRecord() => ErrorRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: _redactMap(record.payload.attributes)),
    ),
    MetricRecord() => MetricRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: _redactMap(record.payload.attributes)),
    ),
    IdentityLinkRecord() || UserPropertiesUnsetRecord() => record,
  };

  Map<String, Object?> _redactMap(Map<Object?, Object?> source) => Map.unmodifiable(
    source.map((key, value) {
      final stringKey = key! as String;
      return MapEntry(
        stringKey,
        options.redaction.fieldTerms.any(stringKey.toLowerCase().contains)
            ? '[REDACTED]'
            : _redactValue(value),
      );
    }),
  );

  Object? _redactValue(Object? value) => switch (value) {
    Map<Object?, Object?>() => _redactMap(value),
    List<Object?>() => List<Object?>.unmodifiable(value.map(_redactValue)),
    _ => value,
  };

  bool _preservesProtectedFields(ChroniclerRecord original, ChroniclerRecord changed) {
    if (original.runtimeType != changed.runtimeType) return false;
    final before = original.envelope;
    final after = changed.envelope;
    if (before.eventId != after.eventId ||
        before.timestamp != after.timestamp ||
        before.appId != after.appId ||
        before.source != after.source ||
        before.release != after.release ||
        before.buildId != after.buildId ||
        before.traceId != after.traceId ||
        before.spanId != after.spanId ||
        before.parentSpanId != after.parentSpanId ||
        !_identityPreserved(before.userId, after.userId) ||
        !_identityPreserved(before.anonymousId, after.anonymousId) ||
        !_identityPreserved(before.sessionId, after.sessionId)) {
      return false;
    }
    if (original case MetricRecord(payload: final beforeMetric)) {
      final afterMetric = (changed as MetricRecord).payload;
      return beforeMetric.name == afterMetric.name &&
          beforeMetric.instrument == afterMetric.instrument &&
          beforeMetric.unit == afterMetric.unit &&
          beforeMetric.intervalStart == afterMetric.intervalStart &&
          beforeMetric.intervalEnd == afterMetric.intervalEnd &&
          beforeMetric.durationMicros == afterMetric.durationMicros &&
          beforeMetric.temporality == afterMetric.temporality &&
          _sameList(beforeMetric.boundaries, afterMetric.boundaries);
    }
    return true;
  }

  bool _identityPreserved(String? before, String? after) => after == null || after == before;

  bool _sameList<T>(List<T>? before, List<T>? after) {
    if (before == null || after == null) return before == after;
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (before[index] != after[index]) return false;
    }
    return true;
  }

  int get _activeRecordCount => _active.fold(0, (count, export) => count + export.records.length);

  ErrorDetails _convertError(Object error, StackTrace? stackTrace) {
    final type = _safeText(() => error.runtimeType.toString(), '[Unknown error type]');
    final message = _safeText(error.toString, '[Error message unavailable]');
    final stack = stackTrace == null
        ? null
        : _safeText(stackTrace.toString, '[Stack trace unavailable]');
    validator
      ..validateString(type, options.limits.maxLabelBytes, 'error type')
      ..validateString(message, options.limits.maxErrorMessageBytes, 'error message');
    if (stack != null) {
      validator.validateString(stack, options.limits.maxStackTraceBytes, 'error stackTrace');
    }
    return ErrorDetails(type: type, message: message, stackTrace: stack);
  }

  String _safeText(String Function() convert, String fallback) {
    try {
      return convert();
    } on Object {
      diagnostics.record(DiagnosticReason.textConversionFailed);
      return fallback;
    }
  }

  void _schedulePump() {
    if (_pumpScheduled || !_deliveryOpen) return;
    _pumpScheduled = true;
    Timer.run(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (!_deliveryOpen) return;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    while (_active.length < options.delivery.maxConcurrentExports) {
      final now = _elapsed.elapsed;
      final eligible = _pending.where((record) => record.readyAt <= now).toList()
        ..sort((left, right) => left.sequence.compareTo(right.sequence));
      if (eligible.isEmpty) break;
      final records = <_PendingRecord>[];
      var batchBytes = 32;
      for (final next in eligible) {
        if (records.length >= options.delivery.maxBatchRecords) break;
        final candidateBytes = batchBytes + next.encodedBytes + (records.isEmpty ? 0 : 1);
        if (candidateBytes > options.delivery.maxBatchBytes) break;
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
        _elapsed.elapsed + options.delivery.attemptTimeout,
      );
      _active.add(active);
      try {
        final attempt = exporter.export(
          ChroniclerBatch(records.map((pending) => pending.record)),
        );
        active.attempt = attempt;
        final result = attempt.result;
        unawaited(
          result.then(
            (result) => _handleResult(active, result),
            onError: (Object _, StackTrace _) => _handleFailure(active),
          ),
        );
        _scheduleAttemptTimeout(active);
      } on Object {
        _handleFailure(active);
      }
    }
    _scheduleWakeup();
  }

  void _scheduleAttemptTimeout(_ActiveExport active) {
    final remaining = active.deadline - _elapsed.elapsed;
    if (remaining <= Duration.zero) {
      _timeOut(active);
    } else {
      active.timeout = Timer(remaining, () => _timeOut(active));
    }
  }

  void _timeOut(_ActiveExport active) {
    if (!_active.contains(active) || active.timedOut) return;
    active.timedOut = true;
    for (final record in active.records) {
      record.disposition.uncertain = true;
    }
    diagnostics.record(DiagnosticReason.exportTimedOut);
    _requestCancellation(active);
  }

  void _requestCancellation(_ActiveExport active) {
    if (active.cancellationRequested) return;
    active.cancellationRequested = true;
    active.timeout?.cancel();
    try {
      active.attempt?.cancel();
    } on Object {
      diagnostics.record(DiagnosticReason.exportCancellationFailed);
    }
  }

  void _handleResult(_ActiveExport active, ExportResult result) {
    if (!_active.remove(active)) return;
    active.timeout?.cancel();
    final outcomes = _validatedOutcomes(active.records, result);
    if (outcomes == null) {
      diagnostics.record(DiagnosticReason.invalidExportResult);
      for (final record in active.records) {
        record.disposition.uncertain = true;
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
          record.disposition.uncertain = true;
          _retry(record);
      }
    }
    _notifyActiveDrained();
    _schedulePump();
  }

  void _handleFailure(_ActiveExport active) {
    if (!_active.remove(active)) return;
    active.timeout?.cancel();
    diagnostics.record(DiagnosticReason.exportFailed);
    for (final record in active.records) {
      record.disposition.uncertain = true;
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
    if (record.attempts >= options.delivery.maxAttempts) {
      _drop(record, DropReason.attemptsExhausted);
      return;
    }
    final ceiling = _retryCeiling(record.attempts);
    final delay = _chooseRetryDelay(record.attempts, ceiling);
    record
      ..isRetry = true
      ..readyAt = _elapsed.elapsed + delay;
    _pending.add(record);
  }

  Duration _chooseRetryDelay(int attempt, Duration ceiling) {
    try {
      final override = _retryDelayOverride;
      final delay = override == null
          ? Duration(
              microseconds: min(
                (_random.nextDouble() * (ceiling.inMicroseconds + 1)).floor(),
                ceiling.inMicroseconds,
              ),
            )
          : override(attempt, ceiling);
      if (delay < Duration.zero || delay > ceiling) {
        throw StateError('Retry delay must be between zero and its ceiling.');
      }
      return delay;
    } on Object {
      diagnostics.record(DiagnosticReason.exportFailed);
      return Duration.zero;
    }
  }

  Duration _retryCeiling(int attempts) {
    final maximumMicros = options.delivery.maxRetryDelay.inMicroseconds;
    var ceilingMicros = options.delivery.initialRetryDelay.inMicroseconds;
    for (var retry = 1; retry < attempts; retry++) {
      ceilingMicros = ceilingMicros >= maximumMicros ~/ 2 ? maximumMicros : ceilingMicros * 2;
    }
    return Duration(microseconds: ceilingMicros);
  }

  void _accept(_PendingRecord record) {
    _pendingBytes -= record.encodedBytes;
    record.disposition.accepted = true;
    _notifyDispositionWaiters();
  }

  void _drop(_PendingRecord record, DropReason reason) {
    _pendingBytes -= record.encodedBytes;
    _dropDisposition(record.disposition, reason);
  }

  void _dropDisposition(_RecordDisposition disposition, DropReason reason) {
    disposition.dropReason = reason;
    diagnostics.record(_diagnosticFor(reason));
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
      if (waiter.snapshot.every((state) => state.isTerminal)) {
        _completeFlush(waiter, timedOut: false);
      }
    }
    final closeSnapshot = _closeSnapshot;
    final closeResolved = _closeDeliveryResolved;
    if (closeSnapshot != null &&
        closeResolved != null &&
        !closeResolved.isCompleted &&
        closeSnapshot.every((state) => state.isTerminal)) {
      closeResolved.complete();
    }
  }

  void _notifyActiveDrained() {
    final activeDrained = _activeDrained;
    if (_active.isEmpty && activeDrained != null && !activeDrained.isCompleted) {
      activeDrained.complete();
    }
  }

  void _finishOutstandingAtShutdown() {
    _wakeTimer?.cancel();
    _wakeTimer = null;
    for (final record in _pending.toList()) {
      _pending.remove(record);
      _drop(record, DropReason.shutdown);
    }
    for (final active in _active.toList()) {
      _active.remove(active);
      active.timeout?.cancel();
      for (final record in active.records) {
        record.disposition.uncertain = true;
        _drop(record, DropReason.shutdown);
      }
    }
    _notifyActiveDrained();
  }

  void _completeFlush(_FlushWaiter waiter, {required bool timedOut}) {
    if (!_flushWaiters.remove(waiter)) return;
    waiter.timer?.cancel();
    waiter.completer.complete(_report(waiter.snapshot, timedOut: timedOut));
  }

  DeliveryReport _report(
    Iterable<_RecordDisposition> snapshot, {
    required bool timedOut,
    bool cleanupIncomplete = false,
  }) {
    var accepted = 0;
    var pending = 0;
    var uncertainDropped = 0;
    final dropped = <DropReason, int>{};
    for (final disposition in snapshot) {
      if (disposition.accepted) {
        accepted++;
      } else if (disposition.dropReason case final reason?) {
        dropped.update(reason, (count) => count + 1, ifAbsent: () => 1);
        if (disposition.uncertain) uncertainDropped++;
      } else {
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
    if (!_deliveryOpen ||
        _pending.isEmpty ||
        _active.length >= options.delivery.maxConcurrentExports) {
      _wakeTimer?.cancel();
      _wakeTimer = null;
      return;
    }
    final next = _pending
        .map((record) => record.readyAt)
        .reduce((left, right) => left <= right ? left : right);
    final delay = next - _elapsed.elapsed;
    if (delay <= Duration.zero) {
      _schedulePump();
      return;
    }
    _wakeTimer?.cancel();
    _wakeTimer = Timer(delay, _pump);
  }
}

/// Internal fixture bridge used by sibling-signal contract tests.
final class ChroniclerCaptureFixture {
  const ChroniclerCaptureFixture._();

  /// Submits a finalized sibling-signal [record] through capture policy.
  static void capture(Chronicler chronicler, ChroniclerRecord record) =>
      chronicler._runtime._captureFixture(record);

  /// Returns a recorder with valid operation correlation for identity tests.
  static ChroniclerRecorder withCorrelation(
    ChroniclerRecorder recorder, {
    required String traceId,
    required String spanId,
  }) => ChroniclerRecorder._(
    recorder._runtime,
    _RecorderAttribution(
      userId: recorder._attribution.userId,
      anonymousId: recorder._attribution.anonymousId,
      sessionId: recorder._attribution.sessionId,
      traceId: traceId,
      spanId: spanId,
    ),
  );
}

/// Internal fixture bridge for deterministic delivery tests.
final class ChroniclerDeliveryFixture {
  const ChroniclerDeliveryFixture._();

  /// Replaces retry jitter selection for deterministic delivery tests.
  static void selectRetryDelay(
    Chronicler chronicler,
    Duration Function(int attempt, Duration ceiling) selector,
  ) {
    chronicler._runtime._retryDelayOverride = selector;
  }

  /// Returns the current trace propagation switch.
  static bool propagationEnabled(Chronicler chronicler) => chronicler._runtime._propagationEnabled;

  /// Queues [records] for internal finalization during the next flush.
  static void finalizeOnNextFlush(
    Chronicler chronicler,
    Iterable<ChroniclerRecord> records,
  ) {
    chronicler._runtime._flushFinalizations.add(List.unmodifiable(records));
  }

  /// Returns the number of flush calls waiting on record dispositions.
  static int activeFlushes(Chronicler chronicler) => chronicler._runtime._flushWaiters.length;
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
  final _RecordDisposition disposition;
  Duration readyAt;
  int attempts = 0;
  bool isRetry = false;
  bool retryEligible = true;
}

final class _RecordDisposition {
  bool accepted = false;
  DropReason? dropReason;
  bool uncertain = false;

  bool get isTerminal => accepted || dropReason != null;
}

final class _FlushWaiter {
  _FlushWaiter(Set<_RecordDisposition> snapshot) : snapshot = Set.unmodifiable(snapshot);

  final Set<_RecordDisposition> snapshot;
  final completer = Completer<DeliveryReport>();
  Timer? timer;
}

final class _ActiveExport {
  _ActiveExport(this.records, this.deadline);
  final List<_PendingRecord> records;
  final Duration deadline;
  ExportAttempt? attempt;
  Timer? timeout;
  bool timedOut = false;
  bool cancellationRequested = false;
}

void _validateConfiguredLabel(
  RecordValidator validator,
  String value,
  String setting,
  int maxBytes,
) {
  try {
    if (value.isEmpty) throw const RecordValidationException('must be nonempty');
    validator.validateString(value, maxBytes, setting);
  } on RecordValidationException {
    throw ChroniclerConfigurationException(setting, 'is invalid');
  }
}

ChroniclerOptions _validateAndSnapshotOptions(ChroniclerOptions options) {
  final delivery = options.delivery;
  final positiveIntegers = <String, int>{
    'maxPendingRecords': delivery.maxPendingRecords,
    'maxPendingBytes': delivery.maxPendingBytes,
    'maxRecordBytes': delivery.maxRecordBytes,
    'maxBatchRecords': delivery.maxBatchRecords,
    'maxBatchBytes': delivery.maxBatchBytes,
    'maxConcurrentExports': delivery.maxConcurrentExports,
    'maxAttempts': delivery.maxAttempts,
  };
  for (final MapEntry(:key, :value) in positiveIntegers.entries) {
    if (value <= 0) throw ChroniclerConfigurationException(key, 'must be positive');
  }
  final positiveDurations = <String, Duration>{
    'batchInterval': delivery.batchInterval,
    'attemptTimeout': delivery.attemptTimeout,
    'initialRetryDelay': delivery.initialRetryDelay,
    'maxRetryDelay': delivery.maxRetryDelay,
    'flushTimeout': delivery.flushTimeout,
    'closeTimeout': delivery.closeTimeout,
  };
  for (final MapEntry(:key, :value) in positiveDurations.entries) {
    if (value <= Duration.zero) {
      throw ChroniclerConfigurationException(key, 'must be positive');
    }
  }
  if (delivery.maxRetryDelay < delivery.initialRetryDelay) {
    throw const ChroniclerConfigurationException(
      'maxRetryDelay',
      'must be at least initialRetryDelay',
    );
  }
  if (delivery.cleanupReserve < Duration.zero || delivery.cleanupReserve >= delivery.closeTimeout) {
    throw const ChroniclerConfigurationException(
      'cleanupReserve',
      'must be nonnegative and less than closeTimeout',
    );
  }
  if (delivery.maxPendingBytes < delivery.maxRecordBytes) {
    throw const ChroniclerConfigurationException(
      'maxPendingBytes',
      'must fit maxRecordBytes',
    );
  }
  if (delivery.maxBatchBytes < delivery.maxRecordBytes + 32) {
    throw const ChroniclerConfigurationException(
      'maxBatchBytes',
      'must fit maxRecordBytes and batch framing',
    );
  }
  final limits = options.limits;
  final limitValues = <String, int>{
    'maxIdBytes': limits.maxIdBytes,
    'maxLabelBytes': limits.maxLabelBytes,
    'maxMapEntries': limits.maxMapEntries,
    'maxListItems': limits.maxListItems,
    'maxDepth': limits.maxDepth,
    'maxKeyBytes': limits.maxKeyBytes,
    'maxStringBytes': limits.maxStringBytes,
    'maxErrorMessageBytes': limits.maxErrorMessageBytes,
    'maxStackTraceBytes': limits.maxStackTraceBytes,
  };
  for (final MapEntry(:key, :value) in limitValues.entries) {
    if (value <= 0) throw ChroniclerConfigurationException(key, 'must be positive');
  }
  if (limits.maxCauses < 0) {
    throw const ChroniclerConfigurationException('maxCauses', 'must be nonnegative');
  }
  for (final MapEntry(:key, :value) in {
    'logs': options.sampling.logs,
    'events': options.sampling.events,
    'traces': options.sampling.traces,
  }.entries) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ChroniclerConfigurationException(key, 'sampling rate must be between zero and one');
    }
  }
  if (options.diagnostics.notificationInterval <= Duration.zero) {
    throw const ChroniclerConfigurationException(
      'notificationInterval',
      'must be positive',
    );
  }
  final terms = <String>{};
  for (final term in options.redaction.fieldTerms) {
    if (term.isEmpty) {
      throw const ChroniclerConfigurationException('fieldTerms', 'must contain nonempty terms');
    }
    terms.add(term.toLowerCase());
  }
  return ChroniclerOptions(
    delivery: delivery,
    limits: limits,
    sampling: options.sampling,
    redaction: RedactionOptions(
      fieldTerms: Set.unmodifiable(terms),
      beforeRecord: options.redaction.beforeRecord,
    ),
    diagnostics: options.diagnostics,
    metrics: options.metrics,
    tracing: options.tracing,
    enabledSignals: Set.unmodifiable(options.enabledSignals),
  );
}

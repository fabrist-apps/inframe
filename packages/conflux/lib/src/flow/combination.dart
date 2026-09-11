import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/cause.dart' show CauseGroup, CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show EffectExecution, ScopeAccess;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';

/// Opens cursors that combine multiple Flow sources.
abstract final class CombinationFlowSource {
  /// Opens every source for position-based concurrent pulls.
  static Effect<FlowSourceCursor<List<A>, E>, E> openZip<A, E>(
    Iterable<OpenFlowCursor<A, E>> sources,
  ) => Effect.build(($) async {
    final cursors = <FlowSourceCursor<A, E>>[];
    for (final source in sources) {
      cursors.add(await $(Effect.defer(source)));
    }
    return _ZipCursor(cursors);
  });

  /// Opens indexed source events for latest-value combination.
  static Effect<FlowSourceCursor<List<A>, E>, E> openCombineLatest<A, E>(
    Iterable<OpenFlowCursor<A, E>> sources, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final sourceList = List<OpenFlowCursor<A, E>>.of(sources);
    final mailbox = FlowMailbox<List<A>, E>(capacity, overflow, onOverflow);
    final coordinator = _CombineLatestCoordinator<A, E>(
      mailbox,
      execution,
      sourceList.length,
    );
    if (!_registerCombinationCleanup(mailbox, coordinator.close, execution)) {
      return const Failed(Interrupted(ScopeClosed()));
    }
    coordinator.start(sourceList);
    return Succeeded(_CombinationCursor(mailbox));
  });

  /// Opens primary and secondary events for trigger-based combination.
  static Effect<FlowSourceCursor<C, E>, E> openWithLatestFrom<A, B, C, E>(
    OpenFlowCursor<A, E> primary,
    OpenFlowCursor<B, E> secondary,
    C Function(A primary, B latest) combine, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<C, E>(capacity, overflow, onOverflow);
    final coordinator = _WithLatestCoordinator<A, B, C, E>(
      mailbox,
      combine,
      execution,
    );
    if (!_registerCombinationCleanup(mailbox, coordinator.close, execution)) {
      return const Failed(Interrupted(ScopeClosed()));
    }
    coordinator.start(primary, secondary);
    return Succeeded(_CombinationCursor(mailbox));
  });
}

bool _registerCombinationCleanup<A, E>(
  FlowMailbox<A, E> mailbox,
  void Function() closeCoordinator,
  EffectExecution execution,
) {
  final registered = ScopeAccess.addFinalizer(
    execution.scope,
    Effect.sync(() {
      closeCoordinator();
      mailbox.close();
    }),
    execution.context,
    execution.clock,
  );
  if (!registered) {
    closeCoordinator();
    mailbox.close();
  }
  return registered;
}

final class _ZipCursor<A, E> implements FlowSourceCursor<List<A>, E> {
  const _ZipCursor(this._sources);

  final List<FlowSourceCursor<A, E>> _sources;

  @override
  Effect<Option<List<A>>, E> next() => EffectAccess.create((execution) async {
    if (_sources.isEmpty) return const Succeeded(None());
    final pending = <int, Fiber<Option<A>, E>>{
      for (final entry in _sources.indexed)
        entry.$1: ScopeAccess.fork(
          execution.scope,
          entry.$2.next(),
          execution,
        ),
    };
    final results = List<Option<A>?>.filled(_sources.length, null);

    while (pending.isNotEmpty) {
      final completed = await Future.any(
        pending.entries.map(
          (entry) => entry.value.exit.then(
            (exit) => (index: entry.key, exit: exit),
          ),
        ),
      );
      pending.remove(completed.index);
      switch (completed.exit) {
        case Failed<Option<A>, E>(:final cause):
          final cleanup = await _interruptZipPulls(pending.values);
          return Failed(CauseGroup.sequential([cause, ?cleanup])!);
        case Succeeded<Option<A>, E>(value: None()):
          final cleanup = await _interruptZipPulls(pending.values);
          return cleanup == null ? const Succeeded(None()) : Failed(cleanup);
        case Succeeded<Option<A>, E>(:final value):
          results[completed.index] = value;
      }
    }

    final values = <A>[];
    for (final result in results) {
      switch (result) {
        case Some<A>(:final value):
          values.add(value);
        case None() || null:
          return Failed(
            Defect(
              StateError('Zip completed without one value from each source.'),
              StackTrace.current,
            ),
          );
      }
    }
    return Succeeded(Some(List.unmodifiable(values)));
  });
}

Future<Cause<E>?> _interruptZipPulls<E>(
  Iterable<Fiber<Option<Object?>, E>> pulls,
) async {
  final exits = await Future.wait(
    pulls.map((fiber) => fiber.interrupt(const FlowZipFinished())),
  );
  return CauseGroup.parallel(
    exits
        .whereType<Failed<Option<Object?>, E>>()
        .map((exit) => exit.cause.defectsOnly)
        .whereType<Cause<Never>>()
        .map((cause) => cause.mapExpected<E>(_widenNever)),
  );
}

final class _CombinationCursor<A, E> implements FlowSourceCursor<A, E> {
  const _CombinationCursor(this._mailbox);

  final FlowMailbox<A, E> _mailbox;

  @override
  Effect<Option<A>, E> next() => _mailbox.take();
}

final class _CombineLatestCoordinator<A, E> {
  _CombineLatestCoordinator(
    this._mailbox,
    this._execution,
    int sourceCount,
  ) : _latest = List<Option<A>>.filled(sourceCount, const None()),
      _remaining = sourceCount;

  final FlowMailbox<List<A>, E> _mailbox;
  final EffectExecution _execution;
  final List<Option<A>> _latest;
  final Map<int, Fiber<void, E>> _fibers = {};
  int _remaining;
  var _terminalizing = false;
  var _closed = false;

  void start(List<OpenFlowCursor<A, E>> sources) {
    if (sources.isEmpty) {
      _terminalizing = true;
      _mailbox.complete();
      return;
    }
    for (final entry in sources.indexed) {
      final index = entry.$1;
      final fiber = ScopeAccess.fork(
        _execution.scope,
        pumpFlow(entry.$2, (value) => _accept(index, value)),
        _execution,
      );
      _fibers[index] = fiber;
      unawaited(fiber.exit.then((exit) => _finished(index, fiber, exit)));
    }
  }

  Effect<void, E> _accept(int index, A value) => EffectAccess.create((execution) {
    if (_terminalizing || _closed) return Future.value(const Succeeded(null));
    _latest[index] = Some(value);
    if (_latest.any((value) => value is None)) {
      return Future.value(const Succeeded(null));
    }
    final snapshot = List<A>.unmodifiable([
      for (final latest in _latest)
        switch (latest) {
          Some<A>(:final value) => value,
          None() => throw StateError('Missing latest Flow value.'),
        },
    ]);
    return EffectAccess.evaluate(_mailbox.offer(snapshot), execution);
  });

  Future<void> _finished(
    int index,
    Fiber<void, E> fiber,
    Exit<void, E> exit,
  ) async {
    if (identical(_fibers[index], fiber)) _fibers.remove(index);
    if (_terminalizing || _closed || _execution.cancellation.isCancelled) return;
    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        if (_latest[index] case None()) {
          await _completeEarly();
          return;
        }
        _remaining -= 1;
        if (_remaining == 0) {
          _terminalizing = true;
          _mailbox.complete();
        }
    }
  }

  Future<void> _completeEarly() async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    final cleanup = await _interruptCombination(_fibers.values);
    if (cleanup == null) {
      _mailbox.complete();
    } else {
      _mailbox.fail(cleanup.mapExpected<E>(_widenNever));
    }
  }

  Future<void> _fail(Cause<E> cause) async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    final cleanup = await _interruptCombination(_fibers.values);
    _mailbox.fail(
      CauseGroup.sequential([
        cause,
        ?cleanup?.mapExpected<E>(_widenNever),
      ])!,
    );
  }

  void close() => _closed = true;
}

final class _WithLatestCoordinator<A, B, C, E> {
  _WithLatestCoordinator(this._mailbox, this._combine, this._execution);

  final FlowMailbox<C, E> _mailbox;
  final C Function(A primary, B latest) _combine;
  final EffectExecution _execution;
  final Map<int, Fiber<void, E>> _fibers = {};
  Option<B> _latest = const None();
  var _terminalizing = false;
  var _closed = false;

  void start(
    OpenFlowCursor<A, E> primary,
    OpenFlowCursor<B, E> secondary,
  ) {
    _startPump(0, primary, _acceptPrimary);
    _startPump(1, secondary, _acceptSecondary);
  }

  void _startPump<T>(
    int index,
    OpenFlowCursor<T, E> source,
    Effect<void, E> Function(T value) emit,
  ) {
    final fiber = ScopeAccess.fork(
      _execution.scope,
      pumpFlow(source, emit),
      _execution,
    );
    _fibers[index] = fiber;
    unawaited(fiber.exit.then((exit) => _finished(index, fiber, exit)));
  }

  Effect<void, E> _acceptPrimary(A value) => EffectAccess.create((execution) {
    if (_terminalizing || _closed) return Future.value(const Succeeded(null));
    final latest = _latest;
    if (latest case None()) return Future.value(const Succeeded(null));
    final combined = _combine(value, (latest as Some<B>).value);
    return EffectAccess.evaluate(_mailbox.offer(combined), execution);
  });

  Effect<void, E> _acceptSecondary(B value) => Effect.sync(() {
    if (!_terminalizing && !_closed) _latest = Some(value);
  }).mapError<E>(_widenNever);

  Future<void> _finished(
    int index,
    Fiber<void, E> fiber,
    Exit<void, E> exit,
  ) async {
    if (identical(_fibers[index], fiber)) _fibers.remove(index);
    if (_terminalizing || _closed || _execution.cancellation.isCancelled) return;
    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        if (index == 0 || _latest is None) await _complete();
    }
  }

  Future<void> _complete() async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    final cleanup = await _interruptCombination(_fibers.values);
    if (cleanup == null) {
      _mailbox.complete();
    } else {
      _mailbox.fail(cleanup.mapExpected<E>(_widenNever));
    }
  }

  Future<void> _fail(Cause<E> cause) async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    final cleanup = await _interruptCombination(_fibers.values);
    _mailbox.fail(
      CauseGroup.sequential([
        cause,
        ?cleanup?.mapExpected<E>(_widenNever),
      ])!,
    );
  }

  void close() => _closed = true;
}

Future<Cause<Never>?> _interruptCombination<E>(
  Iterable<Fiber<void, E>> fibers,
) async {
  final exits = await Future.wait(
    fibers.map((fiber) => fiber.interrupt(const _CombinationFinished())),
  );
  return CauseGroup.parallel(
    exits
        .whereType<Failed<void, E>>()
        .map((exit) => exit.cause.defectsOnly)
        .whereType<Cause<Never>>(),
  );
}

final class _CombinationFinished {
  const _CombinationFinished();

  @override
  String toString() => 'Flow combination finished';
}

E _widenNever<E>(Never error) => error;

/// Why Zip interrupted unused pulls after a source completed or failed.
final class FlowZipFinished {
  /// Creates the stable zip-finished interruption reason.
  const FlowZipFinished();

  @override
  String toString() => 'Flow zip finished';
}

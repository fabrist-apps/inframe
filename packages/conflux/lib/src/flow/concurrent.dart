import 'dart:async';
import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/coordination/waiter.dart';
import 'package:conflux/src/effect/cause.dart' show CauseGroup, CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show EffectExecution, ScopeAccess;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';

/// Opens cursors for concurrent Flow composition.
abstract final class ConcurrentFlowSource {
  /// Merges all [sources] into one bounded output cursor.
  static Effect<FlowSourceCursor<A, E>, E> openMerge<A, E>(
    Iterable<OpenFlowCursor<A, E>> sources, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<A, E>(capacity, overflow, onOverflow);
    final coordinator = _MergeCoordinator<A, E>(mailbox, execution);
    _registerCleanup(mailbox, coordinator, execution);
    coordinator.startSources(sources);
    return Succeeded(_ConcurrentCursor(mailbox));
  });

  /// Maps outer values to at most [concurrency] active inner cursors.
  static Effect<FlowSourceCursor<B, E>, E> openMergeMap<A, B, E>(
    OpenFlowCursor<A, E> upstream,
    OpenFlowCursor<B, E> Function(A value) transform, {
    required int concurrency,
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<B, E>(capacity, overflow, onOverflow);
    final coordinator = _MergeCoordinator<B, E>(mailbox, execution);
    final gate = _ConcurrencyGate(concurrency);
    _registerCleanup(mailbox, coordinator, execution, gate: gate);
    coordinator.startMappedSource(upstream, transform, gate);
    return Succeeded(_ConcurrentCursor(mailbox));
  });

  static void _registerCleanup<A, E>(
    FlowMailbox<A, E> mailbox,
    _MergeCoordinator<A, E> coordinator,
    EffectExecution execution, {
    _ConcurrencyGate? gate,
  }) {
    ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync(() {
        coordinator.close();
        gate?.close();
        mailbox.close();
      }),
      execution.context,
      execution.clock,
    );
  }
}

final class _MergeCoordinator<A, E> {
  _MergeCoordinator(this._mailbox, this._execution);

  final FlowMailbox<A, E> _mailbox;
  final EffectExecution _execution;
  final Map<int, Fiber<void, E>> _fibers = {};
  final Map<int, _PumpKind> _kinds = {};
  var _nextId = 0;
  var _remainingSources = 0;
  var _activeInners = 0;
  var _outerFinished = false;
  var _terminalizing = false;
  var _closed = false;
  _ConcurrencyGate? _gate;

  void startSources(Iterable<OpenFlowCursor<A, E>> sources) {
    final sourceList = List<OpenFlowCursor<A, E>>.of(sources);
    _remainingSources = sourceList.length;
    if (sourceList.isEmpty) {
      _mailbox.complete();
      return;
    }
    for (final source in sourceList) {
      _startPump(source, _mailbox.offer, _PumpKind.source);
    }
  }

  void startMappedSource<B>(
    OpenFlowCursor<B, E> upstream,
    OpenFlowCursor<A, E> Function(B value) transform,
    _ConcurrencyGate gate,
  ) {
    _gate = gate;
    _startPump(
      upstream,
      (value) => gate.acquire().mapError<E>(_widenNever).tap((_) {
        return Effect.sync(() {
          if (_closed || _terminalizing) {
            gate.release();
            return;
          }
          _activeInners += 1;
          _startPump(
            () => Effect.defer(() => transform(value)()),
            _mailbox.offer,
            _PumpKind.inner,
          );
        }).mapError<E>(_widenNever);
      }),
      _PumpKind.outer,
    );
  }

  void _startPump<B>(
    OpenFlowCursor<B, E> open,
    Effect<void, E> Function(B value) emit,
    _PumpKind kind,
  ) {
    final id = _nextId++;
    final fiber = ScopeAccess.fork(
      _execution.scope,
      _pump(open, emit),
      _execution,
    );
    _fibers[id] = fiber;
    _kinds[id] = kind;
    unawaited(fiber.exit.then((exit) => _finished(id, exit)));
  }

  Effect<void, E> _pump<B>(
    OpenFlowCursor<B, E> open,
    Effect<void, E> Function(B value) emit,
  ) => Effect.build(($) async {
    final cursor = await $(Effect.defer(open));
    while (true) {
      switch (await $(cursor.next())) {
        case Some<B>(:final value):
          await $(Effect.defer(() => emit(value)));
        case None():
          return;
      }
    }
  });

  Future<void> _finished(int id, Exit<void, E> exit) async {
    _fibers.remove(id);
    final kind = _kinds.remove(id);
    if (kind == _PumpKind.inner) {
      _activeInners -= 1;
      _gate?.release();
    }
    if (_closed || _execution.cancellation.isCancelled || _terminalizing) return;

    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        _completePump(kind);
    }
  }

  void _completePump(_PumpKind? kind) {
    switch (kind) {
      case _PumpKind.source:
        _remainingSources -= 1;
        if (_remainingSources == 0) _mailbox.complete();
      case _PumpKind.outer:
        _outerFinished = true;
        if (_activeInners == 0) _mailbox.complete();
      case _PumpKind.inner:
        if (_outerFinished && _activeInners == 0) _mailbox.complete();
      case null:
        break;
    }
  }

  Future<void> _fail(Cause<E> original) async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    final siblings = List<Fiber<void, E>>.of(_fibers.values);
    final exits = await Future.wait(
      siblings.map((fiber) => fiber.interrupt(const ConcurrentFlowFailed())),
    );
    final cleanupFailures = exits
        .whereType<Failed<void, E>>()
        .map((exit) => exit.cause.defectsOnly)
        .whereType<Cause<Never>>()
        .map((cause) => cause.mapExpected<E>(_widenNever));
    final parallelCleanup = CauseGroup.parallel(cleanupFailures);
    _mailbox.fail(CauseGroup.sequential([original, ?parallelCleanup])!);
  }

  void close() {
    _closed = true;
  }
}

enum _PumpKind { source, outer, inner }

final class _ConcurrentCursor<A, E> implements FlowSourceCursor<A, E> {
  const _ConcurrentCursor(this._mailbox);

  final FlowMailbox<A, E> _mailbox;

  @override
  Effect<Option<A>, E> next() => _mailbox.take();
}

final class _ConcurrencyGate {
  _ConcurrencyGate(this.limit);

  final int limit;
  final ListQueue<CoordinationWaiter<void>> _waiters = ListQueue();
  var _active = 0;
  var _closed = false;

  Effect<void, Never> acquire() => Effect.defer(() {
    final waiter = CoordinationWaiter<void>();
    return waiter.awaitValue(
      onStart: () {
        if (_closed) {
          waiter.interrupt(const ConcurrentFlowClosed());
        } else if (_active < limit) {
          _active += 1;
          waiter.succeed(null);
        } else {
          _waiters.addLast(waiter);
        }
      },
      onCancel: () => _waiters.remove(waiter),
    );
  });

  void release() {
    if (_active == 0) return;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().succeed(null);
      return;
    }
    _active -= 1;
  }

  void close() {
    _closed = true;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().interrupt(const ConcurrentFlowClosed());
    }
  }
}

E _widenNever<E>(Never error) => error;

/// Why a concurrent Flow stopped sibling work after one failure.
final class ConcurrentFlowFailed {
  /// Creates the stable fail-fast interruption reason.
  const ConcurrentFlowFailed();

  @override
  String toString() => 'Concurrent Flow failed';
}

/// Why a concurrent Flow coordinator stopped accepting work.
final class ConcurrentFlowClosed {
  /// Creates the stable coordinator-closed interruption reason.
  const ConcurrentFlowClosed();

  @override
  String toString() => 'Concurrent Flow closed';
}

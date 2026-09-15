import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/coordination/waiter.dart';
import 'package:conflux/src/effect/cause.dart' show CauseGroup, CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show EffectExecution, ScopeAccess;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';
import 'package:context/context.dart';

/// Opens cursors for concurrent Flow composition.
abstract final class ConcurrentFlowSource {
  /// Merges all [sources] into one bounded output cursor.
  static Effect<FlowSourceCursor<A, E>, E> openMerge<A, E>(
    Iterable<OpenFlowCursor<A, E>> sources, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<A, E>(capacity, overflow, onOverflow);
    final coordinator = _MergeCoordinator<A, E>(mailbox, execution);
    if (!_registerCleanup(mailbox, coordinator, execution)) {
      return const Failed(Interrupted(ScopeClosed()));
    }
    coordinator.startSources(sources);
    return Succeeded(mailbox);
  });

  /// Maps outer values to at most [concurrency] active inner cursors.
  static Effect<FlowSourceCursor<B, E>, E> openMergeMap<A, B, E>(
    OpenFlowCursor<A, E> upstream,
    OpenFlowCursor<B, E> Function(A value, Context context) transform, {
    required int concurrency,
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<B, E>(capacity, overflow, onOverflow);
    final coordinator = _MergeCoordinator<B, E>(mailbox, execution);
    final gate = _ConcurrencyGate(concurrency);
    if (!_registerCleanup(mailbox, coordinator, execution, gate: gate)) {
      return const Failed(Interrupted(ScopeClosed()));
    }
    coordinator.startMappedSource(upstream, transform, gate);
    return Succeeded(mailbox);
  });

  /// Replaces an active inner cursor after its cleanup completes.
  static Effect<FlowSourceCursor<B, E>, E> openSwitchMap<A, B, E>(
    OpenFlowCursor<A, E> upstream,
    OpenFlowCursor<B, E> Function(A value, Context context) transform, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<_GenerationValue<B>, E>(
      capacity,
      overflow,
      onOverflow,
    );
    final coordinator = _SwitchCoordinator<A, B, E>(
      upstream,
      transform,
      mailbox,
      execution,
    );
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync((_) {
        coordinator.close();
        mailbox.close();
      }),
      execution.context,
      execution.clock,
    );
    if (!registered) {
      coordinator.close();
      mailbox.close();
      return const Failed(Interrupted(ScopeClosed()));
    }
    coordinator.start();
    return Succeeded(_SwitchCursor(mailbox, coordinator));
  });

  /// Ignores outer values while one inner cursor remains active.
  static Effect<FlowSourceCursor<B, E>, E> openExhaustMap<A, B, E>(
    OpenFlowCursor<A, E> upstream,
    OpenFlowCursor<B, E> Function(A value, Context context) transform, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow, Context context)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final mailbox = FlowMailbox<B, E>(capacity, overflow, onOverflow);
    final coordinator = _ExhaustCoordinator<A, B, E>(
      upstream,
      transform,
      mailbox,
      execution,
    );
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync((_) {
        coordinator.close();
        mailbox.close();
      }),
      execution.context,
      execution.clock,
    );
    if (!registered) {
      coordinator.close();
      mailbox.close();
      return const Failed(Interrupted(ScopeClosed()));
    }
    coordinator.start();
    return Succeeded(mailbox);
  });

  static bool _registerCleanup<A, E>(
    FlowMailbox<A, E> mailbox,
    _MergeCoordinator<A, E> coordinator,
    EffectExecution execution, {
    _ConcurrencyGate? gate,
  }) {
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync((_) {
        coordinator.close();
        gate?.close();
        mailbox.close();
      }),
      execution.context,
      execution.clock,
    );
    if (!registered) {
      coordinator.close();
      gate?.close();
      mailbox.close();
    }
    return registered;
  }
}

final class _MergeCoordinator<A, E> {
  _MergeCoordinator(this._mailbox, this._execution);

  final FlowMailbox<A, E> _mailbox;
  final EffectExecution _execution;
  final Map<int, ({Fiber<void, E> fiber, bool releasesPermit})> _pumps = {};
  var _nextId = 0;
  var _terminalizing = false;
  var _closed = false;
  _ConcurrencyGate? _gate;

  void startSources(Iterable<OpenFlowCursor<A, E>> sources) {
    final sourceList = List<OpenFlowCursor<A, E>>.of(sources);
    if (sourceList.isEmpty) {
      _mailbox.complete();
      return;
    }
    for (final source in sourceList) {
      _startPump(source, _mailbox.offer);
    }
  }

  void startMappedSource<B>(
    OpenFlowCursor<B, E> upstream,
    OpenFlowCursor<A, E> Function(B value, Context context) transform,
    _ConcurrencyGate gate,
  ) {
    _gate = gate;
    _startPump(
      upstream,
      (value) =>
          gate.acquire().mapError<E>((value, _) => _widenNever(value! as Never)).tap((_, context) {
            return Effect.sync((_) {
              if (_closed || _terminalizing) {
                gate.release();
                return;
              }
              _startPump(
                () => Effect.defer((_) => transform(value, context)()),
                _mailbox.offer,
                releasesPermit: true,
              );
            }).mapError<E>((value, _) => _widenNever(value! as Never));
          }),
    );
  }

  void _startPump<B>(
    OpenFlowCursor<B, E> open,
    Effect<void, E> Function(B value) emit, {
    bool releasesPermit = false,
  }) {
    final id = _nextId++;
    final fiber = ScopeAccess.fork(
      _execution.scope,
      pumpFlow(open, emit),
      _execution,
    );
    _pumps[id] = (fiber: fiber, releasesPermit: releasesPermit);
    unawaited(fiber.exit.then((exit) => _finished(id, exit)));
  }

  Future<void> _finished(int id, Exit<void, E> exit) async {
    final pump = _pumps.remove(id);
    if (pump?.releasesPermit ?? false) {
      _gate?.release();
    }
    if (_closed || _execution.cancellation.isCancelled || _terminalizing) return;

    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        if (_pumps.isEmpty) _mailbox.complete();
    }
  }

  Future<void> _fail(Cause<E> original) async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    final siblings = _pumps.values.map((pump) => pump.fiber).toList();
    final exits = await Future.wait(
      siblings.map((fiber) => fiber.interrupt(const ConcurrentFlowFailed())),
    );
    _mailbox.fail(_appendParallelCleanup(original, exits));
  }

  void close() {
    _closed = true;
  }
}

final class _SwitchCoordinator<Outer, A, E> {
  _SwitchCoordinator(
    this._upstream,
    this._transform,
    this._mailbox,
    this._execution,
  );

  final OpenFlowCursor<Outer, E> _upstream;
  final OpenFlowCursor<A, E> Function(Outer value, Context context) _transform;
  final FlowMailbox<_GenerationValue<A>, E> _mailbox;
  final EffectExecution _execution;
  final _LatestSlot<Outer> _slot = _LatestSlot();
  Fiber<void, E>? _outer;
  Fiber<void, E>? _supervisor;
  Fiber<void, E>? _inner;
  Fiber<void, E>? _replacing;
  var _outerDone = false;
  var _terminalizing = false;
  var _closed = false;

  int get generation => _slot.generation;

  void start() {
    final supervisor = ScopeAccess.fork(
      _execution.scope,
      _supervise(),
      _execution,
    );
    _supervisor = supervisor;
    unawaited(supervisor.exit.then((exit) => _supervisorFinished(supervisor, exit)));

    final outer = ScopeAccess.fork(
      _execution.scope,
      pumpFlow(
        _upstream,
        (value) =>
            Effect.sync((_) => _slot.put(value))
                .mapError<E>((value, _) => _widenNever(value! as Never)),
      ),
      _execution,
    );
    _outer = outer;
    unawaited(outer.exit.then((exit) => _outerFinished(outer, exit)));
  }

  Effect<void, E> _supervise() => EffectAccess.create((execution) async {
    while (true) {
      final pending = _slot.takePending();
      if (pending case Some<_GenerationValue<Outer>>(:final value)) {
        final active = _inner;
        if (active != null) {
          _replacing = active;
          final exit = await active.interrupt(const FlowInnerReplaced());
          if (identical(_replacing, active)) _replacing = null;
          if (identical(_inner, active)) _inner = null;
          if (exit case Failed<void, E>(:final cause)) {
            final primary = cause.primaryError;
            if (primary case Some<E>()) return Failed(cause);
            final defects = cause.defectsOnly;
            if (defects != null) {
              return Failed(defects.mapExpected<E>(_widenNever));
            }
          }
        }

        if (_slot.generation != value.generation) continue;
        _startInner(value.value, value.generation);
        continue;
      }

      if (_outerDone && _inner == null) {
        _mailbox.complete();
        return const Succeeded(null);
      }
      final changed = await EffectAccess.evaluate(_slot.wait(), execution);
      if (changed case Failed<void, Never>(:final cause)) {
        return Failed(cause.mapExpected<E>(_widenNever));
      }
    }
  });

  void _startInner(Outer value, int generation) {
    final inner = ScopeAccess.fork(
      _execution.scope,
      pumpFlow(
        () => Effect.defer((context) => _transform(value, context)()),
        (value) => _mailbox.offer(_GenerationValue(value, generation)),
      ),
      _execution,
    );
    _inner = inner;
    unawaited(inner.exit.then((exit) => _innerFinished(inner, exit)));
  }

  Future<void> _outerFinished(Fiber<void, E> outer, Exit<void, E> exit) async {
    if (identical(_outer, outer)) _outer = null;
    if (_ignoreTerminalCallback) return;
    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        _outerDone = true;
        _slot.signal();
    }
  }

  Future<void> _supervisorFinished(
    Fiber<void, E> supervisor,
    Exit<void, E> exit,
  ) async {
    if (identical(_supervisor, supervisor)) _supervisor = null;
    if (_ignoreTerminalCallback) return;
    if (exit case Failed<void, E>(:final cause)) await _fail(cause);
  }

  Future<void> _innerFinished(Fiber<void, E> inner, Exit<void, E> exit) async {
    if (identical(_replacing, inner)) {
      if (identical(_inner, inner)) _inner = null;
      return;
    }
    if (!identical(_inner, inner)) return;
    _inner = null;
    if (_ignoreTerminalCallback) return;
    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        _slot.signal();
    }
  }

  bool get _ignoreTerminalCallback =>
      _closed || _execution.cancellation.isCancelled || _terminalizing;

  Future<void> _fail(Cause<E> original) async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    _slot.close();
    final replacing = _replacing;
    final siblings = <Fiber<void, E>>[
      ?_outer,
      ?_supervisor,
      if (_inner != null && !identical(_inner, replacing)) _inner!,
    ];
    _outer = null;
    _supervisor = null;
    _inner = null;
    _replacing = null;
    final exits = await Future.wait(
      siblings.map((fiber) => fiber.interrupt(const ConcurrentFlowFailed())),
    );
    _mailbox.fail(_appendParallelCleanup(original, exits));
  }

  void close() {
    _closed = true;
    _slot.close();
  }
}

final class _SwitchCursor<A, E> implements FlowSourceCursor<A, E> {
  const _SwitchCursor(this._mailbox, this._coordinator);

  final FlowMailbox<_GenerationValue<A>, E> _mailbox;
  final _SwitchCoordinator<Object?, A, E> _coordinator;

  @override
  Effect<Option<A>, E> next() => Effect.build(($) async {
    while (true) {
      switch (await $(_mailbox.take())) {
        case Some<_GenerationValue<A>>(:final value)
            when value.generation == _coordinator.generation:
          return Some(value.value);
        case Some<_GenerationValue<A>>():
          continue;
        case None():
          return const None();
      }
    }
  });
}

final class _ExhaustCoordinator<Outer, A, E> {
  _ExhaustCoordinator(
    this._upstream,
    this._transform,
    this._mailbox,
    this._execution,
  );

  final OpenFlowCursor<Outer, E> _upstream;
  final OpenFlowCursor<A, E> Function(Outer value, Context context) _transform;
  final FlowMailbox<A, E> _mailbox;
  final EffectExecution _execution;
  Fiber<void, E>? _outer;
  Fiber<void, E>? _inner;
  var _outerDone = false;
  var _terminalizing = false;
  var _closed = false;

  void start() {
    final outer = ScopeAccess.fork(
      _execution.scope,
      pumpFlow(_upstream, _accept),
      _execution,
    );
    _outer = outer;
    unawaited(outer.exit.then((exit) => _outerFinished(outer, exit)));
  }

  Effect<void, E> _accept(Outer value) => Effect.sync((_) {
    if (_inner != null || _terminalizing || _closed) return;
    final inner = ScopeAccess.fork(
      _execution.scope,
      pumpFlow(
        () => Effect.defer((context) => _transform(value, context)()),
        _mailbox.offer,
      ),
      _execution,
    );
    _inner = inner;
    unawaited(inner.exit.then((exit) => _innerFinished(inner, exit)));
  }).mapError<E>((value, _) => _widenNever(value! as Never));

  Future<void> _outerFinished(Fiber<void, E> outer, Exit<void, E> exit) async {
    if (identical(_outer, outer)) _outer = null;
    if (_ignoreTerminalCallback) return;
    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        _outerDone = true;
        if (_inner == null) _mailbox.complete();
    }
  }

  Future<void> _innerFinished(Fiber<void, E> inner, Exit<void, E> exit) async {
    if (!identical(_inner, inner)) return;
    _inner = null;
    if (_ignoreTerminalCallback) return;
    switch (exit) {
      case Failed<void, E>(:final cause):
        await _fail(cause);
      case Succeeded<void, E>():
        if (_outerDone) _mailbox.complete();
    }
  }

  bool get _ignoreTerminalCallback =>
      _closed || _execution.cancellation.isCancelled || _terminalizing;

  Future<void> _fail(Cause<E> original) async {
    if (_terminalizing || _closed) return;
    _terminalizing = true;
    final siblings = <Fiber<void, E>>[?_outer, ?_inner];
    _outer = null;
    _inner = null;
    final exits = await Future.wait(
      siblings.map((fiber) => fiber.interrupt(const ConcurrentFlowFailed())),
    );
    _mailbox.fail(_appendParallelCleanup(original, exits));
  }

  void close() {
    _closed = true;
  }
}

final class _LatestSlot<A> {
  Option<_GenerationValue<A>> _pending = const None();
  CoordinationWaiter<void>? _waiter;
  var _generation = 0;
  var _signalled = false;
  var _closed = false;

  int get generation => _generation;

  void put(A value) {
    if (_closed) return;
    _generation += 1;
    _pending = Some(_GenerationValue(value, _generation));
    signal();
  }

  Option<_GenerationValue<A>> takePending() {
    final pending = _pending;
    _pending = const None();
    return pending;
  }

  Effect<void, Never> wait() => Effect.defer((_) {
    final waiter = CoordinationWaiter<void>();
    return waiter.awaitValue(
      onStart: () {
        if (_closed) {
          waiter.interrupt(const ConcurrentFlowClosed());
        } else if (_pending case Some<_GenerationValue<A>>()) {
          waiter.succeed(null);
        } else if (_signalled) {
          _signalled = false;
          waiter.succeed(null);
        } else {
          _waiter = waiter;
        }
      },
      onCancel: () {
        if (identical(_waiter, waiter)) _waiter = null;
      },
    );
  });

  void signal() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter == null) {
      if (_pending is None) _signalled = true;
    } else {
      waiter.succeed(null);
    }
  }

  void close() {
    _closed = true;
    _pending = const None();
    _signalled = false;
    _waiter?.interrupt(const ConcurrentFlowClosed());
    _waiter = null;
  }
}

final class _GenerationValue<A> {
  const _GenerationValue(this.value, this.generation);

  final A value;
  final int generation;
}

Cause<E> _appendParallelCleanup<E>(
  Cause<E> original,
  Iterable<Exit<void, E>> exits,
) {
  final cleanupFailures = exits
      .whereType<Failed<void, E>>()
      .map((exit) => exit.cause.defectsOnly)
      .whereType<Cause<Never>>()
      .map((cause) => cause.mapExpected<E>(_widenNever));
  final parallelCleanup = CauseGroup.parallel(cleanupFailures);
  return CauseGroup.sequential([original, ?parallelCleanup])!;
}

final class _ConcurrencyGate {
  _ConcurrencyGate(this.limit);

  final int limit;
  // Only the sequential outer pump acquires permits.
  CoordinationWaiter<void>? _waiter;
  var _active = 0;
  var _closed = false;

  Effect<void, Never> acquire() => Effect.defer((_) {
    final waiter = CoordinationWaiter<void>();
    return waiter.awaitValue(
      onStart: () {
        if (_closed) {
          waiter.interrupt(const ConcurrentFlowClosed());
        } else if (_active < limit) {
          _active += 1;
          waiter.succeed(null);
        } else {
          _waiter = waiter;
        }
      },
      onCancel: () {
        if (identical(_waiter, waiter)) _waiter = null;
      },
    );
  });

  void release() {
    if (_active == 0) return;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null) {
      waiter.succeed(null);
      return;
    }
    _active -= 1;
  }

  void close() {
    _closed = true;
    _waiter?.interrupt(const ConcurrentFlowClosed());
    _waiter = null;
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

/// Why switchMap interrupted an inner Flow before opening its replacement.
final class FlowInnerReplaced {
  /// Creates the stable inner-replacement interruption reason.
  const FlowInnerReplaced();

  @override
  String toString() => 'Flow inner replaced';
}

/// Why a concurrent Flow coordinator stopped accepting work.
final class ConcurrentFlowClosed {
  /// Creates the stable coordinator-closed interruption reason.
  const ConcurrentFlowClosed();

  @override
  String toString() => 'Concurrent Flow closed';
}

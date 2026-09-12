import 'dart:async';
import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/cause.dart' show CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/effect/exit.dart' show ExitRuntimeOperations;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';

/// Opens cursors against one lazily connected shared Flow state.
abstract final class SharedFlowSource {
  /// Creates one connection state retained across calls to the returned opener.
  static OpenFlowCursor<A, E> create<A, E>(
    OpenFlowCursor<A, E> upstream, {
    required int capacity,
    required int replay,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => _SharedFlowState<A, E>(
    upstream,
    capacity: capacity,
    replay: replay,
    overflow: overflow,
    onOverflow: onOverflow,
  ).open;
}

final class _SharedFlowState<A, E> {
  _SharedFlowState(
    this._upstream, {
    required this.capacity,
    required this.replay,
    required this.overflow,
    required this._onOverflow,
  });

  final OpenFlowCursor<A, E> _upstream;

  /// Maximum live values retained for each subscriber.
  final int capacity;

  /// Maximum past values copied to a subscriber when it attaches.
  final int replay;

  /// Per-subscriber behavior when [capacity] live values are pending.
  final FlowOverflowPolicy overflow;

  final E Function(FlowBufferOverflow overflow)? _onOverflow;
  _SharedConnection<A, E>? _connection;
  Future<Cause<Never>?>? _cleanup;
  var _nextConnectionId = 0;

  /// Attaches one cursor to the retained connection or a fresh connection.
  Effect<FlowSourceCursor<A, E>, E> open() => EffectAccess.create((execution) async {
    while (true) {
      final cleanup = _cleanup;
      if (cleanup == null) break;
      final waited = await EffectAccess.evaluate(
        Effect.tryFuture<Cause<Never>?, Never>(
          (_) => cleanup,
          onError: (error, stackTrace, _) => Error.throwWithStackTrace(error, stackTrace),
        ),
        execution,
      );
      if (waited case Failed<Cause<Never>?, Never>(:final cause)) {
        return Failed(cause.mapExpected<E>(_widenNever));
      }
    }

    final subscriber = _SharedSubscriber<A, E>(
      FlowMailbox(
        capacity,
        overflow,
        _onOverflow == null ? null : (event, _) => _onOverflow(event),
      ),
    );
    var connection = _connection;
    var shouldStart = false;
    if (connection == null) {
      connection = _SharedConnection(
        _nextConnectionId++,
        Runtime(context: execution.context, clock: execution.clock),
        replay,
      );
      _connection = connection;
      shouldStart = true;
    }

    final retained = connection.attach(subscriber);
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      _detach(connection, subscriber),
      execution.context,
      execution.clock,
    );
    if (!registered) {
      subscriber.mailbox.close();
      final cleanup = await _remove(connection, subscriber);
      return Failed<FlowSourceCursor<A, E>, E>(
        const Interrupted(ScopeClosed()),
      ).appendCleanup(cleanup);
    }

    if (shouldStart) connection.start(_upstream);
    return Succeeded(_SharedCursor(subscriber.mailbox, retained));
  });

  Effect<void, Never> _detach(
    _SharedConnection<A, E> connection,
    _SharedSubscriber<A, E> subscriber,
  ) => EffectAccess.create((_) async {
    subscriber.mailbox.close();
    final cleanup = await _remove(connection, subscriber);
    return cleanup == null ? const Succeeded(null) : Failed(cleanup);
  });

  Future<Cause<Never>?> _remove(
    _SharedConnection<A, E> connection,
    _SharedSubscriber<A, E> subscriber,
  ) async {
    connection.detach(subscriber);
    if (!identical(_connection, connection) || connection.hasSubscribers) {
      return null;
    }

    _connection = null;
    late final Future<Cause<Never>?> cleanup;
    cleanup = connection.close().whenComplete(() {
      if (identical(_cleanup, cleanup)) _cleanup = null;
    });
    _cleanup = cleanup;
    return cleanup;
  }
}

final class _SharedConnection<A, E> {
  _SharedConnection(
    this.id,
    this._runtime,
    this._replayCapacity,
  );

  final int id;
  final Runtime _runtime;
  final int _replayCapacity;
  final ListQueue<A> _replay = ListQueue();
  final Set<_SharedSubscriber<A, E>> _subscribers = {};
  Fiber<void, E>? _pump;
  Exit<void, E>? _terminal;
  var _closing = false;

  bool get hasSubscribers => _subscribers.isNotEmpty;

  List<A> attach(_SharedSubscriber<A, E> subscriber) {
    final retained = List<A>.of(_replay);
    _subscribers.add(subscriber);
    switch (_terminal) {
      case Succeeded<void, E>():
        subscriber.mailbox.complete();
      case Failed<void, E>(:final cause):
        subscriber.mailbox.fail(cause);
      case null:
        break;
    }
    return retained;
  }

  void detach(_SharedSubscriber<A, E> subscriber) {
    subscriber.active = false;
    _subscribers.remove(subscriber);
  }

  void start(OpenFlowCursor<A, E> upstream) {
    final pump = _runtime.fork(pumpFlow(upstream, _publish));
    _pump = pump;
    unawaited(pump.exit.then(_finished));
  }

  Effect<void, E> _publish(A value) => EffectAccess.create((execution) async {
    if (_closing) return const Succeeded(null);
    if (_replayCapacity > 0) {
      if (_replay.length == _replayCapacity) _replay.removeFirst();
      _replay.addLast(value);
    }

    final subscribers = List<_SharedSubscriber<A, E>>.of(_subscribers);
    for (final subscriber in subscribers) {
      if (!subscriber.active) continue;
      final offered = await EffectAccess.evaluate(subscriber.mailbox.offer(value), execution);
      if (offered case Failed<void, E>(:final cause)) {
        if (execution.cancellation.isCancelled) return Failed(cause);
        subscriber.active = false;
        subscriber.mailbox.fail(cause);
      }
    }
    return const Succeeded(null);
  });

  void _finished(Exit<void, E> exit) {
    if (_closing) return;
    _terminal = exit;
    for (final subscriber in _subscribers) {
      subscriber.active = false;
      switch (exit) {
        case Succeeded<void, E>():
          subscriber.mailbox.complete();
        case Failed<void, E>(:final cause):
          subscriber.mailbox.fail(cause);
      }
    }
  }

  Future<Cause<Never>?> close() async {
    _closing = true;
    _replay.clear();
    final pump = _pump;
    Cause<Never>? cleanup;
    if (pump != null) {
      final exit = _terminal == null
          ? await pump.interrupt(SharedFlowDisconnected(id))
          : await pump.join();
      if (_terminal == null) {
        if (exit case Failed<void, E>(:final cause)) {
          cleanup = cause.defectsOnly;
        }
      }
    }
    await _runtime.close();
    return cleanup;
  }
}

final class _SharedSubscriber<A, E> {
  _SharedSubscriber(this.mailbox);

  final FlowMailbox<A, E> mailbox;
  bool active = true;
}

final class _SharedCursor<A, E> implements FlowSourceCursor<A, E> {
  _SharedCursor(this._mailbox, Iterable<A> retained) : _retained = ListQueue<A>.of(retained);

  final FlowMailbox<A, E> _mailbox;
  final ListQueue<A> _retained;

  @override
  Effect<Option<A>, E> next() {
    if (_retained.isNotEmpty) return Effect.succeed(Some(_retained.removeFirst()));
    return _mailbox.take();
  }
}

E _widenNever<E>(Never error) => error;

/// Why a shared Flow stopped an upstream connection after final detachment.
final class SharedFlowDisconnected {
  /// Identifies the released connection for diagnostics.
  const SharedFlowDisconnected(this.connectionId);

  /// Monotonically increasing connection identity within one shared Flow.
  final int connectionId;

  @override
  String toString() => 'Shared Flow connection $connectionId disconnected';
}

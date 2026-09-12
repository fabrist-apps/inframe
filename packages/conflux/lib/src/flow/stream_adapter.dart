import 'dart:async';
import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';

/// Opens bounded Stream-backed Flow cursors.
abstract final class StreamFlowSource {
  /// Invokes [source], subscribes, and registers asynchronous cancellation.
  static Effect<FlowSourceCursor<A, E>, E> open<A, E>(
    Stream<A> Function() source, {
    required E Function(Object error, StackTrace stackTrace) onError,
    required int capacity,
    required FlowOverflowPolicy overflow,
    E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => Effect.build<FlowSourceCursor<A, E>, E>(($) async {
    return $.acquireRelease<_StreamCursor<A, E>>(
      Effect.sync<_StreamCursor<A, E>>(
        (_) => _StreamCursor<A, E>(
          capacity,
          overflow,
          onError,
          onOverflow,
        )..start(source),
      ).mapError<E>((value, _) => _widenNever(value! as Never)),
      release: (cursor, _) => cursor.close(),
    );
  });
}

E _widenNever<E>(Never error) => error;

final class _StreamCursor<A, E> implements FlowSourceCursor<A, E> {
  _StreamCursor(
    this._capacity,
    this._overflow,
    this._onError,
    this._onOverflow,
  );

  final int _capacity;
  final FlowOverflowPolicy _overflow;
  final E Function(Object error, StackTrace stackTrace) _onError;
  final E Function(FlowBufferOverflow overflow)? _onOverflow;
  final ListQueue<A> _values = ListQueue();
  StreamSubscription<A>? _subscription;
  _PendingStreamPull<A, E>? _pendingPull;
  Future<void>? _stopping;
  Object? _stopError;
  StackTrace? _stopStackTrace;
  Cause<E>? _terminalFailure;
  var _paused = false;
  var _done = false;
  var _closed = false;
  var _stopRequested = false;

  void start(Stream<A> Function() source) {
    // The scoped release below owns this subscription through every exit.
    // ignore: cancel_subscriptions
    final subscription = source().listen(
      _receive,
      onError: _failFromStream,
      onDone: _complete,
      cancelOnError: false,
    );
    _subscription = subscription;
    if (_paused) subscription.pause();
    if (_stopRequested) _beginStopping();
  }

  @override
  Effect<Option<A>, E> next() => EffectAccess.create((execution) async {
    if (_values.isNotEmpty) {
      final value = _values.removeFirst();
      _resumeIfCapacityAvailable();
      return Succeeded(Some(value));
    }
    final failure = _terminalFailure;
    if (failure != null) return Failed(failure);
    if (_done || _closed) return const Succeeded(None());

    final pending = _PendingStreamPull<A, E>();
    _pendingPull = pending;
    if (execution.cancellation.isCancelled) {
      _pendingPull = null;
      return Failed(Interrupted(execution.cancellation.reason));
    }
    pending.stopCancellation = execution.cancellation.listen((reason) {
      if (!identical(_pendingPull, pending)) return;
      _pendingPull = null;
      pending.complete(Failed(Interrupted(reason)));
    });
    return pending.result;
  });

  Effect<void, Never> close() => EffectAccess.create((_) async {
    _closed = true;
    _values.clear();
    _terminalFailure = null;
    final pending = _pendingPull;
    _pendingPull = null;
    pending?.complete(
      const Failed(Interrupted(StreamFlowSourceClosed())),
    );
    await _stopSource();
    final error = _stopError;
    return error == null
        ? const Succeeded(null)
        : Failed(Defect(error, _stopStackTrace ?? StackTrace.empty));
  });

  void _receive(A value) {
    if (_closed || _done || _terminalFailure != null) return;
    final pending = _pendingPull;
    if (pending != null) {
      _pendingPull = null;
      pending.complete(Succeeded(Some(value)));
      return;
    }

    if (_values.length < _capacity) {
      _values.addLast(value);
      if (_overflow == FlowOverflowPolicy.backpressure && _values.length == _capacity) {
        _pause();
      }
      return;
    }

    switch (_overflow) {
      case FlowOverflowPolicy.backpressure:
        _pause();
      case FlowOverflowPolicy.dropNewest:
        return;
      case FlowOverflowPolicy.dropOldest:
        _values
          ..removeFirst()
          ..addLast(value);
      case FlowOverflowPolicy.fail:
        _failFromOverflow();
    }
  }

  void _failFromStream(Object error, StackTrace stackTrace) {
    if (_closed || _done || _terminalFailure != null) return;
    try {
      _terminalFailure = Expected(_onError(error, stackTrace));
    } on Object catch (mapperError, mapperStackTrace) {
      _terminalFailure = Defect(mapperError, mapperStackTrace);
    }
    unawaited(_stopSource());
    _deliverTerminalIfReady();
  }

  void _failFromOverflow() {
    try {
      _terminalFailure = Expected(
        _onOverflow!(FlowBufferOverflow(_capacity)),
      );
    } on Object catch (error, stackTrace) {
      _terminalFailure = Defect(error, stackTrace);
    }
    unawaited(_stopSource());
    _deliverTerminalIfReady();
  }

  void _complete() {
    if (_closed || _done || _terminalFailure != null) return;
    _done = true;
    _deliverTerminalIfReady();
  }

  void _deliverTerminalIfReady() {
    if (_values.isNotEmpty) return;
    final pending = _pendingPull;
    if (pending == null) return;
    _pendingPull = null;
    final failure = _terminalFailure;
    pending.complete(
      failure == null ? const Succeeded(None()) : Failed(failure),
    );
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _subscription?.pause();
  }

  void _resumeIfCapacityAvailable() {
    if (!_paused || _values.length >= _capacity) return;
    _paused = false;
    _subscription?.resume();
  }

  Future<void> _stopSource() {
    _stopRequested = true;
    _beginStopping();
    return _stopping ?? Future.value();
  }

  void _beginStopping() {
    if (_stopping != null) return;
    final subscription = _subscription;
    if (subscription == null) return;
    _stopping = Future.sync(subscription.cancel).then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _stopError = error;
        _stopStackTrace = stackTrace;
      },
    );
  }
}

final class _PendingStreamPull<A, E> {
  final _completer = Completer<Exit<Option<A>, E>>();
  void Function()? stopCancellation;

  Future<Exit<Option<A>, E>> get result => _completer.future;

  void complete(Exit<Option<A>, E> exit) {
    if (_completer.isCompleted) return;
    stopCancellation?.call();
    stopCancellation = null;
    _completer.complete(exit);
  }
}

/// Why adapter cleanup interrupted a pending Stream-backed pull.
final class StreamFlowSourceClosed {
  /// Creates the stable adapter-close reason.
  const StreamFlowSourceClosed();

  @override
  String toString() => 'Stream Flow source closed';
}

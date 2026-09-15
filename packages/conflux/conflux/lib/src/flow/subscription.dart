import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/flow/flow.dart';
import 'package:context/context.dart';

/// A running Flow consumer with an eventual cleanup-complete outcome.
final class FlowSubscription<E> {
  FlowSubscription._(this._fiber, this.completion);

  final Fiber<void, E> _fiber;
  Future<Exit<void, E>>? _cancelling;

  /// The terminal consumer outcome after all Flow cleanup finishes.
  final Future<Exit<void, E>> completion;

  /// Interrupts consumption and returns after cleanup and completion.
  ///
  /// Repeated calls share the first cancellation operation and its final Exit.
  Future<Exit<void, E>> cancel([Object? reason]) {
    final active = _cancelling;
    if (active != null) return active;
    final cancelling = _cancel(reason);
    _cancelling = cancelling;
    return cancelling;
  }

  Future<Exit<void, E>> _cancel(Object? reason) async {
    await _fiber.interrupt(reason ?? const FlowSubscriptionCancelled());
    return completion;
  }

  static FlowSubscription<E> _start<A, E>(
    Flow<A, E> flow,
    Effect<void, E> Function(A value, Context context) consume,
    Context? context,
  ) {
    final runtime = Runtime(context: context);
    final fiber = runtime.fork(flow.runForEach(consume));
    final completion = fiber.join().then((exit) async {
      await runtime.close();
      return exit;
    });
    return FlowSubscription._(fiber, completion);
  }
}

/// A Dart Stream error that retains a Flow's complete terminal cause.
final class FlowException<E> implements Exception {
  /// Creates a wrapper around [cause].
  const FlowException(this.cause);

  /// The expected errors, defects, interruption, and cleanup diagnostics.
  final Cause<E> cause;

  @override
  String toString() => 'FlowException: $cause';
}

/// Running consumers and Dart Stream interop for a Flow.
extension FlowInterop<A, E> on Flow<A, E> {
  /// Starts consuming values through one effectful callback at a time.
  ///
  /// The returned handle owns a temporary Runtime using [context]. Its
  /// [FlowSubscription.completion] resolves only after Flow and Runtime cleanup.
  FlowSubscription<E> subscribe(
    Effect<void, E> Function(A value, Context context) consume, {
    Context? context,
  }) => FlowSubscription._start(this, consume, context);

  /// Creates a single-subscription Dart Stream for each call to [Stream.listen].
  ///
  /// Terminal failure is emitted as [FlowException]. Pausing the Stream stops
  /// further delivery and bounds read-ahead to one value. Cancelling the Dart
  /// subscription awaits Flow cleanup.
  Stream<A> toStream({Context? context}) => _FlowStream(this, context);
}

final class _FlowStream<A, E> extends Stream<A> {
  const _FlowStream(this._flow, this._context);

  final Flow<A, E> _flow;
  final Context? _context;

  @override
  StreamSubscription<A> listen(
    void Function(A event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    late final _StreamPump<A, E> pump;
    final controller = StreamController<A>(
      sync: true,
      onListen: () => pump.start(),
      onPause: () => pump.pause(),
      onResume: () => pump.resume(),
      onCancel: () => pump.cancel(),
    );
    pump = _StreamPump(_flow, _context, controller);
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final class _StreamPump<A, E> {
  _StreamPump(this._flow, this._context, this._controller);

  final Flow<A, E> _flow;
  final Context? _context;
  final StreamController<A> _controller;
  FlowSubscription<E>? _subscription;
  Completer<void>? _resumed;
  var _paused = false;
  var _cancelled = false;

  void start() {
    final subscription = _flow.subscribe(
      (value, _) => _deliver(value),
      context: _context,
    );
    _subscription = subscription;
    unawaited(subscription.completion.then(_complete));
  }

  void pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumed = Completer<void>();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    final resumed = _resumed;
    _resumed = null;
    if (resumed != null && !resumed.isCompleted) resumed.complete();
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    resume();
    await _subscription?.cancel(const FlowStreamCancelled());
  }

  Effect<void, E> _deliver(A value) => EffectAccess.create((execution) async {
    if (_cancelled) {
      return const Failed(Interrupted(FlowStreamCancelled()));
    }
    while (_paused && !_cancelled) {
      final resumed = _resumed;
      if (resumed == null) break;
      final wait = await EffectAccess.evaluate(
        Effect.tryFuture<void, E>(
          (_) => resumed.future,
          onError: (error, stackTrace, _) => Error.throwWithStackTrace(error, stackTrace),
        ),
        execution,
      );
      if (wait case Failed<void, E>()) return wait;
    }
    if (_cancelled || execution.cancellation.isCancelled) {
      return Failed(Interrupted(execution.cancellation.reason));
    }
    _controller.add(value);
    return const Succeeded(null);
  });

  Future<void> _complete(Exit<void, E> exit) async {
    if (_cancelled) return;
    switch (exit) {
      case Succeeded<void, E>():
        await _controller.close();
      case Failed<void, E>(:final cause):
        _controller.addError(FlowException(cause));
        await _controller.close();
    }
  }
}

/// Why a Flow subscription was cancelled without a caller-supplied reason.
final class FlowSubscriptionCancelled {
  /// Creates the default subscription cancellation reason.
  const FlowSubscriptionCancelled();

  @override
  String toString() => 'Flow subscription cancelled';
}

/// Why a Dart Stream subscription interrupted its Flow consumer.
final class FlowStreamCancelled {
  /// Creates the Stream adapter cancellation reason.
  const FlowStreamCancelled();

  @override
  String toString() => 'Flow Stream cancelled';
}

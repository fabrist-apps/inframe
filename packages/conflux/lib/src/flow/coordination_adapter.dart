import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/pubsub.dart';
import 'package:conflux/queue.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/flow/protocol.dart';

/// Opens Flow cursors over shared Conflux coordination primitives.
abstract final class CoordinationFlowSource {
  /// Opens a competing consumer without taking ownership of [queue].
  static Effect<FlowSourceCursor<A, Never>, Never> openQueue<A>(
    Queue<A> queue,
  ) => Effect.succeed(_QueueFlowCursor(queue));

  /// Acquires one subscription owned by the current Flow consumption scope.
  ///
  /// Closing the scope unsubscribes it. The externally supplied [pubsub] remains
  /// owned by its original scope.
  static Effect<FlowSourceCursor<A, Never>, Never> openPubSub<A>(
    PubSub<A> pubsub,
  ) => EffectAccess.create((execution) async {
    final acquired = await EffectAccess.evaluate(pubsub.subscribe(), execution);
    return switch (acquired) {
      Succeeded<PubSubSubscription<A>, Never>(:final value) => Succeeded(
        _PubSubFlowCursor(value),
      ),
      Failed<PubSubSubscription<A>, Never>(
        cause: Interrupted<Never>(reason: PubSubShutdown()),
      ) =>
        const Succeeded(_CompletedCoordinationCursor()),
      Failed<PubSubSubscription<A>, Never>(:final cause) => Failed(cause),
    };
  });
}

final class _QueueFlowCursor<A> implements FlowSourceCursor<A, Never> {
  const _QueueFlowCursor(this._queue);

  final Queue<A> _queue;

  @override
  Effect<Option<A>, Never> next() => _take(
    _queue.take(),
    isSourceShutdown: (reason) => reason is QueueShutdown,
  );
}

final class _PubSubFlowCursor<A> implements FlowSourceCursor<A, Never> {
  const _PubSubFlowCursor(this._subscription);

  final PubSubSubscription<A> _subscription;

  @override
  Effect<Option<A>, Never> next() => _take(
    _subscription.take(),
    isSourceShutdown: (reason) => reason is PubSubShutdown || reason is PubSubSubscriptionClosed,
  );
}

final class _CompletedCoordinationCursor<A> implements FlowSourceCursor<A, Never> {
  const _CompletedCoordinationCursor();

  @override
  Effect<Option<A>, Never> next() => Effect.succeed(const None());
}

Effect<Option<A>, Never> _take<A>(
  Effect<A, Never> take, {
  required bool Function(Object? reason) isSourceShutdown,
}) => EffectAccess.create((execution) async {
  final taken = await EffectAccess.evaluate(take, execution);
  return switch (taken) {
    Succeeded<A, Never>(:final value) => Succeeded(Some(value)),
    Failed<A, Never>(
      cause: Interrupted<Never>(:final reason),
    )
        when isSourceShutdown(reason) =>
      const Succeeded(None()),
    Failed<A, Never>(:final cause) => Failed(cause),
  };
});

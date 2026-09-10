import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/src/coordination/waiter.dart';

/// Identifies interruption caused by a [PubSub] shutting down.
final class PubSubShutdown {
  /// Creates the stable PubSub shutdown reason.
  const PubSubShutdown();

  @override
  String toString() => 'PubSub shut down';
}

/// Identifies interruption caused by a subscription ending independently.
final class PubSubSubscriptionClosed {
  /// Creates the stable subscription-closed reason.
  const PubSubSubscriptionClosed();

  @override
  String toString() => 'PubSub subscription closed';
}

/// A scoped, in-memory broadcaster with bounded lossless backpressure.
///
/// Publications target the subscriptions active when the publish Effect starts.
/// A publication commits to every still-active target in one synchronous state
/// transition, and the slowest target controls capacity. State is confined to
/// the isolate that acquires the PubSub.
final class PubSub<A> {
  PubSub._(this._capacity) {
    if (_capacity <= 0) {
      throw ArgumentError.value(_capacity, 'capacity', 'Must be positive.');
    }
  }

  /// Lazily acquires a PubSub and registers shutdown with the current scope.
  ///
  /// ```dart
  /// final program = Effect.build<int, Never>(($) async {
  ///   final pubsub = await $(PubSub.bounded<int>(1));
  ///   final subscription = await $(pubsub.subscribe());
  ///   await $(pubsub.publish(42));
  ///   return $(subscription.take());
  /// });
  /// final value = await program.runFuture();
  /// ```
  ///
  /// A non-positive [capacity] becomes an [ArgumentError] defect when the
  /// acquisition runs. Scope exit shuts the PubSub down immediately.
  static Effect<PubSub<A>, Never> bounded<A>(int capacity) {
    return Effect.build<PubSub<A>, Never>(($) async {
      return $.acquireRelease(
        Effect.sync(() => PubSub<A>._(capacity)),
        release: (pubsub) => pubsub.shutdown(),
      );
    });
  }

  final int _capacity;
  final LinkedHashSet<_PubSubSubscriptionState<A>> _subscriptions = LinkedHashSet();
  final ListQueue<_PendingPublication<A>> _publications = ListQueue();
  final ListQueue<CoordinationWaiter<void>> _shutdownWaiters = ListQueue();
  var _isShutdown = false;

  /// Whether shutdown bookkeeping and waiter notification have completed.
  bool get isShutdown => _isShutdown;

  /// Lazily publishes [item] to the subscriptions active when execution begins.
  ///
  /// With no subscribers, the item is discarded. Otherwise publication waits
  /// until every still-active target has capacity, then commits atomically.
  Effect<void, Never> publish(A item) => Effect.defer(() {
    if (_isShutdown) return _shutdownEffect();

    final targets = List<_PubSubSubscriptionState<A>>.unmodifiable(
      _subscriptions,
    );
    if (targets.isEmpty) return Effect.succeed(null);

    final publication = _PendingPublication(item, targets);
    _publications.addLast(publication);
    _drainPublications();
    return publication.waiter.awaitValue(
      onCancel: () {
        _publications.remove(publication);
        _drainPublications();
      },
    );
  });

  /// Lazily acquires a subscription owned by the current Effect scope.
  ///
  /// Scope exit unsubscribes automatically. A subscription receives only
  /// publications whose execution began while it was active.
  Effect<PubSubSubscription<A>, Never> subscribe() => Effect.defer(() {
    if (_isShutdown) return _shutdownEffect();

    return Effect.build<PubSubSubscription<A>, Never>(($) async {
      return $.acquireRelease(
        Effect.defer(() {
          if (_isShutdown) return _shutdownEffect();
          return Effect.succeed(_createSubscription());
        }),
        release: (subscription) => subscription.unsubscribe(),
      );
    });
  });

  /// Lazily shuts down immediately, discarding messages and waking waiters.
  ///
  /// Repeated shutdown is harmless. Blocked and subsequent operations are
  /// interrupted with [PubSubShutdown].
  Effect<void, Never> shutdown() => Effect.sync(_shutdown);

  /// Lazily waits until shutdown bookkeeping and waiter notification finish.
  Effect<void, Never> awaitShutdown() => Effect.defer(() {
    if (_isShutdown) return Effect.succeed(null);

    final waiter = CoordinationWaiter<void>();
    _shutdownWaiters.addLast(waiter);
    return waiter.awaitValue(
      onCancel: () => _shutdownWaiters.remove(waiter),
    );
  });

  PubSubSubscription<A> _createSubscription() {
    final state = _PubSubSubscriptionState(this);
    _subscriptions.add(state);
    return PubSubSubscription._(state);
  }

  void _unsubscribe(_PubSubSubscriptionState<A> subscription) {
    if (!subscription.isActive) return;
    _subscriptions.remove(subscription);
    subscription.close(const PubSubSubscriptionClosed());
    _drainPublications();
  }

  void _onCapacityAvailable() => _drainPublications();

  void _drainPublications() {
    while (!_isShutdown && _publications.isNotEmpty) {
      final publication = _publications.first;
      final activeTargets = publication.targets
          .where((target) => target.isActive)
          .toList(growable: false);
      if (activeTargets.any((target) => !target.hasCapacity)) return;

      _publications.removeFirst();
      for (final target in activeTargets) {
        target.enqueue(publication.item);
      }
      publication.waiter.succeed(null);
    }
  }

  void _shutdown() {
    if (_isShutdown) return;
    _isShutdown = true;
    while (_publications.isNotEmpty) {
      _publications.removeFirst().waiter.interrupt(const PubSubShutdown());
    }
    final subscriptions = List<_PubSubSubscriptionState<A>>.of(
      _subscriptions,
    );
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      subscription.close(const PubSubShutdown());
    }
    while (_shutdownWaiters.isNotEmpty) {
      _shutdownWaiters.removeFirst().succeed(null);
    }
  }

  static Effect<T, Never> _shutdownEffect<T>() {
    return Effect.failCause(const Interrupted(PubSubShutdown()));
  }
}

/// A scoped subscription receiving publications in their common order.
final class PubSubSubscription<A> {
  const PubSubSubscription._(this._state);

  final _PubSubSubscriptionState<A> _state;

  /// Lazily waits for and removes the next publication.
  ///
  /// Cancellation removes a pending read without consuming a later value.
  Effect<A, Never> take() => _state.take();

  /// Lazily removes at most [limit] currently available publications.
  ///
  /// This never waits for more values and returns an immutable FIFO list. Zero
  /// returns an empty list. A negative limit becomes an [ArgumentError] defect
  /// when the Effect runs.
  Effect<List<A>, Never> takeUpTo(int limit) => _state.takeUpTo(limit);

  /// Lazily ends this subscription and releases its retained capacity.
  ///
  /// Repeated unsubscription is harmless and does not affect other subscribers.
  Effect<void, Never> unsubscribe() => Effect.sync(
    () => _state.owner._unsubscribe(_state),
  );
}

final class _PubSubSubscriptionState<A> {
  _PubSubSubscriptionState(this.owner);

  final PubSub<A> owner;
  final ListQueue<A> _items = ListQueue();
  final ListQueue<CoordinationWaiter<A>> _takers = ListQueue();
  Object? _closedReason;

  bool get isActive => _closedReason == null;

  bool get hasCapacity => _items.length < owner._capacity;

  Effect<A, Never> take() => Effect.defer(() {
    final closedReason = _closedReason;
    if (closedReason != null) return _interrupted(closedReason);

    if (_items.isNotEmpty) {
      final item = _items.removeFirst();
      owner._onCapacityAvailable();
      return Effect.succeed(item);
    }

    final taker = CoordinationWaiter<A>();
    _takers.addLast(taker);
    return taker.awaitValue(
      onCancel: () => _takers.remove(taker),
    );
  });

  Effect<List<A>, Never> takeUpTo(int limit) => Effect.defer(() {
    final closedReason = _closedReason;
    if (closedReason != null) return _interrupted(closedReason);
    if (limit < 0) {
      return Effect.sync(
        () => throw ArgumentError.value(
          limit,
          'limit',
          'Must not be negative.',
        ),
      );
    }

    final count = limit < _items.length ? limit : _items.length;
    final items = <A>[
      for (var index = 0; index < count; index += 1) _items.removeFirst(),
    ];
    owner._onCapacityAvailable();
    return Effect.succeed(List.unmodifiable(items));
  });

  void enqueue(A item) {
    if (!isActive) return;
    if (_takers.isNotEmpty) {
      _takers.removeFirst().succeed(item);
      return;
    }
    _items.addLast(item);
  }

  void close(Object reason) {
    if (!isActive) return;
    _closedReason = reason;
    _items.clear();
    while (_takers.isNotEmpty) {
      _takers.removeFirst().interrupt(reason);
    }
  }

  static Effect<T, Never> _interrupted<T>(Object reason) {
    return Effect.failCause(Interrupted(reason));
  }
}

final class _PendingPublication<A> {
  _PendingPublication(this.item, this.targets);

  final A item;
  final List<_PubSubSubscriptionState<A>> targets;
  final CoordinationWaiter<void> waiter = CoordinationWaiter();
}

import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/src/coordination/waiter.dart';
import 'package:conflux/src/validation.dart';

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
    checkPositive(_capacity, 'capacity');
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
        Effect.sync((_) => PubSub<A>._(capacity)),
        release: (pubsub, _) => pubsub.shutdown(),
      );
    });
  }

  final int _capacity;
  final LinkedHashSet<PubSubSubscription<A>> _subscriptions = LinkedHashSet();
  final ListQueue<_PendingPublication<A>> _publications = ListQueue();
  final ListQueue<CoordinationWaiter<void>> _shutdownWaiters = ListQueue();
  var _isShutdown = false;

  /// Whether shutdown bookkeeping and waiter notification have completed.
  bool get isShutdown => _isShutdown;

  /// Lazily publishes [item] to the subscriptions active when execution begins.
  ///
  /// With no subscribers, the item is discarded. Otherwise publication waits
  /// until every still-active target has capacity, then commits atomically.
  Effect<void, Never> publish(A item) => Effect.defer((_) {
    final waiter = CoordinationWaiter<void>();
    late final _PendingPublication<A> publication;
    return waiter.awaitValue(
      onStart: () {
        if (_isShutdown) {
          waiter.interrupt(const PubSubShutdown());
          return;
        }
        final targets = List<PubSubSubscription<A>>.unmodifiable(
          _subscriptions,
        );
        if (targets.isEmpty) {
          waiter.succeed(null);
          return;
        }

        publication = _PendingPublication(item, targets, waiter);
        _publications.addLast(publication);
        _drainPublications();
      },
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
  Effect<PubSubSubscription<A>, Never> subscribe() => Effect.defer((_) {
    if (_isShutdown) return _shutdownEffect();

    return Effect.build<PubSubSubscription<A>, Never>(($) async {
      final acquired = await $.acquireRelease(
        Effect.sync<PubSubSubscription<A>?>(
          (_) => _isShutdown ? null : _createSubscription(),
        ),
        release: (subscription, _) => subscription?.unsubscribe() ?? Effect.succeed(null),
      );
      return $(acquired == null ? _shutdownEffect() : Effect.succeed(acquired));
    });
  });

  /// Lazily shuts down immediately, discarding messages and waking waiters.
  ///
  /// Repeated shutdown is harmless. Blocked and subsequent operations are
  /// interrupted with [PubSubShutdown].
  Effect<void, Never> shutdown() => Effect.sync((_) => _shutdown());

  /// Lazily waits until shutdown bookkeeping and waiter notification finish.
  Effect<void, Never> awaitShutdown() => Effect.defer((_) {
    final waiter = CoordinationWaiter<void>();
    return waiter.awaitValue(
      onStart: () {
        if (_isShutdown) {
          waiter.succeed(null);
          return;
        }
        _shutdownWaiters.addLast(waiter);
      },
      onCancel: () => _shutdownWaiters.remove(waiter),
    );
  });

  PubSubSubscription<A> _createSubscription() {
    final subscription = PubSubSubscription._(this);
    _subscriptions.add(subscription);
    return subscription;
  }

  void _unsubscribe(PubSubSubscription<A> subscription) {
    if (!subscription._isActive) return;
    _subscriptions.remove(subscription);
    subscription._close(const PubSubSubscriptionClosed());
    _drainPublications();
  }

  void _drainPublications() {
    while (!_isShutdown && _publications.isNotEmpty) {
      final publication = _publications.first;
      final activeTargets = publication.targets
          .where((target) => target._isActive)
          .toList(growable: false);
      if (activeTargets.any((target) => !target._hasCapacity)) return;

      _publications.removeFirst();
      for (final target in activeTargets) {
        target._enqueue(publication.item);
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
    final subscriptions = List<PubSubSubscription<A>>.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      subscription._close(const PubSubShutdown());
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
  PubSubSubscription._(this._owner);

  final PubSub<A> _owner;
  final ListQueue<A> _items = ListQueue();
  final ListQueue<CoordinationWaiter<A>> _takers = ListQueue();
  Object? _closedReason;

  bool get _isActive => _closedReason == null;

  bool get _hasCapacity => _items.length < _owner._capacity;

  /// Lazily waits for and removes the next publication.
  ///
  /// Cancellation removes a pending read without consuming a later value.
  Effect<A, Never> take() => Effect.defer((_) {
    final taker = CoordinationWaiter<A>();
    return taker.awaitValue(
      onStart: () {
        final closedReason = _closedReason;
        if (closedReason != null) {
          taker.interrupt(closedReason);
          return;
        }
        if (_items.isNotEmpty) {
          taker.succeed(_items.removeFirst());
          _owner._drainPublications();
          return;
        }
        _takers.addLast(taker);
      },
      onCancel: () => _takers.remove(taker),
    );
  });

  /// Lazily removes at most [limit] currently available publications.
  ///
  /// This never waits for more values and returns an immutable FIFO list. Zero
  /// returns an empty list. A negative limit becomes an [ArgumentError] defect
  /// when the Effect runs.
  Effect<List<A>, Never> takeUpTo(int limit) => Effect.defer((_) {
    final closedReason = _closedReason;
    if (closedReason != null) return _interrupted(closedReason);
    checkNonNegative(limit, 'limit');

    final count = limit < _items.length ? limit : _items.length;
    final items = <A>[
      for (var index = 0; index < count; index += 1) _items.removeFirst(),
    ];
    _owner._drainPublications();
    return Effect.succeed(List.unmodifiable(items));
  });

  /// Lazily ends this subscription and releases its retained capacity.
  ///
  /// Repeated unsubscription is harmless and does not affect other subscribers.
  Effect<void, Never> unsubscribe() => Effect.sync((_) => _owner._unsubscribe(this));

  void _enqueue(A item) {
    if (!_isActive) return;
    if (_takers.isNotEmpty) {
      _takers.removeFirst().succeed(item);
      return;
    }
    _items.addLast(item);
  }

  void _close(Object reason) {
    if (!_isActive) return;
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
  _PendingPublication(this.item, this.targets, this.waiter);

  final A item;
  final List<PubSubSubscription<A>> targets;
  final CoordinationWaiter<void> waiter;
}

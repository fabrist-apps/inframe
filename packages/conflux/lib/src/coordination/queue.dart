import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/coordination/waiter.dart';

/// Identifies interruption caused by a [Queue] shutting down.
final class QueueShutdown {
  /// Creates the stable Queue shutdown reason.
  const QueueShutdown();

  @override
  String toString() => 'Queue shut down';
}

/// A scoped, in-memory queue with bounded lossless backpressure.
///
/// Use [bounded] inside an Effect scope. Each accepted item is delivered to one
/// taker, and both items and blocked waiters retain FIFO order. The Queue is
/// confined to the isolate that acquires it.
final class Queue<A> {
  Queue._(this.capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
    }
  }

  /// Lazily acquires a Queue and registers shutdown with the current scope.
  ///
  /// ```dart
  /// final program = Effect.build<int, Never>(($) async {
  ///   final queue = await $(Queue.bounded<int>(1));
  ///   await $(queue.offer(42));
  ///   return $(queue.take());
  /// });
  /// final value = await program.runFuture();
  /// ```
  ///
  /// A non-positive [capacity] becomes an [ArgumentError] defect when the
  /// acquisition runs. Scope exit shuts the Queue down immediately.
  static Effect<Queue<A>, Never> bounded<A>(int capacity) {
    return Effect.build<Queue<A>, Never>(($) async {
      return $.acquireRelease(
        Effect.sync(() => Queue<A>._(capacity)),
        release: (queue) => queue.shutdown(),
      );
    });
  }

  /// The maximum number of buffered items.
  final int capacity;

  final ListQueue<A> _items = ListQueue();
  final ListQueue<_PendingOffer<A>> _offers = ListQueue();
  final ListQueue<CoordinationWaiter<A>> _takers = ListQueue();
  final ListQueue<CoordinationWaiter<void>> _shutdownWaiters = ListQueue();
  var _isShutdown = false;

  /// The number of buffered items, excluding waiting consumers and producers.
  int get size => _items.length;

  /// Whether shutdown bookkeeping and waiter notification have completed.
  bool get isShutdown => _isShutdown;

  /// Lazily offers [item], waiting when the configured capacity is full.
  ///
  /// Cancellation before the offer commits removes it. Cancellation after the
  /// item is accepted cannot retract its delivery.
  Effect<void, Never> offer(A item) => Effect.defer(() {
    if (_isShutdown) return _shutdownEffect();

    final offer = _PendingOffer(item);
    _offers.addLast(offer);
    _drain();
    return offer.waiter.awaitValue(
      onCancel: () {
        _offers.remove(offer);
        _drain();
      },
    );
  });

  /// Lazily waits for and removes the next item.
  ///
  /// Cancellation removes a pending take without consuming a later item.
  Effect<A, Never> take() => Effect.defer(() {
    if (_isShutdown) return _shutdownEffect();

    if (_items.isNotEmpty) {
      final item = _items.removeFirst();
      _drain();
      return Effect.succeed(item);
    }

    final taker = CoordinationWaiter<A>();
    _takers.addLast(taker);
    _drain();
    return taker.awaitValue(
      onCancel: () {
        _takers.remove(taker);
        _drain();
      },
    );
  });

  /// Lazily removes an available item without waiting for a producer.
  ///
  /// Returns [None] while an open Queue is empty. A present nullable item is
  /// returned as [Some] containing `null`.
  Effect<Option<A>, Never> poll() => Effect.defer(() {
    if (_isShutdown) return _shutdownEffect();
    if (_items.isEmpty) return Effect.succeed(const None());

    final item = _items.removeFirst();
    _drain();
    return Effect.succeed(Some(item));
  });

  /// Lazily observes an available item without removing it or waiting.
  ///
  /// Returns [None] while an open Queue is empty.
  Effect<Option<A>, Never> peek() => Effect.defer(() {
    if (_isShutdown) return _shutdownEffect();
    if (_items.isEmpty) return Effect.succeed(const None());
    return Effect.succeed(Some(_items.first));
  });

  /// Lazily removes at most [limit] currently available items in FIFO order.
  ///
  /// This operation never waits for more items and returns an immutable list.
  /// Zero returns an empty list. A negative limit becomes an [ArgumentError]
  /// defect when the Effect runs.
  Effect<List<A>, Never> takeUpTo(int limit) => Effect.defer(() {
    if (_isShutdown) return _shutdownEffect();
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
    _drain();
    return Effect.succeed(List.unmodifiable(items));
  });

  /// Lazily shuts down immediately, discarding items and waking waiters.
  ///
  /// Repeated shutdown is harmless. Blocked and subsequent data operations are
  /// interrupted with [QueueShutdown].
  Effect<void, Never> shutdown() => Effect.sync(_shutdown);

  /// Lazily waits until shutdown bookkeeping and waiter notification finish.
  ///
  /// This does not wait for previously accepted items to be processed.
  Effect<void, Never> awaitShutdown() => Effect.defer(() {
    if (_isShutdown) return Effect.succeed(null);

    final waiter = CoordinationWaiter<void>();
    _shutdownWaiters.addLast(waiter);
    return waiter.awaitValue(
      onCancel: () => _shutdownWaiters.remove(waiter),
    );
  });

  void _drain() {
    while (!_isShutdown) {
      if (_takers.isNotEmpty && _items.isNotEmpty) {
        _takers.removeFirst().succeed(_items.removeFirst());
        continue;
      }

      if (_offers.isEmpty) return;
      if (_takers.isNotEmpty) {
        final offer = _offers.removeFirst();
        _takers.removeFirst().succeed(offer.item);
        offer.waiter.succeed(null);
        continue;
      }
      if (_items.length >= capacity) return;

      final offer = _offers.removeFirst();
      _items.addLast(offer.item);
      offer.waiter.succeed(null);
    }
  }

  void _shutdown() {
    if (_isShutdown) return;
    _isShutdown = true;
    _items.clear();
    while (_offers.isNotEmpty) {
      _offers.removeFirst().waiter.interrupt(const QueueShutdown());
    }
    while (_takers.isNotEmpty) {
      _takers.removeFirst().interrupt(const QueueShutdown());
    }
    while (_shutdownWaiters.isNotEmpty) {
      _shutdownWaiters.removeFirst().succeed(null);
    }
  }

  static Effect<T, Never> _shutdownEffect<T>() {
    return Effect.failCause(const Interrupted(QueueShutdown()));
  }
}

final class _PendingOffer<A> {
  _PendingOffer(this.item);

  final A item;
  final CoordinationWaiter<void> waiter = CoordinationWaiter();
}

import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/coordination/waiter.dart';
import 'package:conflux/src/validation.dart';

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
    checkPositive(capacity, 'capacity');
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
        Effect.sync((_) => Queue<A>._(capacity)),
        release: (queue, _) => queue.shutdown(),
      );
    });
  }

  /// The maximum number of buffered items.
  final int capacity;

  final ListQueue<A> _items = ListQueue();
  final ListQueue<_PendingOffer<A>> _offers = ListQueue();
  final ListQueue<CoordinationWaiter<A>> _takers = ListQueue();
  var _isShutdown = false;

  /// The number of buffered items, excluding waiting consumers and producers.
  int get size => _items.length;

  /// Whether shutdown bookkeeping and waiter notification have completed.
  bool get isShutdown => _isShutdown;

  /// Lazily offers [item], waiting when the configured capacity is full.
  ///
  /// Cancellation before the offer commits removes it. Cancellation after the
  /// item is accepted cannot retract its delivery.
  Effect<void, Never> offer(A item) => Effect.defer((_) {
    final offer = _PendingOffer(item);
    return offer.waiter.awaitValue(
      onStart: () {
        if (_isShutdown) {
          offer.waiter.interrupt(const QueueShutdown());
          return;
        }
        _offers.addLast(offer);
        _drain();
      },
      onCancel: () {
        _offers.remove(offer);
        _drain();
      },
    );
  });

  /// Lazily waits for and removes the next item.
  ///
  /// Cancellation removes a pending take without consuming a later item.
  Effect<A, Never> take() => Effect.defer((_) {
    final taker = CoordinationWaiter<A>();
    return taker.awaitValue(
      onStart: () {
        if (_isShutdown) {
          taker.interrupt(const QueueShutdown());
          return;
        }
        if (_items.isNotEmpty) {
          taker.succeed(_items.removeFirst());
          _drain();
          return;
        }
        _takers.addLast(taker);
      },
      onCancel: () => _takers.remove(taker),
    );
  });

  /// Lazily removes an available item without waiting for a producer.
  ///
  /// Returns [None] while an open Queue is empty. A present nullable item is
  /// returned as [Some] containing `null`.
  Effect<Option<A>, Never> poll() => Effect.defer((_) {
    if (_isShutdown) return _shutdownEffect();
    if (_items.isEmpty) return Effect.succeed(const None());

    final item = _items.removeFirst();
    _drain();
    return Effect.succeed(Some(item));
  });

  /// Lazily observes an available item without removing it or waiting.
  ///
  /// Returns [None] while an open Queue is empty.
  Effect<Option<A>, Never> peek() => Effect.defer((_) {
    if (_isShutdown) return _shutdownEffect();
    if (_items.isEmpty) return Effect.succeed(const None());
    return Effect.succeed(Some(_items.first));
  });

  /// Lazily removes at most [limit] currently available items in FIFO order.
  ///
  /// This operation never waits for more items and returns an immutable list.
  /// Zero returns an empty list. A negative limit becomes an [ArgumentError]
  /// defect when the Effect runs.
  Effect<List<A>, Never> takeUpTo(int limit) => Effect.defer((_) {
    if (_isShutdown) return _shutdownEffect();
    checkNonNegative(limit, 'limit');

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
  Effect<void, Never> shutdown() => Effect.sync((_) => _shutdown());

  void _drain() {
    // Waiting takers imply an empty buffer; offers go directly to them.
    while (!_isShutdown && _offers.isNotEmpty) {
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

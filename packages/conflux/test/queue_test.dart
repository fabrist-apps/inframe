import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Queue', () {
    test('should lazily acquire independent bounded queues', () async {
      var acquisitions = 0;
      final acquisition = Queue.bounded<int>(2).tap((_) {
        acquisitions += 1;
        return Effect.succeed(null);
      });

      expect(acquisitions, 0);
      final queues = await Effect.build<List<Queue<int>>, Never>(($) async {
        return [await $(acquisition), await $(acquisition)];
      }).runFuture();

      expect(acquisitions, 2);
      expect(queues[0], isNot(same(queues[1])));
      expect(queues[0].capacity, 2);
      expect(queues[0].isShutdown, isTrue);
      expect(queues[1].isShutdown, isTrue);
    });

    test('should reject non-positive capacity when acquisition runs', () async {
      final acquisition = Queue.bounded<int>(0);

      final exit = await acquisition.runFutureExit();

      expect((exit as Failed<Queue<int>, Never>).cause, isA<Defect<Never>>());
    });

    test('should preserve FIFO items, takers, and blocked offerers', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);

      await fixture.run(fixture.queue.offer(0));
      final firstOffer = fixture.runtime.fork(fixture.queue.offer(1));
      await _flushMicrotasks();
      final secondOffer = fixture.runtime.fork(fixture.queue.offer(2));
      await _flushMicrotasks();

      expect(await fixture.run(fixture.queue.take()), 0);
      expect(await fixture.run(fixture.queue.take()), 1);
      expect(await fixture.run(fixture.queue.take()), 2);
      expect(firstOffer.join(), completion(isA<Succeeded<void, Never>>()));
      expect(secondOffer.join(), completion(isA<Succeeded<void, Never>>()));

      final firstTake = fixture.runtime.fork(fixture.queue.take());
      await _flushMicrotasks();
      final secondTake = fixture.runtime.fork(fixture.queue.take());
      await _flushMicrotasks();
      await fixture.run(fixture.queue.offer(3));
      await fixture.run(fixture.queue.offer(4));

      expect(_value(await firstTake.join()), 3);
      expect(_value(await secondTake.join()), 4);
      expect(fixture.queue.size, 0);
    });

    test('should block a full Queue until take releases capacity', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      await fixture.run(fixture.queue.offer(1));
      var completed = false;
      final blocked = fixture.runtime.fork(fixture.queue.offer(2));
      unawaited(blocked.exit.then((_) => completed = true));

      await _flushMicrotasks();
      expect(completed, isFalse);
      expect(fixture.queue.size, 1);

      expect(await fixture.run(fixture.queue.take()), 1);
      expect(await blocked.join(), isA<Succeeded<void, Never>>());
      expect(fixture.queue.size, 1);
      expect(await fixture.run(fixture.queue.take()), 2);
    });

    test('should remove cancelled offers without delivering their items', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      await fixture.run(fixture.queue.offer(0));
      final cancelled = fixture.runtime.fork(fixture.queue.offer(1));
      await _flushMicrotasks();

      final cancelledExit = await cancelled.interrupt('cancel offer');
      expect((cancelledExit as Failed<void, Never>).cause, isA<Interrupted<Never>>());
      expect(await fixture.run(fixture.queue.take()), 0);

      final waitingTake = fixture.runtime.fork(fixture.queue.take());
      await _flushMicrotasks();
      await fixture.run(fixture.queue.offer(2));
      expect(_value(await waitingTake.join()), 2);
    });

    test('should retain an item when cancellation follows offer commit', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final committed = fixture.runtime.fork(fixture.queue.offer(1));

      expect(await committed.join(), isA<Succeeded<void, Never>>());
      expect(await committed.interrupt('too late'), isA<Succeeded<void, Never>>());
      expect(await fixture.run(fixture.queue.take()), 1);
    });

    test('should remove a cancelled take without consuming a later item', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final cancelled = fixture.runtime.fork(fixture.queue.take());
      await _flushMicrotasks();

      final cancelledExit = await cancelled.interrupt('cancel take');
      expect((cancelledExit as Failed<int, Never>).cause, isA<Interrupted<Never>>());

      await fixture.run(fixture.queue.offer(1));
      expect(fixture.queue.size, 1);
      expect(await fixture.run(fixture.queue.take()), 1);
    });

    test('should poll an available item without waiting', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);

      expect(await fixture.run(fixture.queue.poll()), isA<None>());
      await fixture.run(fixture.queue.offer(1));
      expect(
        await fixture.run(fixture.queue.poll()),
        isA<Some<int>>().having((option) => option.value, 'value', 1),
      );
    });

    test('should distinguish a nullable item from an empty Queue', () async {
      final fixture = await _QueueFixture.acquire<int?>(1);
      addTearDown(fixture.close);

      expect(await fixture.run(fixture.queue.poll()), isA<None>());
      await fixture.run(fixture.queue.offer(null));
      final present = await fixture.run(fixture.queue.poll());

      expect(present, isA<Some<int?>>());
      expect((present as Some<int?>).value, isNull);
    });

    test('should peek without removing an item or releasing capacity', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      expect(await fixture.run(fixture.queue.peek()), isA<None>());
      await fixture.run(fixture.queue.offer(1));
      var offerCompleted = false;
      final blockedOffer = fixture.runtime.fork(fixture.queue.offer(2));
      unawaited(blockedOffer.exit.then((_) => offerCompleted = true));
      await _flushMicrotasks();

      final peeked = await fixture.run(fixture.queue.peek());

      expect((peeked as Some<int>).value, 1);
      expect(fixture.queue.size, 1);
      expect(offerCompleted, isFalse);
      expect((await fixture.run(fixture.queue.poll()) as Some<int>).value, 1);
      expect(await blockedOffer.join(), isA<Succeeded<void, Never>>());
      expect((await fixture.run(fixture.queue.poll()) as Some<int>).value, 2);
    });

    test('should take an immutable available batch without waiting', () async {
      final fixture = await _QueueFixture.acquire<int>(4);
      addTearDown(fixture.close);
      for (final item in [1, 2, 3]) {
        await fixture.run(fixture.queue.offer(item));
      }

      final first = await fixture.run(fixture.queue.takeUpTo(2));
      expect(first, [1, 2]);
      expect(() => first.add(4), throwsUnsupportedError);
      expect(fixture.queue.size, 1);
      expect(await fixture.run(fixture.queue.takeUpTo(10)), [3]);
      expect(await fixture.run(fixture.queue.takeUpTo(0)), isEmpty);

      final negative = fixture.queue.takeUpTo(-1);
      expect(
        (await fixture.runtime.run(negative) as Failed<List<int>, Never>).cause,
        isA<Defect<Never>>(),
      );
    });

    test('should preserve waiter fairness around nonblocking reads', () async {
      final fixture = await _QueueFixture.acquire<int>(2);
      addTearDown(fixture.close);
      final taker = fixture.runtime.fork(fixture.queue.take());
      await _flushMicrotasks();

      await fixture.run(fixture.queue.offer(1));
      expect(_value(await taker.join()), 1);
      expect(await fixture.run(fixture.queue.poll()), isA<None>());

      await fixture.run(fixture.queue.offer(2));
      await fixture.run(fixture.queue.offer(3));
      final blockedOffer = fixture.runtime.fork(fixture.queue.offer(4));
      await _flushMicrotasks();

      expect(await fixture.run(fixture.queue.takeUpTo(1)), [2]);
      expect(await blockedOffer.join(), isA<Succeeded<void, Never>>());
      expect(await fixture.run(fixture.queue.takeUpTo(5)), [3, 4]);
      expect(fixture.queue.size, 0);
    });

    test('should discard work and interrupt data operations on shutdown', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      await fixture.run(fixture.queue.offer(1));
      final blockedOffer = fixture.runtime.fork(fixture.queue.offer(2));
      await _flushMicrotasks();

      await fixture.run(fixture.queue.shutdown());
      await fixture.run(fixture.queue.shutdown());

      expect(fixture.queue.isShutdown, isTrue);
      expect(fixture.queue.size, 0);
      _expectQueueShutdown(await blockedOffer.join());
      _expectQueueShutdown(await fixture.runtime.run(fixture.queue.offer(3)));
      _expectQueueShutdown(await fixture.runtime.run(fixture.queue.take()));
      _expectQueueShutdown(await fixture.runtime.run(fixture.queue.poll()));
      _expectQueueShutdown(await fixture.runtime.run(fixture.queue.peek()));
      _expectQueueShutdown(await fixture.runtime.run(fixture.queue.takeUpTo(0)));
    });

    test('should interrupt a blocked take on shutdown', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final blockedTake = fixture.runtime.fork(fixture.queue.take());
      await _flushMicrotasks();

      await fixture.run(fixture.queue.shutdown());

      _expectQueueShutdown(await blockedTake.join());
    });

    test('should await completed shutdown bookkeeping cancellably', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      await fixture.run(fixture.queue.offer(1));
      var completed = false;
      final waiter = fixture.runtime.fork(fixture.queue.awaitShutdown());
      unawaited(waiter.exit.then((_) => completed = true));
      await _flushMicrotasks();
      expect(completed, isFalse);

      final cancelled = fixture.runtime.fork(fixture.queue.awaitShutdown());
      await _flushMicrotasks();
      expect(await cancelled.interrupt('stop waiting'), isA<Failed<void, Never>>());
      expect(fixture.queue.isShutdown, isFalse);

      await fixture.run(fixture.queue.shutdown());
      expect(await waiter.join(), isA<Succeeded<void, Never>>());
      await fixture.run(fixture.queue.awaitShutdown());
    });

    test('should shut down when the acquiring scope fails or is cancelled', () async {
      late Queue<int> failedQueue;
      final failed = Effect.build<void, Never>(($) async {
        failedQueue = await $(Queue.bounded<int>(1));
        throw StateError('fail owner');
      });

      expect(await failed.runFutureExit(), isA<Failed<void, Never>>());
      expect(failedQueue.isShutdown, isTrue);

      final fixture = await _QueueFixture.acquire<int>(1);
      final blockedTake = fixture.runtime.fork(fixture.queue.take());
      await _flushMicrotasks();
      await fixture.cancelOwner();

      expect(fixture.queue.isShutdown, isTrue);
      _expectQueueShutdown(await blockedTake.join());
      await fixture.runtime.close();
    });
  });
}

final class _QueueFixture<A> {
  _QueueFixture._(this.runtime, this.queue, this._owner, this._releaseOwner);

  final Runtime runtime;
  final Queue<A> queue;
  final Fiber<void, Never> _owner;
  final Completer<void> _releaseOwner;

  static Future<_QueueFixture<A>> acquire<A>(int capacity) async {
    final runtime = Runtime();
    final acquired = Completer<Queue<A>>();
    final releaseOwner = Completer<void>();
    final owner = runtime.fork(
      Effect.build<void, Never>(($) async {
        final queue = await $(Queue.bounded<A>(capacity));
        acquired.complete(queue);
        await $(
          Effect.tryFuture<void, Never>(
            () => releaseOwner.future,
            onError: Error.throwWithStackTrace,
          ),
        );
      }),
    );
    return _QueueFixture._(runtime, await acquired.future, owner, releaseOwner);
  }

  Future<T> run<T>(Effect<T, Never> effect) async {
    return _value(await runtime.run(effect));
  }

  Future<void> cancelOwner() async {
    await _owner.interrupt('cancel queue owner');
  }

  Future<void> close() async {
    if (!_releaseOwner.isCompleted) _releaseOwner.complete();
    await _owner.join();
    await runtime.close();
  }
}

A _value<A>(Exit<A, Never> exit) {
  return (exit as Succeeded<A, Never>).value;
}

void _expectQueueShutdown(Exit<Object?, Never> exit) {
  final cause = (exit as Failed<Object?, Never>).cause;
  expect(cause, isA<Interrupted<Never>>());
  expect((cause as Interrupted<Never>).reason, isA<QueueShutdown>());
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

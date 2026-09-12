import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Flow coordination sources', () {
    test('should distribute Queue items across competing consumers', () async {
      final fixture = await _QueueFixture.acquire<int>(2);
      addTearDown(fixture.close);
      final flow = Flow.fromQueue(fixture.queue);

      final first = fixture.runtime.fork(flow.take(1).runCollect());
      await _flushMicrotasks();
      final second = fixture.runtime.fork(flow.take(1).runCollect());
      await _flushMicrotasks();
      await fixture.run(fixture.queue.offer(1));
      await fixture.run(fixture.queue.offer(2));

      expect(_value(await first.join()), [1]);
      expect(_value(await second.join()), [2]);
      expect(fixture.queue.isShutdown, isFalse);
    });

    test('should cancel a Queue pull without stealing a later item', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final pending = fixture.runtime.fork(
        Flow.fromQueue(fixture.queue).runFirst(),
      );
      await _flushMicrotasks();

      final exit = await pending.interrupt('stop Queue Flow');
      final cause = (exit as Failed<Option<int>, Never>).cause;
      expect(cause, isA<Interrupted<Never>>());
      expect((cause as Interrupted<Never>).reason, 'stop Queue Flow');

      await fixture.run(fixture.queue.offer(9));
      expect(await fixture.run(fixture.queue.take()), 9);
      expect(fixture.queue.isShutdown, isFalse);
    });

    test('should preserve cancellation and cleanup failures from a Queue Flow', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final pending = fixture.runtime.fork(
        Flow.fromQueue(fixture.queue)
            .ensuring(
              Effect.sync((_) => throw StateError('cleanup failed')),
            )
            .runDrain(),
      );
      await _flushMicrotasks();

      final exit = await pending.interrupt('stop Queue Flow');

      final cause = (exit as Failed<void, Never>).cause;
      expect(cause, isA<Sequential<Never>>());
      final causes = (cause as Sequential<Never>).causes;
      expect(causes.first, isA<Interrupted<Never>>());
      expect((causes.first as Interrupted<Never>).reason, 'stop Queue Flow');
      expect(causes.last, isA<Defect<Never>>());
      expect(fixture.queue.isShutdown, isFalse);
    });

    test('should complete a Queue Flow only for Queue shutdown', () async {
      final fixture = await _QueueFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final observed = Completer<void>();
      final collecting = fixture.runtime.fork(
        Flow.fromQueue(fixture.queue).tap((_) {
          if (!observed.isCompleted) observed.complete();
          return Effect.succeed(null);
        }).runCollect(),
      );
      await _flushMicrotasks();

      await fixture.run(fixture.queue.offer(1));
      await observed.future;
      await fixture.run(fixture.queue.shutdown());

      expect(_value(await collecting.join()), [1]);
      expect(
        await Flow.fromQueue(fixture.queue).runCollect().runFuture(),
        isEmpty,
      );
    });

    test('should fan publications out through independent Flow scopes', () async {
      final fixture = await _PubSubFixture.acquire<int>(2);
      addTearDown(fixture.close);

      final values = await fixture.run(
        Effect.build<List<List<int>>, Never>(($) async {
          final first = await $(Flow.fromPubSub(fixture.pubsub).open());
          final second = await $(Flow.fromPubSub(fixture.pubsub).open());
          await $(fixture.pubsub.publish(1));
          await $(fixture.pubsub.publish(2));

          return [
            [
              _some(await $(first.next())),
              _some(await $(first.next())),
            ],
            [
              _some(await $(second.next())),
              _some(await $(second.next())),
            ],
          ];
        }),
      );

      expect(values, [
        [1, 2],
        [1, 2],
      ]);
      expect(fixture.pubsub.isShutdown, isFalse);
    });

    test('should release PubSub capacity after an early Flow exit', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final remaining = await fixture.subscribe();
      final first = fixture.runtime.fork(
        Flow.fromPubSub(fixture.pubsub).runFirst(),
      );
      await _flushMicrotasks();

      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(remaining.take()), 1);
      expect(_some(_value(await first.join())), 1);

      await fixture.run(fixture.pubsub.publish(2));
      expect(await fixture.run(remaining.take()), 2);
      expect(fixture.pubsub.isShutdown, isFalse);
    });

    test('should remove a cancelled PubSub Flow subscription', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final remaining = await fixture.subscribe();
      final cancelled = fixture.runtime.fork(
        Flow.fromPubSub(fixture.pubsub).runFirst(),
      );
      await _flushMicrotasks();

      final exit = await cancelled.interrupt('stop PubSub Flow');
      final cause = (exit as Failed<Option<int>, Never>).cause;
      expect(cause, isA<Interrupted<Never>>());
      expect((cause as Interrupted<Never>).reason, 'stop PubSub Flow');

      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(remaining.take()), 1);
      await fixture.run(fixture.pubsub.publish(2));
      expect(await fixture.run(remaining.take()), 2);
    });

    test('should release a PubSub subscription after a downstream defect', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final remaining = await fixture.subscribe();
      final failed = fixture.runtime.fork(
        Flow.fromPubSub(fixture.pubsub)
            .tap((_) => Effect.sync((_) => throw StateError('consumer failed')))
            .runDrain(),
      );
      await _flushMicrotasks();

      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(remaining.take()), 1);
      expect(
        (await failed.join() as Failed<void, Never>).cause,
        isA<Defect<Never>>(),
      );

      await fixture.run(fixture.pubsub.publish(2));
      expect(await fixture.run(remaining.take()), 2);
      var thirdCompleted = false;
      final third = fixture.runtime.fork(fixture.pubsub.publish(3));
      unawaited(third.exit.then((_) => thirdCompleted = true));
      await _flushMicrotasks();

      expect(thirdCompleted, isTrue);
      expect(await third.join(), isA<Succeeded<void, Never>>());
      expect(await fixture.run(remaining.take()), 3);
      expect(fixture.pubsub.isShutdown, isFalse);
    });

    test('should treat active and pre-existing PubSub shutdown as completion', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final collecting = fixture.runtime.fork(
        Flow.fromPubSub(fixture.pubsub).runCollect(),
      );
      await _flushMicrotasks();

      await fixture.run(fixture.pubsub.shutdown());

      expect(_value(await collecting.join()), isEmpty);
      expect(
        await Flow.fromPubSub(fixture.pubsub).runCollect().runFuture(),
        isEmpty,
      );
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
        await $(_waitFor(releaseOwner.future));
      }),
    );
    return _QueueFixture._(runtime, await acquired.future, owner, releaseOwner);
  }

  Future<T> run<T>(Effect<T, Never> effect) async {
    return _value(await runtime.run(effect));
  }

  Future<void> close() async {
    if (!_releaseOwner.isCompleted) _releaseOwner.complete();
    await _owner.join();
    await runtime.close();
  }
}

final class _PubSubFixture<A> {
  _PubSubFixture._(this.runtime, this.pubsub, this._owner, this._releaseOwner);

  final Runtime runtime;
  final PubSub<A> pubsub;
  final Fiber<void, Never> _owner;
  final Completer<void> _releaseOwner;
  final List<_OwnedSubscription<A>> _subscriptions = [];

  static Future<_PubSubFixture<A>> acquire<A>(int capacity) async {
    final runtime = Runtime();
    final acquired = Completer<PubSub<A>>();
    final releaseOwner = Completer<void>();
    final owner = runtime.fork(
      Effect.build<void, Never>(($) async {
        final pubsub = await $(PubSub.bounded<A>(capacity));
        acquired.complete(pubsub);
        await $(_waitFor(releaseOwner.future));
      }),
    );
    return _PubSubFixture._(
      runtime,
      await acquired.future,
      owner,
      releaseOwner,
    );
  }

  Future<T> run<T>(Effect<T, Never> effect) async {
    return _value(await runtime.run(effect));
  }

  Future<PubSubSubscription<A>> subscribe() async {
    final acquired = Completer<PubSubSubscription<A>>();
    final releaseOwner = Completer<void>();
    final owner = runtime.fork(
      Effect.build<void, Never>(($) async {
        final subscription = await $(pubsub.subscribe());
        acquired.complete(subscription);
        await $(_waitFor(releaseOwner.future));
      }),
    );
    final subscription = await acquired.future;
    _subscriptions.add(_OwnedSubscription(subscription, owner, releaseOwner));
    return subscription;
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.close();
    }
    if (!_releaseOwner.isCompleted) _releaseOwner.complete();
    await _owner.join();
    await runtime.close();
  }
}

final class _OwnedSubscription<A> {
  _OwnedSubscription(this.subscription, this.owner, this.releaseOwner);

  final PubSubSubscription<A> subscription;
  final Fiber<void, Never> owner;
  final Completer<void> releaseOwner;

  Future<void> close() async {
    if (!releaseOwner.isCompleted) releaseOwner.complete();
    await owner.join();
  }
}

Effect<void, Never> _waitFor(Future<void> future) {
  return Effect.tryFuture<void, Never>(
    () => future,
    onError: Error.throwWithStackTrace,
  );
}

A _value<A>(Exit<A, Never> exit) {
  return (exit as Succeeded<A, Never>).value;
}

A _some<A>(Option<A> option) => (option as Some<A>).value;

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

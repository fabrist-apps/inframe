import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('PubSub', () {
    test('should lazily acquire independent bounded PubSubs', () async {
      var acquisitions = 0;
      final acquisition = PubSub.bounded<int>(2).tap((_) {
        acquisitions += 1;
        return Effect.succeed(null);
      });

      expect(acquisitions, 0);
      final pubsubs = await Effect.build<List<PubSub<int>>, Never>(($) async {
        return [await $(acquisition), await $(acquisition)];
      }).runFuture();

      expect(acquisitions, 2);
      expect(pubsubs[0], isNot(same(pubsubs[1])));
      expect(pubsubs[0].isShutdown, isTrue);
      expect(pubsubs[1].isShutdown, isTrue);
    });

    test('should reject non-positive capacity when acquisition runs', () async {
      final exit = await PubSub.bounded<int>(0).runFutureExit();

      expect((exit as Failed<PubSub<int>, Never>).cause, isA<Defect<Never>>());
    });

    test('should discard publications made without subscribers', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      await fixture.run(fixture.pubsub.publish(1));
      final subscription = await fixture.subscribe();
      final waiting = fixture.runtime.fork(subscription.take());
      await _flushMicrotasks();

      await fixture.run(fixture.pubsub.publish(2));

      expect(_value(await waiting.join()), 2);
    });

    test('should publish in common order to the captured subscriber set', () async {
      final fixture = await _PubSubFixture.acquire<int>(3);
      addTearDown(fixture.close);
      final first = await fixture.subscribe();
      final second = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(1));
      final late = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(2));

      expect(await fixture.run(first.takeUpTo(3)), [1, 2]);
      expect(await fixture.run(second.takeUpTo(3)), [1, 2]);
      expect(await fixture.run(late.takeUpTo(3)), [2]);
    });

    test('should let the slowest subscriber control backpressure', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final fast = await fixture.subscribe();
      final slow = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(fast.take()), 1);
      var completed = false;
      final blocked = fixture.runtime.fork(fixture.pubsub.publish(2));
      unawaited(blocked.exit.then((_) => completed = true));
      await _flushMicrotasks();

      expect(completed, isFalse);
      expect(await fixture.run(slow.take()), 1);
      expect(await blocked.join(), isA<Succeeded<void, Never>>());
      expect(await fixture.run(fast.take()), 2);
      expect(await fixture.run(slow.take()), 2);
    });

    test('should commit blocked publications in FIFO order', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final subscription = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(1));
      final second = fixture.runtime.fork(fixture.pubsub.publish(2));
      await _flushMicrotasks();
      var thirdCompleted = false;
      final third = fixture.runtime.fork(fixture.pubsub.publish(3));
      unawaited(third.exit.then((_) => thirdCompleted = true));
      await _flushMicrotasks();

      expect(await fixture.run(subscription.take()), 1);
      expect(await second.join(), isA<Succeeded<void, Never>>());
      expect(thirdCompleted, isFalse);
      expect(await fixture.run(subscription.take()), 2);
      expect(await third.join(), isA<Succeeded<void, Never>>());
      expect(await fixture.run(subscription.take()), 3);
    });

    test('should cancel a publication before commit without partial delivery', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final fast = await fixture.subscribe();
      final slow = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(fast.take()), 1);
      final publication = fixture.runtime.fork(fixture.pubsub.publish(2));
      await _flushMicrotasks();
      var fastReadCompleted = false;
      final fastRead = fixture.runtime.fork(fast.take());
      unawaited(fastRead.exit.then((_) => fastReadCompleted = true));
      await _flushMicrotasks();

      expect(await publication.interrupt('cancel publication'), isA<Failed<void, Never>>());
      expect(fastReadCompleted, isFalse);
      expect(await fixture.run(slow.take()), 1);
      await fixture.run(fixture.pubsub.publish(3));

      expect(_value(await fastRead.join()), 3);
      expect(await fixture.run(slow.take()), 3);
    });

    test('should retain delivery when cancellation follows publication commit', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final subscription = await fixture.subscribe();
      final committed = fixture.runtime.fork(fixture.pubsub.publish(1));

      expect(await committed.join(), isA<Succeeded<void, Never>>());
      expect(await committed.interrupt('too late'), isA<Succeeded<void, Never>>());
      expect(await fixture.run(subscription.take()), 1);
    });

    test('should remove a cancelled subscription take', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final subscription = await fixture.subscribe();
      final cancelled = fixture.runtime.fork(subscription.take());
      await _flushMicrotasks();

      expect(await cancelled.interrupt('cancel take'), isA<Failed<int, Never>>());
      await fixture.run(fixture.pubsub.publish(1));

      expect(await fixture.run(subscription.take()), 1);
    });

    test('should not retain cancelled work at a scheduling boundary', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final subscription = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(0));

      final publication = fixture.runtime.fork(
        _atWaiterRegistrationBoundary(fixture.pubsub.publish(1)),
      );
      expect(await _interruptNextEventTurn(publication), isA<Failed<void, Never>>());
      expect(await fixture.run(subscription.take()), 0);
      expect(await fixture.run(subscription.takeUpTo(1)), isEmpty);

      final take = fixture.runtime.fork(
        _atWaiterRegistrationBoundary(subscription.take()),
      );
      expect(await _interruptNextEventTurn(take), isA<Failed<int, Never>>());
      await fixture.run(fixture.pubsub.publish(2));
      expect(await fixture.run(subscription.takeUpTo(1)), [2]);

      await fixture.cancelSubscription(subscription);
      final acquisition = fixture.runtime.fork(
        _atSubscriptionRegistrationBoundary(fixture.pubsub.subscribe()),
      );
      expect(
        await _interruptNextEventTurn(acquisition),
        isA<Failed<PubSubSubscription<int>, Never>>(),
      );

      final active = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(3));
      expect(await fixture.run(active.take()), 3);
      var completed = false;
      final next = fixture.runtime.fork(fixture.pubsub.publish(4));
      unawaited(next.exit.then((_) => completed = true));
      await _flushMicrotasks();

      expect(completed, isTrue);
      expect(await next.join(), isA<Succeeded<void, Never>>());
      expect(await fixture.run(active.take()), 4);
    });

    test('should take immutable available batches without waiting', () async {
      final fixture = await _PubSubFixture.acquire<int>(3);
      addTearDown(fixture.close);
      final subscription = await fixture.subscribe();
      for (final item in [1, 2, 3]) {
        await fixture.run(fixture.pubsub.publish(item));
      }

      final first = await fixture.run(subscription.takeUpTo(2));

      expect(first, [1, 2]);
      expect(() => first.add(4), throwsUnsupportedError);
      expect(await fixture.run(subscription.takeUpTo(10)), [3]);
      expect(await fixture.run(subscription.takeUpTo(0)), isEmpty);
      final negative = subscription.takeUpTo(-1);
      expect(
        (await fixture.runtime.run(negative) as Failed<List<int>, Never>).cause,
        isA<Defect<Never>>(),
      );
    });

    test('should unsubscribe idempotently and release retained capacity', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final fast = await fixture.subscribe();
      final slow = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(fast.take()), 1);
      final blocked = fixture.runtime.fork(fixture.pubsub.publish(2));
      await _flushMicrotasks();

      await fixture.run(slow.unsubscribe());
      await fixture.run(slow.unsubscribe());

      expect(await blocked.join(), isA<Succeeded<void, Never>>());
      expect(await fixture.run(fast.take()), 2);
      _expectSubscriptionClosed(await fixture.runtime.run(slow.take()));
      await fixture.run(fixture.pubsub.publish(3));
      expect(await fixture.run(fast.take()), 3);
    });

    test('should unsubscribe automatically when the acquiring scope exits', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final remaining = await fixture.subscribe();
      final scoped = await fixture.subscribe();
      final scopedRead = fixture.runtime.fork(scoped.take());
      await _flushMicrotasks();

      await fixture.closeSubscription(scoped);

      _expectSubscriptionClosed(await scopedRead.join());
      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(remaining.take()), 1);
    });

    test('should clean up subscription scopes on failure and cancellation', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      late PubSubSubscription<int> failedSubscription;
      final failed = Effect.build<void, Never>(($) async {
        failedSubscription = await $(fixture.pubsub.subscribe());
        throw StateError('fail subscriber');
      });

      expect(await fixture.runtime.run(failed), isA<Failed<void, Never>>());
      _expectSubscriptionClosed(
        await fixture.runtime.run(failedSubscription.take()),
      );

      final cancelledSubscription = await fixture.subscribe();
      final pendingRead = fixture.runtime.fork(cancelledSubscription.take());
      await _flushMicrotasks();
      await fixture.cancelSubscription(cancelledSubscription);

      _expectSubscriptionClosed(await pendingRead.join());
    });

    test('should shut down publishers and subscribers immediately', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      final fast = await fixture.subscribe();
      final slow = await fixture.subscribe();
      await fixture.run(fixture.pubsub.publish(1));
      expect(await fixture.run(fast.take()), 1);
      final publisher = fixture.runtime.fork(fixture.pubsub.publish(2));
      final reader = fixture.runtime.fork(fast.take());
      await _flushMicrotasks();

      await fixture.run(fixture.pubsub.shutdown());
      await fixture.run(fixture.pubsub.shutdown());

      expect(fixture.pubsub.isShutdown, isTrue);
      _expectPubSubShutdown(await publisher.join());
      _expectPubSubShutdown(await reader.join());
      _expectPubSubShutdown(await fixture.runtime.run(slow.take()));
      _expectPubSubShutdown(
        await fixture.runtime.run(fixture.pubsub.publish(3)),
      );
      _expectPubSubShutdown(
        await fixture.runtime.run(fixture.pubsub.subscribe()),
      );
      await fixture.run(slow.unsubscribe());
    });

    test('should await completed PubSub shutdown cancellably', () async {
      final fixture = await _PubSubFixture.acquire<int>(1);
      addTearDown(fixture.close);
      var completed = false;
      final waiter = fixture.runtime.fork(fixture.pubsub.awaitShutdown());
      unawaited(waiter.exit.then((_) => completed = true));
      await _flushMicrotasks();
      expect(completed, isFalse);

      final cancelled = fixture.runtime.fork(fixture.pubsub.awaitShutdown());
      await _flushMicrotasks();
      expect(await cancelled.interrupt('stop waiting'), isA<Failed<void, Never>>());
      expect(fixture.pubsub.isShutdown, isFalse);

      await fixture.run(fixture.pubsub.shutdown());
      expect(await waiter.join(), isA<Succeeded<void, Never>>());
      await fixture.run(fixture.pubsub.awaitShutdown());
    });

    test('should shut down when the acquiring scope fails or is cancelled', () async {
      late PubSub<int> failedPubSub;
      final failed = Effect.build<void, Never>(($) async {
        failedPubSub = await $(PubSub.bounded<int>(1));
        throw StateError('fail owner');
      });

      expect(await failed.runFutureExit(), isA<Failed<void, Never>>());
      expect(failedPubSub.isShutdown, isTrue);

      final fixture = await _PubSubFixture.acquire<int>(1);
      final subscription = await fixture.subscribe();
      final blockedRead = fixture.runtime.fork(subscription.take());
      await _flushMicrotasks();
      await fixture.cancelOwner();

      expect(fixture.pubsub.isShutdown, isTrue);
      _expectPubSubShutdown(await blockedRead.join());
      await fixture.close();
    });
  });
}

final class _PubSubFixture<A> {
  _PubSubFixture._(
    this.runtime,
    this.pubsub,
    this._owner,
    this._releaseOwner,
  );

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
    _subscriptions.add(
      _OwnedSubscription(subscription, owner, releaseOwner),
    );
    return subscription;
  }

  Future<T> run<T>(Effect<T, Never> effect) async {
    return _value(await runtime.run(effect));
  }

  Future<void> closeSubscription(PubSubSubscription<A> subscription) async {
    final owned = _subscriptions.singleWhere(
      (candidate) => identical(candidate.subscription, subscription),
    );
    await owned.close();
  }

  Future<void> cancelSubscription(
    PubSubSubscription<A> subscription,
  ) async {
    final owned = _subscriptions.singleWhere(
      (candidate) => identical(candidate.subscription, subscription),
    );
    await owned.owner.interrupt('cancel subscription owner');
  }

  Future<void> cancelOwner() => _owner.interrupt('cancel PubSub owner');

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

void _expectSubscriptionClosed(Exit<Object?, Never> exit) {
  final cause = (exit as Failed<Object?, Never>).cause;
  expect(cause, isA<Interrupted<Never>>());
  expect(
    (cause as Interrupted<Never>).reason,
    isA<PubSubSubscriptionClosed>(),
  );
}

void _expectPubSubShutdown(Exit<Object?, Never> exit) {
  final cause = (exit as Failed<Object?, Never>).cause;
  expect(cause, isA<Interrupted<Never>>());
  expect((cause as Interrupted<Never>).reason, isA<PubSubShutdown>());
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Effect<A, E> _atWaiterRegistrationBoundary<A, E>(Effect<A, E> effect) {
  // The operation's defer is step 255; its waiter adapter reaches the runtime's
  // cooperative boundary at step 256.
  return _afterEvaluationSteps(effect, 254);
}

Effect<A, E> _atSubscriptionRegistrationBoundary<A, E>(Effect<A, E> effect) {
  // The former subscription acquisition created state at step 255, immediately
  // before finalizer registration crossed the step-256 boundary.
  return _afterEvaluationSteps(effect, 252);
}

Effect<A, E> _afterEvaluationSteps<A, E>(Effect<A, E> effect, int count) {
  var wrapped = effect;
  for (var index = 0; index < count; index += 1) {
    final inner = wrapped;
    wrapped = Effect.defer(() => inner);
  }
  return wrapped;
}

Future<Exit<A, E>> _interruptNextEventTurn<A, E>(Fiber<A, E> fiber) {
  return Future<void>.delayed(Duration.zero).then(
    (_) => fiber.interrupt('cancel at scheduling boundary'),
  );
}

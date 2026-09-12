import 'dart:async';

import 'package:conflux/cache.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/fake_clock.dart';

void main() {
  group('Cache', () {
    test('should share a successful lookup and retain its value', () async {
      final lookupStarted = Completer<void>();
      final releaseLookup = Completer<int>();
      var lookups = 0;
      final fixture = await _CacheFixture.start(
        lookup: (_) => Effect.tryFuture<int, String>(
          () {
            lookups += 1;
            lookupStarted.complete();
            return releaseLookup.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);

      final first = Runtime().fork(fixture.cache.get('key'));
      final second = Runtime().fork(fixture.cache.get('key'));
      await lookupStarted.future;
      releaseLookup.complete(42);

      expect((await first.join() as Succeeded<int, String>).value, 42);
      expect((await second.join() as Succeeded<int, String>).value, 42);
      expect(await fixture.cache.get('key').runFuture(), 42);
      expect(lookups, 1);
    });

    test('should retry a failed lookup without caching its error', () async {
      var lookups = 0;
      final fixture = await _CacheFixture.start(
        lookup: (_) => Effect.defer((_) {
          lookups += 1;
          return lookups == 1
              ? Effect.fail<int, String>('unavailable')
              : Effect.succeed<int, String>(42);
        }),
      );
      addTearDown(fixture.close);

      final failed = await Runtime().run(fixture.cache.get('key'));
      final succeeded = await Runtime().run(fixture.cache.get('key'));

      final failure = (failed as Failed<int, String>).cause as Expected<String>;
      expect(failure.error, 'unavailable');
      expect((succeeded as Succeeded<int, String>).value, 42);
      expect(lookups, 2);
    });

    test('should use the Context captured when the Cache is created', () async {
      final serviceKey = ContextKey<int>('service');
      final fixture = await _CacheFixture.start(
        ownerContext: Context().withBinding(serviceKey.bind(1)),
        lookup: (_) => Effect.context((context) => context.require(serviceKey)),
      );
      addTearDown(fixture.close);
      final caller = Runtime(
        context: Context().withBinding(serviceKey.bind(2)),
      );
      addTearDown(caller.close);

      final exit = await caller.run(fixture.cache.get('key'));

      expect((exit as Succeeded<int, String>).value, 1);
    });

    test('should keep a shared load running when one waiter is cancelled', () async {
      final lookupStarted = Completer<void>();
      final releaseLookup = Completer<int>();
      final fixture = await _CacheFixture.start(
        lookup: (_) => Effect.tryFuture<int, String>(
          () {
            lookupStarted.complete();
            return releaseLookup.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final cancelled = caller.fork(fixture.cache.get('key'));
      final remaining = caller.fork(fixture.cache.get('key'));
      await lookupStarted.future;

      final cancelledExit = await cancelled.interrupt('caller stopped');
      releaseLookup.complete(42);

      expect((cancelledExit as Failed<int, String>).cause, isA<Interrupted<String>>());
      expect((await remaining.join() as Succeeded<int, String>).value, 42);
    });

    test('should bound active lookups independently across keys', () async {
      final gates = <String, Completer<int>>{
        'a': Completer<int>(),
        'b': Completer<int>(),
        'c': Completer<int>(),
      };
      final started = <String>[];
      final fixture = await _CacheFixture.start(
        concurrency: 2,
        lookup: (key) => Effect.tryFuture<int, String>(
          () {
            started.add(key);
            return gates[key]!.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final first = caller.fork(fixture.cache.get('a'));
      final second = caller.fork(fixture.cache.get('b'));
      final third = caller.fork(fixture.cache.get('c'));
      await _flushMicrotasks();

      expect(started, ['a', 'b']);

      gates['a']!.complete(1);
      await _flushMicrotasks();
      expect(started, ['a', 'b', 'c']);
      gates['b']!.complete(2);
      gates['c']!.complete(3);
      expect((await first.join() as Succeeded<int, String>).value, 1);
      expect((await second.join() as Succeeded<int, String>).value, 2);
      expect((await third.join() as Succeeded<int, String>).value, 3);
    });

    test('should evict the least recently used retained value', () async {
      final lookups = <String, int>{};
      final fixture = await _CacheFixture.start(
        capacity: 2,
        lookup: (key) => Effect.sync((_) {
          lookups.update(key, (count) => count + 1, ifAbsent: () => 1);
          return key.codeUnitAt(0);
        }),
      );
      addTearDown(fixture.close);

      await fixture.cache.get('a').runFuture();
      await fixture.cache.get('b').runFuture();
      await fixture.cache.get('a').runFuture();
      await fixture.cache.get('c').runFuture();
      await fixture.cache.get('b').runFuture();

      expect(lookups, {'a': 1, 'b': 2, 'c': 1});
    });

    test('should discard expired entries before applying LRU capacity', () async {
      final clock = FakeClock();
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        capacity: 2,
        expiry: CacheExpiry.byValue(
          (_, value) => value == 1 ? const Duration(seconds: 1) : const Duration(minutes: 1),
        ),
        lookup: (key) => Effect.succeed(
          switch (key) {
            'live' => 2,
            'expired' => 1,
            _ => 3,
          },
        ),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('live').runFuture();
      await fixture.cache.get('expired').runFuture();
      clock.advanceMonotonic(const Duration(seconds: 1));

      await fixture.cache.get('new').runFuture();

      expect(
        await fixture.cache.getOption('live').runFuture(),
        isA<Some<int>>().having((option) => option.value, 'value', 2),
      );
      expect(fixture.cache.keys, ['new', 'live']);
    });

    test('should count a shared load as one active lookup', () async {
      final firstGate = Completer<int>();
      final secondGate = Completer<int>();
      final started = <String>[];
      final fixture = await _CacheFixture.start(
        concurrency: 1,
        lookup: (key) => Effect.tryFuture<int, String>(
          () {
            started.add(key);
            return key == 'a' ? firstGate.future : secondGate.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final first = caller.fork(fixture.cache.get('a'));
      final shared = caller.fork(fixture.cache.get('a'));
      final second = caller.fork(fixture.cache.get('b'));
      await _flushMicrotasks();

      expect(started, ['a']);
      firstGate.complete(1);
      await _flushMicrotasks();
      expect(started, ['a', 'b']);
      secondGate.complete(2);

      expect((await first.join() as Succeeded<int, String>).value, 1);
      expect((await shared.join() as Succeeded<int, String>).value, 1);
      expect((await second.join() as Succeeded<int, String>).value, 2);
    });

    test('should release an active slot when a lookup fails', () async {
      final started = <String>[];
      final fixture = await _CacheFixture.start(
        concurrency: 1,
        lookup: (key) => Effect.defer((_) {
          started.add(key);
          return key == 'a' ? Effect.fail<int, String>('failed') : Effect.succeed<int, String>(2);
        }),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);

      final failed = caller.fork(fixture.cache.get('a'));
      final succeeded = caller.fork(fixture.cache.get('b'));

      expect(await failed.join(), isA<Failed<int, String>>());
      expect((await succeeded.join() as Succeeded<int, String>).value, 2);
      expect(started, ['a', 'b']);
    });

    test('should interrupt active and queued lookups when closed', () async {
      final activeStarted = Completer<void>();
      final activeGate = Completer<int>();
      final started = <String>[];
      var lookupCancelled = false;
      final fixture = await _CacheFixture.start(
        concurrency: 1,
        lookup: (key) => Effect.tryFuture<int, String>(
          () {
            started.add(key);
            if (key == 'a') activeStarted.complete();
            return activeGate.future;
          },
          onError: (error, _) => '$error',
          onCancel: () => lookupCancelled = true,
        ),
      );
      final caller = Runtime();
      addTearDown(caller.close);
      final active = caller.fork(fixture.cache.get('a'));
      final queued = caller.fork(fixture.cache.get('b'));
      await activeStarted.future;

      await fixture.close();

      expect(started, ['a']);
      expect(lookupCancelled, isTrue);
      expect((await active.join() as Failed<int, String>).cause, isA<Interrupted<String>>());
      expect((await queued.join() as Failed<int, String>).cause, isA<Interrupted<String>>());
      final closedExit = await caller.run(fixture.cache.get('other'));
      expect((closedExit as Failed<int, String>).cause, isA<Defect<String>>());
    });

    test('should reject non-positive capacity and concurrency at acquisition', () async {
      for (final configuration in [(capacity: 0, concurrency: 1), (capacity: 1, concurrency: 0)]) {
        final exit = await Cache.make<String, int, String>(
          capacity: configuration.capacity,
          concurrency: configuration.concurrency,
          expiry: CacheExpiry.fixed(const Duration(minutes: 1)),
          lookup: (_) => Effect.succeed(1),
        ).runFutureExit();

        final cause = (exit as Failed<Cache<String, int, String>, Never>).cause;
        expect(cause, isA<Defect<Never>>());
        expect((cause as Defect<Never>).error, isA<ArgumentError>());
      }
    });

    test('should not dispose values evicted from the Cache', () async {
      final values = <String, _BorrowedValue>{};
      final fixture = await _CacheFixture.start(
        capacity: 1,
        lookup: (key) => Effect.sync((_) {
          return values.putIfAbsent(key, _BorrowedValue.new);
        }),
      );
      addTearDown(fixture.close);

      await fixture.cache.get('a').runFuture();
      await fixture.cache.get('b').runFuture();

      expect(values['a']!.closed, isFalse);
    });

    test('should start fixed expiry when a lookup succeeds', () async {
      final clock = FakeClock();
      final lookupStarted = Completer<void>();
      final lookupGate = Completer<int>();
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.fixed(const Duration(seconds: 5)),
        lookup: (_) => Effect.tryFuture<int, String>(
          () {
            lookupStarted.complete();
            return lookupGate.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final loading = caller.fork(fixture.cache.get('key'));
      await lookupStarted.future;

      clock.advanceMonotonic(const Duration(seconds: 10));
      lookupGate.complete(42);
      await loading.join();
      clock.advanceMonotonic(const Duration(seconds: 4));
      expect(await fixture.cache.getOption('key').runFuture(), isA<Some<int>>());

      clock.advanceMonotonic(const Duration(seconds: 1));
      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
    });

    test('should inspect pending and nullable values without loading or waiting', () async {
      final lookupStarted = Completer<void>();
      final lookupGate = Completer<int?>();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int?>(
        lookup: (_) => Effect.tryFuture<int?, String>(
          () {
            lookups += 1;
            lookupStarted.complete();
            return lookupGate.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final loading = caller.fork(fixture.cache.get('key'));
      await lookupStarted.future;

      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
      expect(await fixture.cache.containsKey('key').runFuture(), isFalse);
      expect(lookups, 1);

      lookupGate.complete(null);
      await loading.join();
      final ready = await fixture.cache.getOption('key').runFuture();
      expect(ready, isA<Some<int?>>());
      expect((ready as Some<int?>).value, isNull);
      expect(await fixture.cache.containsKey('key').runFuture(), isTrue);
      expect(lookups, 1);
    });

    test('should apply value-dependent expiry at the exact boundary', () async {
      final clock = FakeClock();
      final expiryInputs = <(String, int)>[];
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.byValue((key, value) {
          expiryInputs.add((key, value));
          return Duration(seconds: value);
        }),
        lookup: (_) => Effect.succeed(3),
      );
      addTearDown(fixture.close);

      await fixture.cache.get('key').runFuture();
      clock.advanceMonotonic(const Duration(seconds: 2));
      expect(await fixture.cache.containsKey('key').runFuture(), isTrue);

      clock.advanceMonotonic(const Duration(seconds: 1));
      expect(await fixture.cache.containsKey('key').runFuture(), isFalse);
      expect(expiryInputs, [('key', 3)]);
    });

    test('should use its captured monotonic Clock for ready observations', () async {
      final ownerClock = FakeClock();
      final callerClock = FakeClock();
      final fixture = await _CacheFixture.start<int>(
        ownerClock: ownerClock,
        expiry: CacheExpiry.fixed(const Duration(seconds: 5)),
        lookup: (_) => Effect.succeed(42),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('key').runFuture();
      ownerClock.adjustWall(const Duration(days: 30));
      callerClock.advanceMonotonic(const Duration(days: 30));
      final caller = Runtime(clock: callerClock);
      addTearDown(caller.close);

      final ready = await caller.run(fixture.cache.getOption('key'));
      expect((ready as Succeeded<Option<int>, Never>).value, isA<Some<int>>());
      ownerClock.advanceMonotonic(const Duration(seconds: 5));
      final expired = await caller.run(fixture.cache.getOption('key'));
      expect((expired as Succeeded<Option<int>, Never>).value, isA<None>());
    });

    test('should reload an expired successful value', () async {
      final clock = FakeClock();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.fixed(const Duration(seconds: 1)),
        lookup: (_) => Effect.sync((_) => ++lookups),
      );
      addTearDown(fixture.close);

      expect(await fixture.cache.get('key').runFuture(), 1);
      clock.advanceMonotonic(const Duration(seconds: 1));
      expect(await fixture.cache.get('key').runFuture(), 2);
    });

    test('should snapshot ready entries without pending or expired values', () async {
      final clock = FakeClock();
      final pending = Completer<int>();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.fixed(const Duration(seconds: 5)),
        lookup: (key) => Effect.defer((_) {
          lookups += 1;
          return key == 'pending'
              ? Effect.tryFuture<int, String>(
                  () => pending.future,
                  onError: (error, _) => '$error',
                )
              : Effect.succeed(key.codeUnitAt(0));
        }),
      );
      addTearDown(fixture.close);

      await fixture.cache.get('a').runFuture();
      await fixture.cache.get('b').runFuture();
      final caller = Runtime();
      addTearDown(caller.close);
      caller.fork(fixture.cache.get('pending'));
      await _flushMicrotasks();

      expect(fixture.cache.size, 2);
      expect(fixture.cache.keys, ['a', 'b']);
      expect(fixture.cache.values, [97, 98]);
      expect(
        fixture.cache.entries.map((entry) => (entry.key, entry.value)),
        [('a', 97), ('b', 98)],
      );
      expect(() => fixture.cache.keys.add('c'), throwsUnsupportedError);
      expect(lookups, 3);

      clock.advanceMonotonic(const Duration(seconds: 5));
      expect(fixture.cache.size, 0);
      expect(fixture.cache.keys, isEmpty);
      expect(lookups, 3);
    });

    test('should reject ready observations after scope closure', () async {
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.succeed(42),
      );
      await fixture.cache.get('key').runFuture();
      await fixture.close();

      final optionExit = await fixture.cache.getOption('key').runFutureExit();
      final membershipExit = await fixture.cache.containsKey('key').runFutureExit();

      expect((optionExit as Failed<Option<int>, Never>).cause, isA<Defect<Never>>());
      expect((membershipExit as Failed<bool, Never>).cause, isA<Defect<Never>>());
      expect(() => fixture.cache.size, throwsStateError);
      expect(() => fixture.cache.keys, throwsStateError);
      expect(() => fixture.cache.values, throwsStateError);
      expect(() => fixture.cache.entries, throwsStateError);
    });

    test('should keep a set value when an older lookup completes', () async {
      final clock = FakeClock();
      final lookupStarted = Completer<void>();
      final lookupGate = Completer<int>();
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.fixed(const Duration(seconds: 5)),
        lookup: (_) => Effect.tryFuture<int, String>(
          () {
            lookupStarted.complete();
            return lookupGate.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final oldWaiter = caller.fork(fixture.cache.get('key'));
      await lookupStarted.future;

      await fixture.cache.set('key', 2).runFuture();
      lookupGate.complete(1);

      expect((await oldWaiter.join() as Succeeded<int, String>).value, 1);
      expect(await fixture.cache.get('key').runFuture(), 2);
      clock.advanceMonotonic(const Duration(seconds: 5));
      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
    });

    test('should let old waiters finish without repopulating an invalidated key', () async {
      final gates = [Completer<int>(), Completer<int>()];
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.tryFuture<int, String>(
          () => gates[lookups++].future,
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final oldWaiter = caller.fork(fixture.cache.get('key'));
      await _flushMicrotasks();

      await fixture.cache.invalidate('key').runFuture();
      final currentWaiter = caller.fork(fixture.cache.get('key'));
      await _flushMicrotasks();
      gates[1].complete(2);
      expect((await currentWaiter.join() as Succeeded<int, String>).value, 2);
      gates[0].complete(1);

      expect((await oldWaiter.join() as Succeeded<int, String>).value, 1);
      expect(await fixture.cache.get('key').runFuture(), 2);
      expect(lookups, 2);
    });

    test('should keep sharing the current lookup after an older lookup finishes', () async {
      final gates = [Completer<int>(), Completer<int>()];
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.tryFuture<int, String>(
          () => gates[lookups++].future,
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final oldWaiter = caller.fork(fixture.cache.get('key'));
      await _flushMicrotasks();
      await fixture.cache.invalidate('key').runFuture();
      final currentWaiter = caller.fork(fixture.cache.get('key'));
      await _flushMicrotasks();

      gates[0].complete(1);
      expect((await oldWaiter.join() as Succeeded<int, String>).value, 1);
      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
      final joinedWaiter = caller.fork(fixture.cache.get('key'));
      await _flushMicrotasks();
      expect(lookups, 2);

      gates[1].complete(2);
      expect((await currentWaiter.join() as Succeeded<int, String>).value, 2);
      expect((await joinedWaiter.join() as Succeeded<int, String>).value, 2);
      expect(await fixture.cache.get('key').runFuture(), 2);
    });

    test('should invalidate ready and pending generations together', () async {
      final pending = Completer<int>();
      final lookups = <String, int>{};
      final fixture = await _CacheFixture.start<int>(
        lookup: (key) => Effect.defer((_) {
          lookups.update(key, (count) => count + 1, ifAbsent: () => 1);
          return key == 'pending'
              ? Effect.tryFuture<int, String>(
                  () => pending.future,
                  onError: (error, _) => '$error',
                )
              : Effect.succeed(key.codeUnitAt(0));
        }),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('ready').runFuture();
      final caller = Runtime();
      addTearDown(caller.close);
      final oldPending = caller.fork(fixture.cache.get('pending'));
      await _flushMicrotasks();

      await fixture.cache.invalidateAll().runFuture();
      expect(fixture.cache.size, 0);
      expect(await fixture.cache.get('ready').runFuture(), 'ready'.codeUnitAt(0));
      pending.complete(7);

      expect((await oldPending.join() as Succeeded<int, String>).value, 7);
      expect(await fixture.cache.getOption('pending').runFuture(), isA<None>());
      expect(lookups, {'ready': 2, 'pending': 1});
    });

    test('should apply invalidateWhere only to ready unexpired entries', () async {
      final clock = FakeClock();
      final pending = Completer<int>();
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.byValue(
          (_, value) => Duration(seconds: value == 3 ? 1 : 10),
        ),
        lookup: (key) => key == 'pending'
            ? Effect.tryFuture<int, String>(
                () => pending.future,
                onError: (error, _) => '$error',
              )
            : Effect.succeed(int.parse(key)),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('1').runFuture();
      await fixture.cache.get('2').runFuture();
      await fixture.cache.get('3').runFuture();
      final caller = Runtime();
      addTearDown(caller.close);
      caller.fork(fixture.cache.get('pending'));
      await _flushMicrotasks();
      clock.advanceMonotonic(const Duration(seconds: 1));
      final inspected = <(String, int)>[];

      await fixture.cache.invalidateWhere((key, value) {
        inspected.add((key, value));
        return value.isEven;
      }).runFuture();

      expect(inspected, [('1', 1), ('2', 2)]);
      expect(await fixture.cache.containsKey('1').runFuture(), isTrue);
      expect(await fixture.cache.containsKey('2').runFuture(), isFalse);
      expect(await fixture.cache.containsKey('3').runFuture(), isFalse);
      expect(await fixture.cache.containsKey('pending').runFuture(), isFalse);
    });

    test('should protect a queued invalidated generation before it starts', () async {
      final activeGate = Completer<int>();
      final oldGate = Completer<int>();
      final currentGate = Completer<int>();
      var keyLookups = 0;
      final started = <String>[];
      final fixture = await _CacheFixture.start<int>(
        concurrency: 1,
        lookup: (key) => Effect.tryFuture<int, String>(
          () {
            started.add(key);
            if (key == 'active') return activeGate.future;
            keyLookups += 1;
            return keyLookups == 1 ? oldGate.future : currentGate.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final active = caller.fork(fixture.cache.get('active'));
      final oldWaiter = caller.fork(fixture.cache.get('key'));
      await _flushMicrotasks();
      await fixture.cache.invalidate('key').runFuture();
      final currentWaiter = caller.fork(fixture.cache.get('key'));

      activeGate.complete(0);
      await active.join();
      await _flushMicrotasks();
      expect(started, ['active', 'key']);
      oldGate.complete(1);
      expect((await oldWaiter.join() as Succeeded<int, String>).value, 1);
      await _flushMicrotasks();
      expect(started, ['active', 'key', 'key']);
      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
      currentGate.complete(2);

      expect((await currentWaiter.join() as Succeeded<int, String>).value, 2);
      expect(await fixture.cache.get('key').runFuture(), 2);
    });

    test('should reject mutation after scope closure', () async {
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.succeed(1),
      );
      await fixture.close();

      final exits = await Future.wait([
        fixture.cache.set('key', 1).runFutureExit(),
        fixture.cache.invalidate('key').runFutureExit(),
        fixture.cache.invalidateAll().runFutureExit(),
        fixture.cache.invalidateWhere((_, _) => true).runFutureExit(),
      ]);

      for (final exit in exits) {
        expect((exit as Failed<void, Never>).cause, isA<Defect<Never>>());
      }
    });

    test('should apply capacity without disposing values supplied through set', () async {
      final first = _BorrowedValue();
      final second = _BorrowedValue();
      final fixture = await _CacheFixture.start<_BorrowedValue>(
        capacity: 1,
        lookup: (_) => Effect.succeed(_BorrowedValue()),
      );
      addTearDown(fixture.close);

      await fixture.cache.set('first', first).runFuture();
      await fixture.cache.set('second', second).runFuture();

      expect(fixture.cache.keys, ['second']);
      expect(first.closed, isFalse);
      expect(second.closed, isFalse);
    });

    test('should share refresh while keeping an unexpired value readable', () async {
      final refreshStarted = Completer<void>();
      final refreshGate = Completer<int>();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.defer((_) {
          lookups += 1;
          if (lookups == 1) return Effect.succeed<int, String>(1);
          return Effect.tryFuture<int, String>(
            () {
              refreshStarted.complete();
              return refreshGate.future;
            },
            onError: (error, _) => '$error',
          );
        }),
      );
      addTearDown(fixture.close);
      expect(await fixture.cache.get('key').runFuture(), 1);
      final caller = Runtime();
      addTearDown(caller.close);
      final first = caller.fork(fixture.cache.refresh('key'));
      final second = caller.fork(fixture.cache.refresh('key'));
      await refreshStarted.future;

      expect(await fixture.cache.get('key').runFuture(), 1);
      final ready = await fixture.cache.getOption('key').runFuture();
      expect((ready as Some<int>).value, 1);
      expect(await fixture.cache.containsKey('key').runFuture(), isTrue);
      expect(fixture.cache.size, 1);
      expect(fixture.cache.keys, ['key']);
      expect(fixture.cache.values, [1]);
      expect(fixture.cache.entries.single.value, 1);
      final cancelled = await first.interrupt('caller stopped');
      refreshGate.complete(2);

      expect((cancelled as Failed<int, String>).cause, isA<Interrupted<String>>());
      expect((await second.join() as Succeeded<int, String>).value, 2);
      expect(await fixture.cache.get('key').runFuture(), 2);
      expect(lookups, 2);
    });

    test('should preserve the prior value and deadline when refresh fails', () async {
      final clock = FakeClock();
      final refreshStarted = Completer<void>();
      final refreshGate = Completer<int>();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.fixed(const Duration(seconds: 5)),
        lookup: (_) => Effect.defer((_) {
          lookups += 1;
          if (lookups == 1) return Effect.succeed<int, String>(1);
          return Effect.tryFuture<int, String>(
            () {
              refreshStarted.complete();
              return refreshGate.future;
            },
            onError: (_, _) => 'refresh failed',
          );
        }),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('key').runFuture();
      clock.advanceMonotonic(const Duration(seconds: 2));
      final caller = Runtime();
      addTearDown(caller.close);
      final refreshing = caller.fork(fixture.cache.refresh('key'));
      await refreshStarted.future;

      expect(await fixture.cache.get('key').runFuture(), 1);
      clock.advanceMonotonic(const Duration(seconds: 3));
      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
      refreshGate.completeError(StateError('unavailable'));

      expect(await refreshing.join(), isA<Failed<int, String>>());
      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
    });

    test('should begin a fresh expiry period after successful refresh', () async {
      final clock = FakeClock();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        ownerClock: clock,
        expiry: CacheExpiry.fixed(const Duration(seconds: 5)),
        lookup: (_) => Effect.sync((_) => ++lookups),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('key').runFuture();
      clock.advanceMonotonic(const Duration(seconds: 4));

      expect(await fixture.cache.refresh('key').runFuture(), 2);
      clock.advanceMonotonic(const Duration(seconds: 4));
      final ready = await fixture.cache.getOption('key').runFuture();
      expect((ready as Some<int>).value, 2);
      clock.advanceMonotonic(const Duration(seconds: 1));
      expect(await fixture.cache.getOption('key').runFuture(), isA<None>());
    });

    test('should not let refresh overwrite an intervening set', () async {
      final refreshStarted = Completer<void>();
      final refreshGate = Completer<int>();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.defer((_) {
          lookups += 1;
          if (lookups == 1) return Effect.succeed<int, String>(1);
          return Effect.tryFuture<int, String>(
            () {
              refreshStarted.complete();
              return refreshGate.future;
            },
            onError: (error, _) => '$error',
          );
        }),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('key').runFuture();
      final caller = Runtime();
      addTearDown(caller.close);
      final refreshing = caller.fork(fixture.cache.refresh('key'));
      await refreshStarted.future;

      await fixture.cache.set('key', 9).runFuture();
      refreshGate.complete(2);

      expect((await refreshing.join() as Succeeded<int, String>).value, 2);
      expect(await fixture.cache.get('key').runFuture(), 9);
    });

    test('should join a current miss when refreshing an absent key', () async {
      final started = Completer<void>();
      final gate = Completer<int>();
      var lookups = 0;
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.tryFuture<int, String>(
          () {
            lookups += 1;
            started.complete();
            return gate.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      addTearDown(fixture.close);
      final caller = Runtime();
      addTearDown(caller.close);
      final get = caller.fork(fixture.cache.get('key'));
      await started.future;
      final refresh = caller.fork(fixture.cache.refresh('key'));
      gate.complete(4);

      expect((await get.join() as Succeeded<int, String>).value, 4);
      expect((await refresh.join() as Succeeded<int, String>).value, 4);
      expect(lookups, 1);
    });

    test('should interrupt refresh when its owning scope closes', () async {
      final refreshStarted = Completer<void>();
      final refreshGate = Completer<int>();
      var lookups = 0;
      var cancelled = false;
      final fixture = await _CacheFixture.start<int>(
        lookup: (_) => Effect.defer((_) {
          lookups += 1;
          if (lookups == 1) return Effect.succeed<int, String>(1);
          return Effect.tryFuture<int, String>(
            () {
              refreshStarted.complete();
              return refreshGate.future;
            },
            onError: (error, _) => '$error',
            onCancel: () => cancelled = true,
          );
        }),
      );
      await fixture.cache.get('key').runFuture();
      final caller = Runtime();
      addTearDown(caller.close);
      final refreshing = caller.fork(fixture.cache.refresh('key'));
      await refreshStarted.future;

      await fixture.close();

      expect(cancelled, isTrue);
      expect((await refreshing.join() as Failed<int, String>).cause, isA<Interrupted<String>>());
    });

    test('should apply concurrency and LRU rules to refresh', () async {
      final firstRefresh = Completer<int>();
      final secondRefresh = Completer<int>();
      final lookups = <String, int>{};
      final startedRefreshes = <String>[];
      final fixture = await _CacheFixture.start<int>(
        capacity: 2,
        concurrency: 1,
        lookup: (key) => Effect.defer((_) {
          final count = lookups.update(key, (value) => value + 1, ifAbsent: () => 1);
          if (count == 1) return Effect.succeed(key.codeUnitAt(0));
          startedRefreshes.add(key);
          return Effect.tryFuture<int, String>(
            () => key == 'a' ? firstRefresh.future : secondRefresh.future,
            onError: (error, _) => '$error',
          );
        }),
      );
      addTearDown(fixture.close);
      await fixture.cache.get('a').runFuture();
      await fixture.cache.get('b').runFuture();
      final caller = Runtime();
      addTearDown(caller.close);
      final refreshA = caller.fork(fixture.cache.refresh('a'));
      final refreshB = caller.fork(fixture.cache.refresh('b'));
      await _flushMicrotasks();
      expect(startedRefreshes, ['a']);

      firstRefresh.complete(1);
      await refreshA.join();
      await _flushMicrotasks();
      expect(startedRefreshes, ['a', 'b']);
      secondRefresh.complete(2);
      await refreshB.join();
      await fixture.cache.get('c').runFuture();

      expect(fixture.cache.keys, ['b', 'c']);
      expect(lookups, {'a': 2, 'b': 2, 'c': 1});
    });
  });
}

final class _CacheFixture<A> {
  _CacheFixture._(this.cache, this._owner);

  final Cache<String, A, String> cache;
  final Runtime _owner;

  static Future<_CacheFixture<A>> start<A>({
    required Effect<A, String> Function(String key) lookup,
    Context? ownerContext,
    Clock? ownerClock,
    CacheExpiry<String, A>? expiry,
    int capacity = 16,
    int concurrency = 4,
  }) async {
    final owner = Runtime(context: ownerContext, clock: ownerClock);
    final created = Completer<Cache<String, A, String>>();
    final keepScopeOpen = Completer<void>();
    final fiber = owner.fork(
      Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, A, String>(
            capacity: capacity,
            concurrency: concurrency,
            expiry: expiry ?? CacheExpiry.fixed(const Duration(days: 36500)),
            lookup: lookup,
          ),
        );
        created.complete(cache);
        await $(
          Effect.tryFuture<void, Never>(
            () => keepScopeOpen.future,
            onError: Error.throwWithStackTrace,
          ),
        );
      }),
    );
    unawaited(
      fiber.join().then((exit) {
        if (created.isCompleted) return;
        switch (exit) {
          case Succeeded<void, Never>():
            created.completeError(
              StateError('Cache scope ended before acquisition completed.'),
            );
          case Failed<void, Never>(:final cause):
            created.completeError(EffectException(cause));
        }
      }),
    );
    try {
      return _CacheFixture<A>._(await created.future, owner);
    } on Object {
      await owner.close();
      rethrow;
    }
  }

  Future<void> close() => _owner.close();
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

final class _BorrowedValue {
  bool closed = false;

  void close() => closed = true;
}

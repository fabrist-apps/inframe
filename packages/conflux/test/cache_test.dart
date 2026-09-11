import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

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
        lookup: (_) => Effect.defer(() {
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

    test('should interrupt loads and reject use after its scope closes', () async {
      final lookupStarted = Completer<void>();
      final pendingLookup = Completer<int>();
      var lookupCancelled = false;
      final fixture = await _CacheFixture.start(
        lookup: (_) => Effect.tryFuture<int, String>(
          () {
            lookupStarted.complete();
            return pendingLookup.future;
          },
          onError: (error, _) => '$error',
          onCancel: () => lookupCancelled = true,
        ),
      );
      final caller = Runtime();
      addTearDown(caller.close);
      final waiting = caller.fork(fixture.cache.get('key'));
      await lookupStarted.future;

      await fixture.close();
      final waitingExit = await waiting.join();
      final closedExit = await caller.run(fixture.cache.get('other'));

      expect(lookupCancelled, isTrue);
      expect((waitingExit as Failed<int, String>).cause, isA<Interrupted<String>>());
      expect((closedExit as Failed<int, String>).cause, isA<Defect<String>>());
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
        lookup: (key) => Effect.sync(() {
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
        lookup: (key) => Effect.defer(() {
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
      final fixture = await _CacheFixture.start(
        concurrency: 1,
        lookup: (key) => Effect.tryFuture<int, String>(
          () {
            started.add(key);
            if (key == 'a') activeStarted.complete();
            return activeGate.future;
          },
          onError: (error, _) => '$error',
        ),
      );
      final caller = Runtime();
      addTearDown(caller.close);
      final active = caller.fork(fixture.cache.get('a'));
      final queued = caller.fork(fixture.cache.get('b'));
      await activeStarted.future;

      await fixture.close();

      expect(started, ['a']);
      expect((await active.join() as Failed<int, String>).cause, isA<Interrupted<String>>());
      expect((await queued.join() as Failed<int, String>).cause, isA<Interrupted<String>>());
    });

    test('should reject non-positive capacity and concurrency at acquisition', () async {
      for (final configuration in [(capacity: 0, concurrency: 1), (capacity: 1, concurrency: 0)]) {
        final exit = await Cache.make<String, int, String>(
          capacity: configuration.capacity,
          concurrency: configuration.concurrency,
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
        lookup: (key) => Effect.sync(() {
          return values.putIfAbsent(key, _BorrowedValue.new);
        }),
      );
      addTearDown(fixture.close);

      await fixture.cache.get('a').runFuture();
      await fixture.cache.get('b').runFuture();

      expect(values['a']!.closed, isFalse);
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
    int capacity = 16,
    int concurrency = 4,
  }) async {
    final owner = Runtime(context: ownerContext);
    final created = Completer<Cache<String, A, String>>();
    final keepScopeOpen = Completer<void>();
    owner.fork(
      Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, A, String>(
            capacity: capacity,
            concurrency: concurrency,
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
    return _CacheFixture<A>._(await created.future, owner);
  }

  Future<void> close() => _owner.close();
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

final class _BorrowedValue {
  bool closed = false;

  void close() => closed = true;
}

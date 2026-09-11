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
  });
}

final class _CacheFixture {
  _CacheFixture._(this.cache, this._owner);

  final Cache<String, int, String> cache;
  final Runtime _owner;

  static Future<_CacheFixture> start({
    required Effect<int, String> Function(String key) lookup,
    Context? ownerContext,
  }) async {
    final owner = Runtime(context: ownerContext);
    final created = Completer<Cache<String, int, String>>();
    final keepScopeOpen = Completer<void>();
    owner.fork(
      Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, int, String>(
            capacity: 16,
            concurrency: 4,
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
    return _CacheFixture._(await created.future, owner);
  }

  Future<void> close() => _owner.close();
}

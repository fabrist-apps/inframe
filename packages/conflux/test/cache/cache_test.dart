import 'package:conflux/conflux.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  group('Cache', () {
    test('should distinguish missing and nullable values and replace existing values', () async {
      await Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, int?>(
            capacity: 2,
            timeToLive: const Duration(seconds: 10),
          ),
        );
        expect(await $(cache.get('key')), isA<None>());
        final insert = cache.set('key', null);
        expect(await $(cache.get('key')), isA<None>());
        await $(insert);
        expect((await $(cache.get('key')) as Some<int?>).value, isNull);
        await $(cache.set('key', 2));
        expect((await $(cache.get('key')) as Some<int?>).value, 2);
      }).runFuture();
    });

    test('should restart TTL on set and expire exactly at the owner clock deadline', () async {
      final clock = FakeClock();
      await Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, int>(
            capacity: 2,
            timeToLive: const Duration(seconds: 10),
          ),
        );
        await $(cache.set('key', 1));
        clock.advanceMonotonic(const Duration(seconds: 9));
        await cache.set('key', 2).runFuture(clock: FakeClock());
        clock.advanceMonotonic(const Duration(seconds: 9));
        expect((await cache.get('key').runFuture(clock: FakeClock()) as Some<int>).value, 2);
        clock.advanceMonotonic(const Duration(seconds: 1));
        expect(await $(cache.get('key')), isA<None>());
      }).runFuture(clock: clock);
    });

    test('should evict the least recently read or written value', () async {
      await Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, int>(
            capacity: 2,
            timeToLive: const Duration(seconds: 10),
          ),
        );
        await $(cache.set('a', 1));
        await $(cache.set('b', 2));
        await $(cache.get('a'));
        await $(cache.set('c', 3));
        expect(await $(cache.get('b')), isA<None>());
        await $(cache.set('a', 4));
        await $(cache.set('d', 5));
        expect(await $(cache.get('c')), isA<None>());
        expect((await $(cache.get('a')) as Some<int>).value, 4);
      }).runFuture();
    });

    test('should discard expired entries before evicting live entries', () async {
      final clock = FakeClock();
      await Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, int>(
            capacity: 2,
            timeToLive: const Duration(seconds: 10),
          ),
        );
        await $(cache.set('old', 1));
        clock.advanceMonotonic(const Duration(seconds: 5));
        await $(cache.set('live', 2));
        await $(cache.get('old'));
        clock.advanceMonotonic(const Duration(seconds: 5));
        await $(cache.set('new', 3));
        expect((await $(cache.get('live')) as Some<int>).value, 2);
        expect(await $(cache.get('old')), isA<None>());
      }).runFuture(clock: clock);
    });

    test(
      'should invalidate keys and evaluate predicates only for live entries in caller context',
      () async {
        final clock = FakeClock();
        final caller = Context();
        await Effect.build<void, Never>(($) async {
          final cache = await $(
            Cache.make<String, int>(
              capacity: 4,
              timeToLive: const Duration(seconds: 10),
            ),
          );
          await $(cache.set('expired', 0));
          clock.advanceMonotonic(const Duration(seconds: 10));
          await $(cache.set('a', 1));
          await $(cache.set('b', 2));
          final visited = <String>[];
          await cache
              .invalidateWhere((key, value, context) {
                expect(context, same(caller));
                visited.add(key);
                return value == 2;
              })
              .runFuture(context: caller);
          expect(visited, ['a', 'b']);
          expect(await $(cache.get('b')), isA<None>());
          await $(cache.invalidate('a'));
          expect(await $(cache.get('a')), isA<None>());
          await $(cache.set('c', 3));
          await $(cache.invalidateAll());
          expect(await $(cache.get('c')), isA<None>());
        }).runFuture(clock: clock);
      },
    );

    test('should leave matching entries intact when a predicate throws', () async {
      await Effect.build<void, Never>(($) async {
        final cache = await $(
          Cache.make<String, int>(
            capacity: 2,
            timeToLive: const Duration(seconds: 10),
          ),
        );
        await $(cache.set('a', 1));
        await $(cache.set('b', 2));
        final exit = await cache.invalidateWhere((key, _, _) {
          if (key == 'b') throw StateError('predicate');
          return true;
        }).runFutureExit();
        expect(exit, isA<Failed<void, Never>>());
        expect((await $(cache.get('a')) as Some<int>).value, 1);
      }).runFuture();
    });

    test('should retain no values with zero TTL', () async {
      await Effect.build<void, Never>(($) async {
        final cache = await $(Cache.make<String, int>(capacity: 1, timeToLive: Duration.zero));
        await $(cache.set('key', 1));
        expect(await $(cache.get('key')), isA<None>());
      }).runFuture();
    });

    test('should reject invalid configuration during acquisition', () async {
      for (final config in [
        (capacity: 0, ttl: Duration.zero),
        (capacity: 1, ttl: const Duration(microseconds: -1)),
      ]) {
        final exit = await Cache.make<String, int>(
          capacity: config.capacity,
          timeToLive: config.ttl,
        ).runFutureExit();
        expect(
          exit,
          isA<Failed<Cache<String, int>, Never>>().having(
            (failure) => failure.cause,
            'cause',
            isA<Defect<Never>>().having((defect) => defect.error, 'error', isArgumentError),
          ),
        );
      }
    });

    test('should reject every operation after its scope closes', () async {
      final cache = await Cache.make<String, int>(
        capacity: 1,
        timeToLive: const Duration(seconds: 10),
      ).runFuture();
      for (final operation in <Effect<Object?, Never>>[
        cache.get('key'),
        cache.set('key', 1),
        cache.invalidate('key'),
        cache.invalidateAll(),
        cache.invalidateWhere((_, _, _) => true),
      ]) {
        expect(await operation.runFutureExit(), isA<Failed<Object?, Never>>());
      }
    });
  });
}

import 'package:conflux/cache.dart';
import 'package:conflux/effect.dart';
import 'package:test/test.dart';

void main() {
  group('Cache module', () {
    test('should expose the Cache API without the convenience barrel', () {
      final cache = Cache.make<String, int, String>(
        capacity: 4,
        concurrency: 2,
        expiry: CacheExpiry.fixed(const Duration(minutes: 1)),
        lookup: (key) => Effect.succeed(key.length),
      );

      _acceptCacheEffect(cache);
      expect(cache, isA<Effect<Cache<String, int, String>, Never>>());
    });
  });
}

void _acceptCacheEffect(Effect<Cache<String, int, String>, Never> effect) {}

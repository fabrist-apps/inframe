import 'package:test/test.dart';

import 'support/consumer_fixtures.dart';

void main() {
  group('Context extensions', () {
    late ConsumerFixtures fixtures;

    setUpAll(() async {
      fixtures = await ConsumerFixtures.create();
      for (final package in [
        'core_consumer',
        'analytics_consumer',
        'http_consumer',
        'combined_consumer',
      ]) {
        await fixtures.resolve(package);
      }
    });

    test('should hide both features when only the base is imported', () async {
      await fixtures.analyze(
        'core_consumer',
        'absent_features.dart',
        errors: ['UNDEFINED_GETTER', 'UNDEFINED_GETTER'],
      );
    });

    for (final feature in ['analytics', 'http']) {
      final package = '${feature}_consumer';
      final other = feature == 'analytics' ? 'http' : 'analytics';

      test('should expose $feature through its package entrypoint', () async {
        await fixtures.analyze(package, 'valid.dart');
        await fixtures.run(package, 'valid.dart');
      });

      test('should hide $other from a $feature-only import', () async {
        await fixtures.analyze(package, 'absent_$other.dart', errors: ['UNDEFINED_GETTER']);
      });

      test('should fail on access when $feature setup is missing', () async {
        await fixtures.analyze(package, 'missing_binding.dart');
        await fixtures.run(package, 'missing_binding.dart');
      });
    }

    test('should compose both features across independent requests', () async {
      await fixtures.analyze('combined_consumer', 'valid.dart');
      await fixtures.run('combined_consumer', 'valid.dart');
    });
  });
}

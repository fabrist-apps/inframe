import 'package:test/test.dart';

import 'support/consumer_fixtures.dart';

void main() {
  group('Effect consumer', () {
    late ConsumerFixtures fixtures;

    setUpAll(() async {
      fixtures = await ConsumerFixtures.create();
      await fixtures.resolve('effect_consumer');
    });

    test('should infer builder values through the public entrypoint', () async {
      await fixtures.analyze('effect_consumer', 'valid.dart');
      await fixtures.run('effect_consumer', 'valid.dart');
    });

    test('should reject an incompatible builder error type', () async {
      await fixtures.analyzeFails(
        'effect_consumer',
        'invalid_bind.dart',
        containing: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
      );
    });

    test('should reject an incompatible Schedule error type', () async {
      await fixtures.analyzeFails(
        'effect_consumer',
        'invalid_schedule.dart',
        containing: 'RETURN_OF_INVALID_TYPE',
      );
    });
  });
}

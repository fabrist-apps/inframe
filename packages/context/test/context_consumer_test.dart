import 'package:test/test.dart';

import 'support/consumer_fixtures.dart';

void main() {
  group('Context consumer', () {
    late ConsumerFixtures fixtures;

    setUpAll(() async {
      fixtures = await ConsumerFixtures.create();
      await fixtures.resolve('core_consumer');
    });

    test('should expose the typed API through the public entrypoint', () async {
      await fixtures.analyze('core_consumer', 'valid.dart');
      await fixtures.run('core_consumer', 'valid.dart');
    });

    for (final file in ['null_binding', 'incompatible_binding']) {
      test('should reject $file during analysis', () async {
        await fixtures.analyze(
          'core_consumer',
          '$file.dart',
          errors: ['ARGUMENT_TYPE_NOT_ASSIGNABLE'],
        );
      });
    }

    test('should prevent direct binding construction by a consumer', () async {
      await fixtures.analyze(
        'core_consumer',
        'direct_constructor.dart',
        errors: ['NEW_WITH_UNDEFINED_CONSTRUCTOR_DEFAULT'],
      );
    });
  });
}

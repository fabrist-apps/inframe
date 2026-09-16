import 'package:test/test.dart';

import '../support/consumer_fixtures.dart';

void main() {
  group('Val consumer', () {
    late ConsumerFixtures fixtures;
    setUpAll(() async {
      fixtures = await ConsumerFixtures.create();
      await fixtures.resolve('val_consumer');
    });
    test('should retain declared output types through public composition', () async {
      await fixtures.analyze('val_consumer', 'valid.dart');
      await fixtures.run('val_consumer', 'valid.dart');
    });
    test('should retain conversion output types and reject string methods afterward', () async {
      await fixtures.analyze('val_consumer', 'moment.dart');
      await fixtures.run('val_consumer', 'moment.dart');
      await fixtures.analyzeFails(
        'val_consumer',
        'invalid_moment_string.dart',
        containing: 'UNDEFINED_METHOD',
      );
    });
    test('should serialize issues without consumer generation', () async {
      await fixtures.analyze('val_consumer', 'issues.dart');
      await fixtures.run('val_consumer', 'issues.dart');
    });
    test('should expose the full catalog with exact output types and sound widening', () async {
      await fixtures.analyze('val_consumer', 'catalog.dart');
      await fixtures.run('val_consumer', 'catalog.dart');
      await fixtures.analyzeFails(
        'val_consumer',
        'invalid_numeric_bound.dart',
        containing: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
      );
    });
    test('should reject non-string codes statically', () async {
      await fixtures.analyzeFails(
        'val_consumer',
        'invalid_code.dart',
        containing: 'ARGUMENT_TYPE_NOT_ASSIGNABLE',
      );
    });
  });
}

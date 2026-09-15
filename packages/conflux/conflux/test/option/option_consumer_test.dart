import 'package:test/test.dart';

import '../support/consumer_fixtures.dart';

void main() {
  group('Option consumer', () {
    late ConsumerFixtures fixtures;

    setUpAll(() async {
      fixtures = await ConsumerFixtures.create();
      await fixtures.resolve('value_consumer');
    });

    test('should expose typed composition through the public entrypoint', () async {
      await fixtures.analyze('value_consumer', 'valid.dart');
      await fixtures.run('value_consumer', 'valid.dart');
    });
  });
}

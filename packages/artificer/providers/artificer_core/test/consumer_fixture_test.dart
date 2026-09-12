import 'package:test/test.dart';

import 'support/consumer_fixtures.dart';

void main() {
  group('Public provider consumer', () {
    late ConsumerFixtures fixtures;

    setUpAll(() async {
      fixtures = await ConsumerFixtures.create();
      await fixtures.resolve('provider_consumer');
    });

    test('should implement model contracts using public imports only', () async {
      await fixtures.analyze('provider_consumer', 'valid.dart');
      await fixtures.run('provider_consumer', 'valid.dart');
    });
  });
}

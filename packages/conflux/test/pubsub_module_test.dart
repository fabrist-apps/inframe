import 'package:conflux/effect.dart';
import 'package:conflux/pubsub.dart';
import 'package:test/test.dart';

void main() {
  group('PubSub module', () {
    test('should expose the PubSub API without the convenience barrel', () async {
      final result = await Effect.build<int, Never>(($) async {
        final pubsub = await $(PubSub.bounded<int>(1));
        final subscription = await $(pubsub.subscribe());
        await $(pubsub.publish(42));
        return $(subscription.take());
      }).runFuture();

      expect(result, 42);
    });
  });
}

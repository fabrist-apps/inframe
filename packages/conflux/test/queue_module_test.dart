import 'package:conflux/effect.dart';
import 'package:conflux/queue.dart';
import 'package:test/test.dart';

void main() {
  group('Queue module', () {
    test('should expose the Queue API without the convenience barrel', () async {
      final result = await Effect.build<int, Never>(($) async {
        final queue = await $(Queue.bounded<int>(1));
        await $(queue.offer(42));
        return $(queue.take());
      }).runFuture();

      expect(result, 42);
    });
  });
}

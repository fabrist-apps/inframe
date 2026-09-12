import 'package:test/test.dart';

/// Waits for observable asynchronous work with a bounded failure message.
Future<void> waitForCondition(bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed >= const Duration(seconds: 1)) {
      fail('Condition was not met before timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Gives already-scheduled asynchronous result handling an event-loop turn.
Future<void> settleAsync() => Future<void>.delayed(const Duration(milliseconds: 4));

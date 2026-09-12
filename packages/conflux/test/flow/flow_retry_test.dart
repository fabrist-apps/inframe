import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/schedule.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  group('Flow retry', () {
    test('should resubscribe and permit values from failed attempts to repeat', () async {
      var attempts = 0;
      final flow = Flow.defer<int, String>((_) {
        attempts += 1;
        final tail = attempts < 3
            ? Flow.fail<int, String>('failure $attempts')
            : Flow.succeed<int, String>(2);
        return Flow.succeed<int, String>(1).concat(tail);
      }).retry(Schedule.recurs(2));

      expect(await flow.runCollect().runFuture(), [1, 1, 1, 2]);
      expect(attempts, 3);
    });

    test('should create a fresh bounded driver for every consumption', () async {
      var attempts = 0;
      final flow = Flow.defer<int, String>((_) {
        attempts += 1;
        return Flow.fail('failure $attempts');
      }).retry(Schedule.recurs(1));

      final first = await flow.runCollect().runFutureExit();
      final second = await flow.runCollect().runFutureExit();

      expect(first, isA<Failed<List<int>, String>>());
      expect(second, isA<Failed<List<int>, String>>());
      expect(attempts, 4);
      expect(
        ((first as Failed<List<int>, String>).cause as Expected<String>).error,
        'failure 2',
      );
      expect(
        ((second as Failed<List<int>, String>).cause as Expected<String>).error,
        'failure 4',
      );
    });

    test('should step with the primary expected error and preserve stop failure', () async {
      final inputs = <String>[];
      var attempts = 0;
      final policy = Schedule<String, int, String>.fromDriver(
        () => ScheduleDriver((input) {
          inputs.add(input);
          return Effect.succeed(
            attempts == 1 ? const ScheduleContinue(0, Duration.zero) : const ScheduleStop(1),
          );
        }),
      );
      final stopped = Sequential<String>([
        const Expected('final first'),
        const Expected('final second'),
      ]);
      final flow = Flow.defer<int, String>((_) {
        attempts += 1;
        final cause = attempts == 1
            ? Sequential<String>([
                const Expected('first'),
                const Expected('second'),
              ])
            : stopped;
        return Effect.failCause<int, String>(cause).asFlow();
      }).retry(policy);

      final exit = await flow.runCollect().runFutureExit();

      expect((exit as Failed<List<int>, String>).cause, same(stopped));
      expect(inputs, ['first', 'final first']);
      expect(attempts, 2);
    });

    test('should preserve a fatal cause without consulting the policy', () async {
      var steps = 0;
      final policy = Schedule<String, int, String>.fromDriver(
        () => ScheduleDriver((_) {
          steps += 1;
          return Effect.succeed(const ScheduleContinue(0, Duration.zero));
        }),
      );
      final cause = Sequential<String>([
        const Expected('failed'),
        Defect(StateError('defect'), StackTrace.current),
      ]);

      final exit = await Effect.failCause<int, String>(cause)
          .asFlow()
          .retry(policy)
          .runCollect()
          .runFutureExit();

      expect((exit as Failed<List<int>, String>).cause, same(cause));
      expect(steps, 0);
    });

    test('should expose mapped schedule failure without retrying that step', () async {
      var attempts = 0;
      final policy = Schedule<String, int, int>.fromDriver(
        () => ScheduleDriver((_) => Effect.fail(7)),
      ).mapError((error, _) => 'policy $error');
      final flow = Flow.defer<int, String>((_) {
        attempts += 1;
        return Flow.fail('source failed');
      }).retry(policy);

      final exit = await flow.runCollect().runFutureExit();

      expect(
        ((exit as Failed<List<int>, String>).cause as Expected<String>).error,
        'policy 7',
      );
      expect(attempts, 1);
    });

    test('should finish cleanup before waiting and opening the next attempt', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      var attempts = 0;
      final flow = Flow.defer<int, String>((_) {
        attempts += 1;
        if (attempts > 1) return Flow.succeed(42);
        return Flow.fail<int, String>('again').ensuring(
          Effect.tryFuture<void, Never>(
            (_) {
              cleanupStarted.complete();
              return releaseCleanup.future;
            },
            onError: (error, stackTrace, _) => _impossibleFutureError(error, stackTrace),
          ),
        );
      }).retry(Schedule.spaced(const Duration(seconds: 5)));
      final fiber = runtime.fork(flow.runCollect());

      await cleanupStarted.future;
      expect(clock.activeWaits, 0);
      expect(attempts, 1);
      releaseCleanup.complete();
      await _waitUntil(() => clock.activeWaits == 1);
      expect(attempts, 1);

      clock.advanceMonotonic(const Duration(seconds: 5));
      final exit = await fiber.join();
      expect((exit as Succeeded<List<int>, String>).value, [42]);
      expect(attempts, 2);
    });

    test('should cancel a retry wait without opening another source', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      var attempts = 0;
      final flow = Flow.defer<int, String>((_) {
        attempts += 1;
        return Flow.fail('again');
      }).retry(Schedule.spaced(const Duration(seconds: 5)));
      final fiber = runtime.fork(flow.runCollect());
      await _waitUntil(() => clock.activeWaits == 1);

      final exit = await fiber.interrupt('stop');
      clock.advanceMonotonic(const Duration(seconds: 5));
      await _flushMicrotasks();

      expect((exit as Failed<List<int>, String>).cause, isA<Interrupted<String>>());
      expect(clock.activeWaits, 0);
      expect(attempts, 1);
    });
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true.');
}

Future<void> _flushMicrotasks() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

Never _impossibleFutureError(Object error, StackTrace stackTrace) {
  throw StateError('Unexpected future failure: $error');
}

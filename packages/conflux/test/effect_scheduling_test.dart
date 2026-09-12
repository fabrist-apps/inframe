import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

import 'support/fake_clock.dart';

void main() {
  group('Effect scheduling', () {
    test('should retry at most three times before succeeding', () async {
      var attempts = 0;
      final effect = Effect.defer<int, String>((_) {
        attempts += 1;
        return attempts < 4 ? Effect.fail('failure $attempts') : Effect.succeed(42);
      }).retry(Schedule.recurs(3));

      final exit = await effect.runFutureExit();

      expect((exit as Succeeded<int, String>).value, 42);
      expect(attempts, 4);
    });

    test('should stop retrying after the configured recurrences', () async {
      var attempts = 0;
      final effect = Effect.defer<int, String>((_) {
        attempts += 1;
        return Effect.fail('failure $attempts');
      }).retry(Schedule.recurs(3));

      final cause = (await effect.runFutureExit() as Failed<int, String>).cause;

      expect((cause as Expected<String>).error, 'failure 4');
      expect(attempts, 4);
    });

    test('should repeat immediately with a fresh driver on each run', () async {
      var executions = 0;
      final effect = Effect.sync((_) => ++executions).repeat(
        Schedule.recurs(3),
      );

      final exit = await effect.runFutureExit();

      expect((exit as Succeeded<int, Never>).value, 3);
      expect(executions, 4);
      expect(await effect.runFuture(), 3);
      expect(executions, 8);
    });

    test('should schedule only after the first continuing decision', () async {
      var executions = 0;
      final effect = Effect.sync<int>((_) => ++executions).schedule(
        Schedule.recurs(3),
      );

      final exit = await effect.runFutureExit();

      expect((exit as Succeeded<int, Never>).value, 3);
      expect(executions, 3);
    });

    test('should distinguish zero repeat recurrences from zero scheduled runs', () async {
      var repeated = 0;
      var scheduled = 0;

      final repeatOutput = await Effect.sync((_) => ++repeated)
          .repeat(Schedule.recurs(0))
          .runFuture();
      final scheduleOutput = await Effect.sync((_) => ++scheduled)
          .schedule(Schedule.recurs(0))
          .runFuture();

      expect(repeatOutput, 0);
      expect(repeated, 1);
      expect(scheduleOutput, 0);
      expect(scheduled, 0);
    });

    test('should preserve None and nullable Some schedule inputs', () async {
      final inputs = <Option<int?>>[];
      var decisions = 0;
      final policy = Schedule<Option<int?>, int, Never>.fromDriver(
        () => ScheduleDriver((input) {
          inputs.add(input);
          decisions += 1;
          return Effect.succeed(
            decisions <= 2 ? ScheduleContinue(decisions, Duration.zero) : ScheduleStop(decisions),
          );
        }),
      );

      final exit = await Effect.succeed<int?, Never>(null).schedule(policy).runFutureExit();

      expect((exit as Succeeded<int, Never>).value, 3);
      expect(inputs, [isA<None>(), isA<Some<int?>>(), isA<Some<int?>>()]);
      expect((inputs[1] as Some<int?>).value, isNull);
    });

    test('should pass only the primary expected error to retry policy', () async {
      final inputs = <String>[];
      var attempts = 0;
      final policy = Schedule<String, int, String>.fromDriver(
        () => ScheduleDriver((input) {
          inputs.add(input);
          return Effect.succeed(
            const ScheduleContinue(0, Duration.zero),
          );
        }),
      );
      final effect = Effect.defer<int, String>((_) {
        attempts += 1;
        return attempts == 1
            ? Effect.failCause(
                Sequential([const Expected('first'), const Expected('second')]),
              )
            : Effect.succeed(42);
      }).retry(policy);

      final exit = await effect.runFutureExit();

      expect(exit, isA<Succeeded<int, String>>());
      expect(inputs, ['first']);
    });

    test('should not retry a cause containing a defect', () async {
      var policySteps = 0;
      final policy = Schedule<String, int, String>.fromDriver(
        () => ScheduleDriver((_) {
          policySteps += 1;
          return Effect.succeed(
            const ScheduleContinue(0, Duration.zero),
          );
        }),
      );
      final cause = Sequential<String>([
        const Expected('failed'),
        Defect(StateError('defect'), StackTrace.current),
      ]);

      final exit = await Effect.failCause<int, String>(cause).retry(policy).runFutureExit();

      expect((exit as Failed<int, String>).cause, same(cause));
      expect(policySteps, 0);
    });

    test('should stop on a failed schedule step', () async {
      var attempts = 0;
      final policy = Schedule<String, int, String>.fromDriver(
        () => ScheduleDriver((_) => Effect.fail('policy failed')),
      );
      final effect = Effect.defer<int, String>((_) {
        attempts += 1;
        return Effect.fail('operation failed');
      }).retry(policy);

      final cause = (await effect.runFutureExit() as Failed<int, String>).cause;

      expect((cause as Expected<String>).error, 'policy failed');
      expect(attempts, 1);
    });

    test('should map policy errors without changing decisions', () async {
      final failed = Schedule<int, int, String>.fromDriver(
        () => ScheduleDriver((_) => Effect.fail('cron failed')),
      ).mapError((error) => 'domain: $error');
      final defective = Schedule<int, int, String>.fromDriver(
        () => ScheduleDriver((_) => Effect.fail('cron failed')),
      ).mapError<int>((_) => throw StateError('mapper'));

      final failedExit = await failed.driver().step(0).runFutureExit();
      final defectiveExit = await defective.driver().step(0).runFutureExit();

      expect(
        ((failedExit as Failed<ScheduleDecision<int>, String>).cause as Expected<String>).error,
        'domain: cron failed',
      );
      expect(
        (defectiveExit as Failed<ScheduleDecision<int>, int>).cause,
        isA<Defect<int>>(),
      );
    });

    test('should space retries from operation completion', () async {
      final clock = FakeClock();
      var attempts = 0;
      final fiber = Runtime(clock: clock).fork(
        Effect.defer<int, String>((_) {
          attempts += 1;
          return attempts == 1 ? Effect.fail('again') : Effect.succeed(42);
        }).retry(Schedule.spaced(const Duration(seconds: 5))),
      );
      await Future<void>.delayed(Duration.zero);

      expect(attempts, 1);
      expect(clock.activeWaits, 1);
      clock.advance(const Duration(seconds: 5));
      final exit = await fiber.join();

      expect(exit, isA<Succeeded<int, String>>());
      expect(attempts, 2);
    });

    test('should cancel a pending schedule wait without another attempt', () async {
      final clock = FakeClock();
      var attempts = 0;
      final fiber = Runtime(clock: clock).fork(
        Effect.defer<int, String>((_) {
          attempts += 1;
          return Effect.fail('again');
        }).retry(Schedule.spaced(const Duration(seconds: 5))),
      );
      await Future<void>.delayed(Duration.zero);
      expect(clock.activeWaits, 1);

      final exit = await fiber.interrupt('stop');
      clock.advance(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      expect((exit as Failed<int, String>).cause, isA<Interrupted<String>>());
      expect(attempts, 1);
      expect(clock.activeWaits, 0);
    });

    test('should yield during a long immediate repetition', () async {
      var yielded = false;
      Future<void>.delayed(Duration.zero, () => yielded = true);

      final output = await Effect.succeed<int, Never>(1).repeat(Schedule.recurs(2000)).runFuture();

      expect(output, 2000);
      expect(yielded, isTrue);
    });

    test('should await failed schedule cleanup before returning', () async {
      var cleaned = false;
      final policy = Schedule<String, int, String>.fromDriver(
        () => ScheduleDriver(
          (_) => Effect.build<ScheduleDecision<int>, String>(($) {
            $.addFinalizer(Effect.sync((_) => cleaned = true));
            return $.sync(const Failure('policy failed'));
          }),
        ),
      );

      final exit = await Effect.fail<int, String>('operation failed').retry(policy).runFutureExit();

      expect(exit, isA<Failed<int, String>>());
      expect(cleaned, isTrue);
    });

    test('should reject negative recurrence and spacing configuration', () {
      expect(() => Schedule.recurs<Object?>(-1), throwsArgumentError);
      expect(
        () => Schedule.spaced<Object?>(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
    });
  });
}

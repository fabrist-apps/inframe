import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

import 'support/fake_clock.dart';

void main() {
  group('Schedule composition', () {
    test('should distinguish anchored fixed delays from spaced delays', () async {
      final clock = FakeClock();
      final fixed = Schedule.fixed<String>(
        const Duration(seconds: 10),
      ).driver();
      final spaced = Schedule.spaced<String>(
        const Duration(seconds: 10),
      ).driver();

      final first = await fixed.step('first').runFuture(clock: clock);
      await spaced.step('first').runFuture(clock: clock);
      clock.advance(const Duration(seconds: 25));
      final second = await fixed.step('second').runFuture(clock: clock);
      final spacedSecond = await spaced.step('second').runFuture(clock: clock);
      clock.advance(const Duration(seconds: 5));
      final third = await fixed.step('third').runFuture(clock: clock);

      expect((first as ScheduleContinue<int>).delay, const Duration(seconds: 10));
      expect((second as ScheduleContinue<int>).delay, const Duration(seconds: 5));
      expect(
        (spacedSecond as ScheduleContinue<int>).delay,
        const Duration(seconds: 10),
      );
      expect((third as ScheduleContinue<int>).delay, const Duration(seconds: 10));
    });

    test('should double exponential delays by default', () async {
      final driver = Schedule.exponential<Object?>(
        const Duration(milliseconds: 100),
      ).driver();

      final first = await driver.step(null).runFuture();
      final second = await driver.step(null).runFuture();
      final third = await driver.step(null).runFuture();

      expect((first as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 100));
      expect((second as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 200));
      expect((third as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 400));
    });

    test('should modify exponential delay without adding an automatic cap', () async {
      final uncapped = Schedule.exponential<Object?>(
        const Duration(milliseconds: 100),
      ).driver();
      final capped =
          Schedule.exponential<Object?>(
                const Duration(milliseconds: 100),
              )
              .modifyDelay(
                (delay) => delay > const Duration(milliseconds: 150)
                    ? const Duration(milliseconds: 150)
                    : delay,
              )
              .driver();

      await uncapped.step(null).runFuture();
      final uncappedSecond = await uncapped.step(null).runFuture();
      await capped.step(null).runFuture();
      final cappedSecond = await capped.step(null).runFuture();

      expect(
        (uncappedSecond as ScheduleContinue<Duration>).delay,
        const Duration(milliseconds: 200),
      );
      expect((cappedSecond as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 150));

      final tripled = Schedule.exponential<Object?>(
        const Duration(milliseconds: 100),
        factor: 3,
      ).driver();
      await tripled.step(null).runFuture();
      final tripledSecond = await tripled.step(null).runFuture();
      expect(
        (tripledSecond as ScheduleContinue<Duration>).delay,
        const Duration(milliseconds: 300),
      );
    });

    test('should jitter delays through injected uniform values', () async {
      final values = [0.0, 0.999999].iterator;
      final driver =
          Schedule.spaced<Object?>(
                const Duration(seconds: 1),
              )
              .jittered(
                random: () {
                  values.moveNext();
                  return values.current;
                },
              )
              .driver();

      final low = await driver.step(null).runFuture();
      final high = await driver.step(null).runFuture();

      expect((low as ScheduleContinue<int>).delay, const Duration(milliseconds: 800));
      expect((high as ScheduleContinue<int>).delay.inMicroseconds, 1199999);
    });

    test('should stop when the next start exceeds a monotonic budget', () async {
      final clock = FakeClock();
      final driver = Schedule.spaced<Object?>(
        const Duration(seconds: 10),
      ).within(const Duration(seconds: 25)).driver();

      final first = await driver.step(null).runFuture(clock: clock);
      clock.advance(const Duration(seconds: 10));
      final second = await driver.step(null).runFuture(clock: clock);
      clock
        ..adjustWall(const Duration(days: 1))
        ..advanceMonotonic(const Duration(seconds: 10));
      final third = await driver.step(null).runFuture(clock: clock);

      expect(first, isA<ScheduleContinue<int>>());
      expect(second, isA<ScheduleContinue<int>>());
      expect(third, isA<ScheduleStop<int>>());
    });

    test('should let started work finish before enforcing its budget', () async {
      final clock = FakeClock();
      var executions = 0;
      final program =
          Effect.sync(() {
            executions += 1;
            if (executions == 2) {
              clock.advance(const Duration(seconds: 30));
            }
          }).repeat<int>(
            Schedule.spaced<Null>(
              const Duration(seconds: 10),
            ).within(const Duration(seconds: 25)),
          );

      final fiber = Runtime(clock: clock).fork(program);
      await Future<void>.delayed(Duration.zero);
      clock.advance(const Duration(seconds: 10));
      final exit = await fiber.join();

      expect(exit, isA<Succeeded<int, Never>>());
      expect(executions, 2);
    });

    test('should include effectful driver work in its elapsed budget', () async {
      final clock = FakeClock();
      final driver =
          Schedule.spaced<Object?>(
                const Duration(seconds: 10),
              )
              .tap((_) {
                return Effect.sync(() {
                  clock.advanceMonotonic(const Duration(seconds: 20));
                });
              })
              .within(const Duration(seconds: 25))
              .driver();

      final decision = await driver.step(null).runFuture(clock: clock);

      expect(decision, isA<ScheduleStop<int>>());
    });

    test('should combine both-alive policies with the later delay', () async {
      final driver = Schedule.max(
        Schedule.spaced<Object?>(const Duration(seconds: 2)),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).driver();

      final decision = await driver.step(null).runFuture();
      final continued = decision as ScheduleContinue<({int left, int right})>;

      expect(continued.output, (left: 0, right: 0));
      expect(continued.delay, const Duration(seconds: 5));
    });

    test('should stop max when either branch stops', () async {
      final driver = Schedule.max(
        Schedule.recurs<Object?>(0),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).driver();

      final decision = await driver.step(null).runFuture();

      expect(decision, isA<ScheduleStop<({int left, int right})>>());
    });

    test('should continue min with optional active outputs', () async {
      final driver = Schedule.min(
        Schedule.recurs<Object?>(0),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).driver();

      final decision = await driver.step(null).runFuture();
      final continued = decision as ScheduleContinue<({Option<int> left, Option<int> right})>;

      expect(continued.output.left, isA<None>());
      expect((continued.output.right as Some<int>).value, 0);
      expect(continued.delay, const Duration(seconds: 5));
    });

    test('should choose the earlier delay while both min branches continue', () async {
      final driver = Schedule.min(
        Schedule.spaced<Object?>(const Duration(seconds: 2)),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).driver();

      final decision = await driver.step(null).runFuture();

      expect(
        (decision as ScheduleContinue<({Option<int> left, Option<int> right})>).delay,
        const Duration(seconds: 2),
      );
    });

    test('should stop min after both branches stop', () async {
      final driver = Schedule.min(
        Schedule.recurs<Object?>(0),
        Schedule.recurs<Object?>(0),
      ).driver();

      final decision = await driver.step(null).runFuture();

      expect(
        decision,
        isA<ScheduleStop<({Option<int> left, Option<int> right})>>(),
      );
    });

    test('should stop before another execution when input is rejected', () async {
      final driver = Schedule.spaced<int>(
        const Duration(seconds: 1),
      ).whileInput((input) => input > 0).driver();

      final accepted = await driver.step(1).runFuture();
      final rejected = await driver.step(0).runFuture();

      expect(accepted, isA<ScheduleContinue<int>>());
      expect(rejected, isA<ScheduleStop<int>>());
    });

    test('should start concat second policy with fresh state', () async {
      final driver = Schedule.recurs<Object?>(1).concat(Schedule.recurs<Object?>(1)).driver();

      final first = await driver.step(null).runFuture();
      final second = await driver.step(null).runFuture();
      final third = await driver.step(null).runFuture();

      expect((first as ScheduleContinue<int>).output, 0);
      expect((second as ScheduleContinue<int>).output, 0);
      expect((third as ScheduleStop<int>).output, 1);
    });

    test('should tap only continuing decisions', () async {
      final observed = <int>[];
      final driver = Schedule.recurs<Object?>(1)
          .tap(
            (decision) => Effect.sync(() => observed.add(decision.output)),
          )
          .driver();

      await driver.step(null).runFuture();
      await driver.step(null).runFuture();

      expect(observed, [0]);
    });

    test('should retain a tap defect', () async {
      final driver = Schedule.recurs<Object?>(1)
          .tap(
            (_) => Effect.sync(() => throw StateError('tap failed')),
          )
          .driver();

      final exit = await driver.step(null).runFutureExit();

      expect((exit as Failed<ScheduleDecision<int>, Never>).cause, isA<Defect<Never>>());
    });

    test('should retain tap interruption', () async {
      final driver = Schedule.recurs<Object?>(1)
          .tap(
            (_) => Effect.failCause<void, Never>(const Interrupted('hook')),
          )
          .driver();

      final exit = await driver.step(null).runFutureExit();

      expect(
        (exit as Failed<ScheduleDecision<int>, Never>).cause,
        isA<Interrupted<Never>>(),
      );
    });

    test('should reject invalid policy configuration', () async {
      expect(
        () => Schedule.fixed<Object?>(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => Schedule.exponential<Object?>(Duration.zero, factor: 0),
        throwsArgumentError,
      );
      expect(
        () => Schedule.spaced<Object?>(
          const Duration(seconds: 1),
        ).within(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      final invalidJitter = Schedule.spaced<Object?>(
        const Duration(seconds: 1),
      ).jittered(random: () => 1).driver();
      final exit = await invalidJitter.step(null).runFutureExit();
      expect(
        (exit as Failed<ScheduleDecision<int>, Never>).cause,
        isA<Defect<Never>>(),
      );
    });
  });
}

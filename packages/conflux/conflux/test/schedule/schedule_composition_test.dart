import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  group('Schedule composition', () {
    test('should distinguish anchored fixed delays from spaced delays', () async {
      final clock = FakeClock();
      final fixed = Schedule.fixed<String>(
        const Duration(seconds: 10),
      ).createStep();
      final spaced = Schedule.spaced<String>(
        const Duration(seconds: 10),
      ).createStep();

      final first = await fixed('first').runFuture(clock: clock);
      await spaced('first').runFuture(clock: clock);
      clock.advance(const Duration(seconds: 25));
      final second = await fixed('second').runFuture(clock: clock);
      final spacedSecond = await spaced('second').runFuture(clock: clock);
      clock.advance(const Duration(seconds: 5));
      final third = await fixed('third').runFuture(clock: clock);

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
      ).createStep();

      final first = await driver(null).runFuture();
      final second = await driver(null).runFuture();
      final third = await driver(null).runFuture();

      expect((first as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 100));
      expect((second as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 200));
      expect((third as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 400));
    });

    test('should modify exponential delay without adding an automatic cap', () async {
      final uncapped = Schedule.exponential<Object?>(
        const Duration(milliseconds: 100),
      ).createStep();
      final capped =
          Schedule.exponential<Object?>(
                const Duration(milliseconds: 100),
              )
              .modifyDelay(
                (delay, _) => delay > const Duration(milliseconds: 150)
                    ? const Duration(milliseconds: 150)
                    : delay,
              )
              .createStep();

      await uncapped(null).runFuture();
      final uncappedSecond = await uncapped(null).runFuture();
      await capped(null).runFuture();
      final cappedSecond = await capped(null).runFuture();

      expect(
        (uncappedSecond as ScheduleContinue<Duration>).delay,
        const Duration(milliseconds: 200),
      );
      expect((cappedSecond as ScheduleContinue<Duration>).delay, const Duration(milliseconds: 150));

      final tripled = Schedule.exponential<Object?>(
        const Duration(milliseconds: 100),
        factor: 3,
      ).createStep();
      await tripled(null).runFuture();
      final tripledSecond = await tripled(null).runFuture();
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
              .createStep();

      final low = await driver(null).runFuture();
      final high = await driver(null).runFuture();

      expect((low as ScheduleContinue<int>).delay, const Duration(milliseconds: 800));
      expect((high as ScheduleContinue<int>).delay.inMicroseconds, 1199999);
    });

    test('should combine both-alive policies with the later delay', () async {
      final driver = Schedule.max(
        Schedule.spaced<Object?>(const Duration(seconds: 2)),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).createStep();

      final decision = await driver(null).runFuture();
      final continued = decision as ScheduleContinue<({int left, int right})>;

      expect(continued.output, (left: 0, right: 0));
      expect(continued.delay, const Duration(seconds: 5));
    });

    test('should stop max when either branch stops', () async {
      final driver = Schedule.max(
        Schedule.recurs<Object?>(0),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).createStep();

      final decision = await driver(null).runFuture();

      expect(decision, isA<ScheduleStop<({int left, int right})>>());
    });

    test('should continue min with optional active outputs', () async {
      final driver = Schedule.min(
        Schedule.recurs<Object?>(0),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).createStep();

      final decision = await driver(null).runFuture();
      final continued = decision as ScheduleContinue<({Option<int> left, Option<int> right})>;

      expect(continued.output.left, isA<None>());
      expect((continued.output.right as Some<int>).value, 0);
      expect(continued.delay, const Duration(seconds: 5));
    });

    test('should choose the earlier delay while both min branches continue', () async {
      final driver = Schedule.min(
        Schedule.spaced<Object?>(const Duration(seconds: 2)),
        Schedule.spaced<Object?>(const Duration(seconds: 5)),
      ).createStep();

      final decision = await driver(null).runFuture();

      expect(
        (decision as ScheduleContinue<({Option<int> left, Option<int> right})>).delay,
        const Duration(seconds: 2),
      );
    });

    test('should stop min after both branches stop', () async {
      final driver = Schedule.min(
        Schedule.recurs<Object?>(0),
        Schedule.recurs<Object?>(0),
      ).createStep();

      final decision = await driver(null).runFuture();

      expect(
        decision,
        isA<ScheduleStop<({Option<int> left, Option<int> right})>>(),
      );
    });
  });
}

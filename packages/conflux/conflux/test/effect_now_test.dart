import 'package:conflux/conflux.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'support/fake_clock.dart';
import 'support/moments.dart';

void main() {
  group('Effect.now', () {
    test('should defer each reading and use the current execution Clock', () async {
      final firstClock = CountingClock(utcMoment(2026));
      final secondClock = CountingClock(utcMoment(2027));
      final first = Runtime(clock: firstClock);
      final second = Runtime(clock: secondClock);
      addTearDown(first.close);
      addTearDown(second.close);
      final current = Effect.now();
      expect(firstClock.reads, 0);
      expect(secondClock.reads, 0);
      expect((await first.run(current) as Succeeded<UtcMoment, Never>).value, utcMoment(2026));
      firstClock.instant = utcMoment(2026, 2);
      expect((await first.run(current) as Succeeded<UtcMoment, Never>).value, utcMoment(2026, 2));
      expect((await second.run(current) as Succeeded<UtcMoment, Never>).value, utcMoment(2027));
      expect(firstClock.reads, 2);
      expect(secondClock.reads, 1);
      final zone = TimeZone.fixed(const Duration(hours: 8))
          .getOrThrowWith((e) => StateError(e.message));
      // The note's public composition shape retains both typed channels.
      // ignore: omit_local_variable_types
      final Effect<Result<ZonedMoment, MomentError>, Never> zoned = current.map(
        (value, context) => value.setZone(zone),
      );
      final result =
          (await first.run(zoned) as Succeeded<Result<ZonedMoment, MomentError>, Never>).value;
      expect(
        (result as Success<ZonedMoment, MomentError>).value.formatIsoOffset(),
        '2026-02-01T08:00:00.000000+08:00',
      );
    });

    test(
      'should read system UTC and execute ordinary effects without IANA initialization',
      () async {
        expect(tz.timeZoneDatabase.isInitialized, isFalse);
        final clock = SystemClock();
        final before = clock.wallTime();
        final runtime = Runtime(clock: clock);
        addTearDown(runtime.close);
        final now = (await runtime.run(Effect.now()) as Succeeded<UtcMoment, Never>).value;
        final after = clock.wallTime();
        expect(now.isBetween(before, after), isTrue);
        expect(now.isUtc, isTrue);
        expect(tz.timeZoneDatabase.isInitialized, isFalse);
        expect(await runtime.run(Effect.succeed<int, Never>(42)), isA<Succeeded<int, Never>>());
      },
    );

    test('should preserve independent wall and monotonic fake-clock advancement', () async {
      final clock = FakeClock(wallTime: utcMoment(2026));
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      clock.adjustWall(const Duration(days: -1));
      expect(clock.wallTime(), utcMoment(2025, 12, 31));
      expect(clock.monotonic(), Duration.zero);
      final wait = clock.sleep(const Duration(seconds: 1));
      clock.advanceMonotonic(const Duration(seconds: 1));
      await wait.completed;
      expect(clock.wallTime(), utcMoment(2025, 12, 31));
      expect(clock.monotonic(), const Duration(seconds: 1));
      expect(
        (await runtime.run(Effect.now()) as Succeeded<UtcMoment, Never>).value,
        clock.wallTime(),
      );
      expect(clock.activeWaits, 0);
    });

    test('should keep unexpected clock failures in the defect channel', () async {
      final clock = CountingClock(utcMoment(2026))..fail = true;
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final result = await runtime.run(Effect.now());
      expect((result as Failed<UtcMoment, Never>).cause, isA<Defect<Never>>());
    });
  });
}

final class CountingClock implements Clock {
  CountingClock(this.instant);
  UtcMoment instant;
  int reads = 0;
  bool fail = false;

  @override
  UtcMoment wallTime() {
    reads++;
    if (fail) throw StateError('Invalid platform reading');
    return instant;
  }

  @override
  Duration monotonic() => Duration.zero;
  @override
  CancellableWait sleep(Duration duration) => throw StateError('No wait expected');
}

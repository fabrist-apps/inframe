import 'package:conflux/cron.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'support/moments.dart';

void main() {
  tz_data.initializeTimeZones();
  final utc = tz.UTC;
  final newYork = tz.getLocation('America/New_York');

  Cron parse(String expression, tz.Location location) {
    return (Cron.parse(expression, location) as Success<Cron, CronError>).value;
  }

  group('Cron occurrences', () {
    test('should retain the configured named zone for every reference representation', () {
      final cron = parse('0 9 * * *', newYork);
      final reference = utcMoment(2026, 1, 18);
      final fixed = reference
          .setZone(TimeZone.fixed(const Duration(hours: 8)).getOrNull()!)
          .getOrNull()!;
      final named = reference
          .setZone(TimeZone.fromLocation(tz.getLocation('Europe/Paris')))
          .getOrNull()!;
      for (final input in <Moment>[reference, fixed, named]) {
        final next = cron.next(input).getOrNull()!;
        final previous = cron.previous(input).getOrNull()!;
        expect(next.toUtc(), utcMoment(2026, 1, 18, 14));
        expect(previous.toUtc(), utcMoment(2026, 1, 17, 14));
        expect(identical((next.zone as NamedTimeZone).location, newYork), isTrue);
        expect(next.zone, TimeZone.fromLocation(newYork));
        expect(previous.zone, next.zone);
        expect(next.parts.hour, 9);
        expect(cron.matches(next), isTrue);
        expect(cron.matches(next.toUtc()), isTrue);
        expect(
          cron.sequence(input).take(2).map((r) => r.getOrNull()!.zone),
          everyElement(next.zone),
        );
      }
    });

    test('should map local range failures into CronError without hiding defects', () {
      final west = tz.Location('test/west', [], [], [
        const tz.TimeZone(Duration(hours: -1), isDst: false, abbreviation: 'W'),
      ]);
      final cron = parse('* * * * * *', west);
      final first = utcMoment(1);
      expect(cron.matches(first), isFalse);
      expect(
        cron.next(first),
        isA<Failure<ZonedMoment, CronError>>().having(
          (r) => r.error.message,
          'message',
          contains('1–9999'),
        ),
      );
      final broken = tz.Location('test/broken', [253402214400000], [5], [
        const tz.TimeZone(Duration.zero, isDst: false, abbreviation: 'B'),
      ]);
      expect(() => parse('* * * * * *', broken).next(utcMoment(9999, 12, 31)), throwsRangeError);
    });

    test('should find occurrences when a rollback crosses midnight', () {
      final gooseBay = tz.getLocation('America/Goose_Bay');
      final lateEvening = parse('0 30 23 * * *', gooseBay);
      final midnight = parse('0 0 0 * * *', gooseBay);

      // At 03:01 UTC, October 25 00:01 rolls back to October 24 23:01.
      expect(
        lateEvening.next(utcMoment(1987, 10, 25, 3)).getOrNull()?.toUtc(),
        utcMoment(1987, 10, 25, 3, 30),
      );
      expect(
        midnight.previous(utcMoment(1987, 10, 25, 3, 30)).getOrNull()?.toUtc(),
        utcMoment(1987, 10, 25, 3),
      );
    });

    test('should order overlapping calendar dates by their actual instants', () {
      final cron = parse('0 0,30 0,23 * * *', tz.getLocation('America/Goose_Bay'));

      expect(
        cron.next(utcMoment(1987, 10, 25, 2, 59)).getOrNull()?.toUtc(),
        utcMoment(1987, 10, 25, 3),
      );
      expect(
        cron.previous(utcMoment(1987, 10, 25, 4, 1)).getOrNull()?.toUtc(),
        utcMoment(1987, 10, 25, 4),
      );
    });

    test('should find strict next and previous occurrences', () {
      final cron = parse('0 */15 * * * *', utc);
      final input = utcMoment(2026, 9, 11, 10, 30);

      expect(
        (cron.next(input) as Success<ZonedMoment, CronError>).value.toUtc(),
        utcMoment(2026, 9, 11, 10, 45),
      );
      expect(
        (cron.previous(input) as Success<ZonedMoment, CronError>).value.toUtc(),
        utcMoment(2026, 9, 11, 10, 15),
      );
    });

    test('should cross month year and leap-day boundaries', () {
      final newYear = parse('0 0 0 1 jan *', utc);
      final leapDay = parse('0 0 0 29 feb *', utc);

      expect(
        (newYear.next(utcMoment(2026, 12, 31)) as Success<ZonedMoment, CronError>).value.toUtc(),
        utcMoment(2027),
      );
      expect(
        (newYear.previous(utcMoment(2027)) as Success<ZonedMoment, CronError>).value.toUtc(),
        utcMoment(2026),
      );
      expect(
        (leapDay.next(utcMoment(2025)) as Success<ZonedMoment, CronError>).value.toUtc(),
        utcMoment(2028, 2, 29),
      );
    });

    test('should skip a nonexistent local time in both directions', () {
      final cron = parse('0 30 2 * * *', newYork);
      final beforeGap = utcMoment(2024, 3, 9, 8);
      final afterGap = utcMoment(2024, 3, 11, 6);

      expect(
        (cron.next(beforeGap) as Success<ZonedMoment, CronError>).value.toUtc(),
        utcMoment(2024, 3, 11, 6, 30),
      );
      expect(
        (cron.previous(afterGap) as Success<ZonedMoment, CronError>).value.toUtc(),
        utcMoment(2024, 3, 9, 7, 30),
      );
    });

    test('should return both instants of a repeated local time', () {
      final cron = parse('0 30 1 * * *', newYork);
      final first = utcMoment(2024, 11, 3, 5, 30);
      final second = utcMoment(2024, 11, 3, 6, 30);

      expect(
        (cron.next(utcMoment(2024, 11, 3, 4)) as Success<ZonedMoment, CronError>).value.toUtc(),
        first,
      );
      expect((cron.next(first) as Success<ZonedMoment, CronError>).value.toUtc(), second);
      expect(
        (cron.previous(utcMoment(2024, 11, 3, 7)) as Success<ZonedMoment, CronError>).value.toUtc(),
        second,
      );
      expect((cron.previous(second) as Success<ZonedMoment, CronError>).value.toUtc(), first);
    });

    test('should return typed search failures at budget and date limits', () {
      final impossible = parse('0 0 0 31 feb *', utc);
      final everySecond = parse('* * * * * *', utc);

      expect(impossible.next(utcMoment(2026)), isA<Failure<ZonedMoment, CronError>>());
      expect(impossible.previous(utcMoment(2026)), isA<Failure<ZonedMoment, CronError>>());
      expect(
        everySecond.next(utcMoment(9999, 12, 31, 23, 59, 59)),
        isA<Failure<ZonedMoment, CronError>>(),
      );
      expect(
        everySecond.previous(utcMoment(1)),
        isA<Failure<ZonedMoment, CronError>>(),
      );
    });

    test('should lazily sequence successes and stop after one failure', () {
      final everyMinute = parse('0 * * * * *', utc);
      final successes = everyMinute.sequence(utcMoment(2026)).take(2).toList();
      final failure = parse('0 0 0 31 feb *', utc).sequence(utcMoment(2026)).toList();

      expect(
        successes.map((result) => (result as Success<ZonedMoment, CronError>).value.toUtc()),
        [utcMoment(2026, 1, 1, 0, 1), utcMoment(2026, 1, 1, 0, 2)],
      );
      expect(failure, hasLength(1));
      expect(failure.single, isA<Failure<ZonedMoment, CronError>>());
    });
  });
}

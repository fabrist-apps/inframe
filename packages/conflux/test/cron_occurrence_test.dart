import 'package:conflux/cron.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tz_data.initializeTimeZones();
  final utc = tz.UTC;
  final newYork = tz.getLocation('America/New_York');

  Cron parse(String expression, tz.Location location) {
    return (Cron.parse(expression, location) as Success<Cron, CronError>).value;
  }

  group('Cron occurrences', () {
    test('should find strict next and previous occurrences', () {
      final cron = parse('0 */15 * * * *', utc);
      final input = DateTime.utc(2026, 9, 11, 10, 30);

      expect(
        (cron.next(input) as Success<DateTime, CronError>).value,
        DateTime.utc(2026, 9, 11, 10, 45),
      );
      expect(
        (cron.previous(input) as Success<DateTime, CronError>).value,
        DateTime.utc(2026, 9, 11, 10, 15),
      );
    });

    test('should cross month year and leap-day boundaries', () {
      final newYear = parse('0 0 0 1 jan *', utc);
      final leapDay = parse('0 0 0 29 feb *', utc);

      expect(
        (newYear.next(DateTime.utc(2026, 12, 31)) as Success<DateTime, CronError>).value,
        DateTime.utc(2027),
      );
      expect(
        (newYear.previous(DateTime.utc(2027)) as Success<DateTime, CronError>).value,
        DateTime.utc(2026),
      );
      expect(
        (leapDay.next(DateTime.utc(2025)) as Success<DateTime, CronError>).value,
        DateTime.utc(2028, 2, 29),
      );
    });

    test('should skip a nonexistent local time in both directions', () {
      final cron = parse('0 30 2 * * *', newYork);
      final beforeGap = DateTime.utc(2024, 3, 9, 8);
      final afterGap = DateTime.utc(2024, 3, 11, 6);

      expect(
        (cron.next(beforeGap) as Success<DateTime, CronError>).value,
        DateTime.utc(2024, 3, 11, 6, 30),
      );
      expect(
        (cron.previous(afterGap) as Success<DateTime, CronError>).value,
        DateTime.utc(2024, 3, 9, 7, 30),
      );
    });

    test('should return both instants of a repeated local time', () {
      final cron = parse('0 30 1 * * *', newYork);
      final first = DateTime.utc(2024, 11, 3, 5, 30);
      final second = DateTime.utc(2024, 11, 3, 6, 30);

      expect(
        (cron.next(DateTime.utc(2024, 11, 3, 4)) as Success<DateTime, CronError>).value,
        first,
      );
      expect((cron.next(first) as Success<DateTime, CronError>).value, second);
      expect(
        (cron.previous(DateTime.utc(2024, 11, 3, 7)) as Success<DateTime, CronError>).value,
        second,
      );
      expect((cron.previous(second) as Success<DateTime, CronError>).value, first);
    });

    test('should return typed search failures at budget and date limits', () {
      final impossible = parse('0 0 0 31 feb *', utc);
      final everySecond = parse('* * * * * *', utc);

      expect(impossible.next(DateTime.utc(2026)), isA<Failure<DateTime, CronError>>());
      expect(impossible.previous(DateTime.utc(2026)), isA<Failure<DateTime, CronError>>());
      expect(
        everySecond.next(DateTime.utc(9999, 12, 31, 23, 59, 59)),
        isA<Failure<DateTime, CronError>>(),
      );
      expect(
        everySecond.previous(DateTime.utc(1)),
        isA<Failure<DateTime, CronError>>(),
      );
    });

    test('should lazily sequence successes and stop after one failure', () {
      final everyMinute = parse('0 * * * * *', utc);
      final successes = everyMinute.sequence(DateTime.utc(2026)).take(2).toList();
      final failure = parse('0 0 0 31 feb *', utc).sequence(DateTime.utc(2026)).toList();

      expect(
        successes.map((result) => (result as Success<DateTime, CronError>).value),
        [DateTime.utc(2026, 1, 1, 0, 1), DateTime.utc(2026, 1, 1, 0, 2)],
      );
      expect(failure, hasLength(1));
      expect(failure.single, isA<Failure<DateTime, CronError>>());
    });
  });
}

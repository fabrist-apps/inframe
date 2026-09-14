import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest_all.dart' as data;

T value<T>(Result<T, MomentError> r) => r.getOrThrowWith((e) => StateError(e.message));
Moment parse(String s) => value(Moment.parse(s));
const Disambiguation reject = Disambiguation.reject;

void main() {
  group('Moment calendar', () {
    setUpAll(data.initializeTimeZones);
    test('should clamp once for combined month changes', () {
      final january = parse('2025-01-31T10:20:30.123456Z');
      expect(
        value(january.addCalendar(months: 2, disambiguation: reject)).formatIso(),
        '2025-03-31T10:20:30.123456Z',
      );
      final february = value(january.addCalendar(months: 1, disambiguation: reject));
      expect(
        value(february.addCalendar(months: 1, disambiguation: reject)).formatIso(),
        '2025-03-28T10:20:30.123456Z',
      );
    });

    test('should combine signed units and subtract with the same ordering', () {
      final start = parse('2024-02-29T12:00:00.123456+08:00');
      final shifted = value(
        start.addCalendar(years: 1, months: -1, weeks: 1, days: -2, disambiguation: reject),
      );
      expect(shifted.formatIsoOffset(), '2025-02-03T12:00:00.123456+08:00');
      expect(
        value(
          start.subtractCalendar(years: -1, months: 1, weeks: -1, days: 2, disambiguation: reject),
        ),
        shifted,
      );
      final january = parse('2025-01-31T00:00:00Z');
      final february = value(january.addCalendar(months: 1, disambiguation: reject));
      expect(
        value(february.subtractCalendar(months: 1, disambiguation: reject)).formatIsoDate(),
        '2025-01-28',
      );
      expect(value(start.addCalendar(years: 1, disambiguation: reject)).parts.day, 28);
      expect(
        value(
          start.addCalendar(
            years: 1000000000,
            months: -12000000000,
            weeks: 1000000000,
            days: -7000000000,
            disambiguation: reject,
          ),
        ),
        start,
      );
    });

    test('should resolve only the final local fields after calendar changes', () {
      final zone = value(TimeZone.named('America/New_York'));
      final start = value(parse('2025-02-09T07:30:00Z').setZone(zone));
      // The intermediate March 9 02:30 is a gap, but March 10 is valid.
      expect(
        value(start.addCalendar(months: 1, days: 1, disambiguation: reject)).formatIsoOffset(),
        '2025-03-10T02:30:00.000000-04:00',
      );
      for (final policy in Disambiguation.values) {
        final result = start.addCalendar(months: 1, disambiguation: policy);
        if (policy == reject) {
          expect(
            result,
            isA<Failure<Moment, MomentError>>().having(
              (r) => r.error.kind,
              'kind',
              MomentErrorKind.nonexistentLocalTime,
            ),
          );
        } else {
          expect(value(result).parts.hour, policy == Disambiguation.earlier ? 1 : 3);
        }
      }
      final overlapStart = value(parse('2025-11-01T05:30:00Z').setZone(zone));
      expect(
        value(overlapStart.addCalendar(days: 1, disambiguation: Disambiguation.earlier))
            .formatIso(),
        '2025-11-02T05:30:00.000000Z',
      );
      expect(
        value(overlapStart.addCalendar(days: 1, disambiguation: Disambiguation.later)).formatIso(),
        '2025-11-02T06:30:00.000000Z',
      );
      expect(overlapStart.addCalendar(days: 1, disambiguation: reject).isFailure, isTrue);
    });

    test('should distinguish calendar days from 24 elapsed hours across DST', () {
      final start = value(
        parse('2025-03-09T05:00:00Z').setZone(value(TimeZone.named('America/New_York'))),
      );
      final calendar = value(start.addCalendar(days: 1, disambiguation: reject));
      expect(calendar.formatIsoOffset(), '2025-03-10T00:00:00.000000-04:00');
      expect(value(calendar.difference(start)), const Duration(hours: 23));
      expect(value(start.addDuration(const Duration(days: 1))).parts.hour, 1);
      expect((calendar as ZonedMoment).zone, start.zone);
    });

    test('should resolve every period using local fields and microsecond precision', () {
      final start = parse('2024-02-15T12:34:56.123456+08:00');
      final expected = {
        MomentUnit.year: ('2024-01-01T00:00:00.000000+08:00', '2024-12-31T23:59:59.999999+08:00'),
        MomentUnit.month: ('2024-02-01T00:00:00.000000+08:00', '2024-02-29T23:59:59.999999+08:00'),
        MomentUnit.week: ('2024-02-12T00:00:00.000000+08:00', '2024-02-18T23:59:59.999999+08:00'),
        MomentUnit.day: ('2024-02-15T00:00:00.000000+08:00', '2024-02-15T23:59:59.999999+08:00'),
        MomentUnit.hour: ('2024-02-15T12:00:00.000000+08:00', '2024-02-15T12:59:59.999999+08:00'),
        MomentUnit.minute: ('2024-02-15T12:34:00.000000+08:00', '2024-02-15T12:34:59.999999+08:00'),
        MomentUnit.second: ('2024-02-15T12:34:56.000000+08:00', '2024-02-15T12:34:56.999999+08:00'),
      };
      for (final entry in expected.entries) {
        expect(
          value(start.startOf(entry.key, disambiguation: reject)).formatIsoOffset(),
          entry.value.$1,
        );
        expect(
          value(start.endOf(entry.key, disambiguation: reject)).formatIsoOffset(),
          entry.value.$2,
        );
      }
      final ny = value(
        parse('2025-03-09T16:00:00Z').setZone(value(TimeZone.named('America/New_York'))),
      );
      final beginning = value(ny.startOf(MomentUnit.day, disambiguation: reject));
      final end = value(ny.endOf(MomentUnit.day, disambiguation: reject));
      expect(
        value(end.difference(beginning)),
        const Duration(hours: 22, minutes: 59, seconds: 59, milliseconds: 999, microseconds: 999),
      );
    });

    test('should apply boundary policies even when a gap shift leaves the period', () {
      final zone = value(TimeZone.named('America/Sao_Paulo'));
      final day = value(parse('2018-11-04T12:00:00Z').setZone(zone));
      expect(
        value(day.startOf(MomentUnit.day, disambiguation: Disambiguation.earlier))
            .formatIsoOffset(),
        '2018-11-03T23:00:00.000000-03:00',
      );
      expect(
        value(day.startOf(MomentUnit.day, disambiguation: Disambiguation.later)).formatIsoOffset(),
        '2018-11-04T01:00:00.000000-02:00',
      );
      expect(day.startOf(MomentUnit.day, disambiguation: reject).isFailure, isTrue);
      final overlap = value(
        parse('2025-11-02T06:30:00Z').setZone(value(TimeZone.named('America/New_York'))),
      );
      expect(
        value(overlap.startOf(MomentUnit.hour, disambiguation: Disambiguation.earlier)).formatIso(),
        '2025-11-02T05:00:00.000000Z',
      );
      expect(
        value(overlap.endOf(MomentUnit.hour, disambiguation: Disambiguation.later)).formatIso(),
        '2025-11-02T06:59:59.999999Z',
      );
      expect(overlap.endOf(MomentUnit.hour, disambiguation: reject).isFailure, isTrue);
    });

    test('should query local Gregorian dates and ISO week-years across boundaries', () {
      final cases = [
        ('2021-01-01T00:00:00Z', (year: 2020, week: 53), 1, 5),
        ('2021-01-04T00:00:00Z', (year: 2021, week: 1), 4, 1),
        ('2019-12-30T00:00:00Z', (year: 2020, week: 1), 364, 1),
        ('2024-12-31T00:00:00Z', (year: 2025, week: 1), 366, 2),
      ];
      for (final (text, week, ordinal, weekday) in cases) {
        final moment = parse(text);
        expect(moment.isoWeek, week);
        expect(moment.dayOfYear, ordinal);
        expect(moment.weekday, weekday);
      }
      expect(parse('2000-02-01T00:00:00Z').isLeapYear, isTrue);
      expect(parse('1900-02-01T00:00:00Z').isLeapYear, isFalse);
      expect(parse('2000-02-01T00:00:00Z').daysInMonth, 29);
      expect(parse('1900-02-01T00:00:00Z').daysInMonth, 28);
      expect(parse('2026-10-01T00:00:00Z').quarter, 4);
      final ny = value(
        parse('2025-03-10T04:00:00Z').setZone(value(TimeZone.named('America/New_York'))),
      );
      expect(ny.dayOfYear, 69);
      expect(ny.weekday, 1);
      expect(ny.isoWeek, (year: 2025, week: 11));
    });

    test('should return range failures for calendar and local boundary overflow', () {
      final first = parse('-271821-04-20T00:00:00Z');
      final last = parse('+275760-09-13T00:00:00Z');
      for (final result in [
        first.subtractCalendar(days: 1, disambiguation: reject),
        first.subtractCalendar(months: 1, disambiguation: reject),
        last.addCalendar(years: 1, disambiguation: reject),
        last.addCalendar(weeks: 9223372036854775807, disambiguation: reject),
        last.subtractCalendar(years: -9223372036854775808, disambiguation: reject),
        last.endOf(MomentUnit.week, disambiguation: reject),
        parse('-271821-04-20T08:00:00+08:00').startOf(MomentUnit.day, disambiguation: reject),
      ]) {
        expect(
          result,
          isA<Failure<Moment, MomentError>>().having(
            (r) => r.error.kind,
            'kind',
            MomentErrorKind.outOfRange,
          ),
        );
      }
      expect(value(last.startOf(MomentUnit.day, disambiguation: reject)), last);
      expect(value(first.startOf(MomentUnit.day, disambiguation: reject)), first);
    });
  });
}

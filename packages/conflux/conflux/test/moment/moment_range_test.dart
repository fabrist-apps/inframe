// These boundaries exercise exact signed 64-bit Dart VM integers.
// ignore_for_file: avoid_js_rounded_ints

import 'package:conflux/cron.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

T value<T>(Result<T, MomentError> result) =>
    result.getOrThrowWith((error) => StateError(error.message));

void main() {
  group('Moment native range', () {
    test('should construct years before 1 and after 9999 and preserve native limits', () {
      for (final year in [-10000, -1, 0, 10000]) {
        final native = DateTime.utc(year);
        final moment = value(Moment.fromDateTime(native));
        expect(moment.toDateTimeUtc(), native);
        expect(value(Moment.utc(MomentParts(year: year, month: 1, day: 1))), moment);
      }
      for (final micros in [-8640000000000000000, 8640000000000000000]) {
        final moment = value(Moment.fromEpochMicroseconds(micros));
        expect(moment.toDateTimeUtc().microsecondsSinceEpoch, micros);
      }
    });

    test('should round-trip signed extended years and year zero', () {
      for (final text in [
        '0000-01-01T00:00:00.000001Z',
        '-0001-12-31T23:59:59.123456Z',
        '-010000-01-01T00:00:00.000000Z',
        '+010000-01-01T00:00:00.000000Z',
        '-271821-04-20T00:00:00.000000Z',
        '+275760-09-13T00:00:00.000000Z',
      ]) {
        expect(value(Moment.parse(text)).formatIso(), text);
      }
    });
    test('should return typed differences at both Duration limits without wrapping', () {
      final first = value(Moment.fromEpochMicroseconds(-8640000000000000000));
      final last = value(Moment.fromEpochMicroseconds(8640000000000000000));
      final maxAway = value(Moment.fromEpochMicroseconds(583372036854775807));
      final minAway = value(Moment.fromEpochMicroseconds(583372036854775808));
      expect(value(maxAway.difference(first)).inMicroseconds, 9223372036854775807);
      expect(value(first.difference(minAway)).inMicroseconds, -9223372036854775808);
      for (final result in [
        last.difference(first),
        first.difference(last),
        minAway.difference(first),
      ]) {
        expect(result, isA<Failure<Duration, MomentError>>());
        expect(result.getFailure().getOrNull()!.kind, MomentErrorKind.outOfRange);
      }
      expect(value(first.addDuration(const Duration(microseconds: 9223372036854775807))), maxAway);
      expect(
        value(first.subtractDuration(const Duration(microseconds: -9223372036854775808))),
        minAway,
      );
    });

    test('should reject noncanonical years and partial native boundary dates', () {
      for (final year in ['-0000', '+000001', '-000001', '10000', '+10000']) {
        final result = Moment.parse('$year-01-01T00:00:00Z');
        expect(result.getFailure().getOrNull()!.kind, MomentErrorKind.invalidFormat);
      }
      for (final text in [
        '-271821-04-19T23:59:59.999999Z',
        '+275760-09-13T00:00:00.000001Z',
        '+275760-12-31T00:00:00Z',
      ]) {
        expect(Moment.parse(text).getFailure().getOrNull()!.kind, MomentErrorKind.outOfRange);
      }
      expect(
        Moment.utc(const MomentParts(year: 9223372036854775807, month: 1, day: 1))
            .getFailure()
            .getOrNull()!
            .kind,
        MomentErrorKind.outOfRange,
      );
    });

    test('should preserve extended local years through fixed and named conversions', () {
      final zone = TimeZone.fromLocation(
        tz.Location('test/east', [], [], [
          const tz.TimeZone(Duration(hours: 1), isDst: false, abbreviation: 'E'),
        ]),
      );
      for (final year in ['-010000', '0000', '+010000']) {
        final original = value(Moment.parse('$year-01-01T00:00:00.123456Z'));
        final zoned = value(original.setZone(zone));
        expect(zoned.formatIsoOffset(), '$year-01-01T01:00:00.123456+01:00');
        expect(value(Moment.parse(zoned.formatIsoOffset())).toUtc(), original);
        expect(
          value(Moment.zoned(zoned.parts, zone, disambiguation: Disambiguation.reject)),
          zoned,
        );
      }
    });

    test('should apply Gregorian calendar arithmetic across zero and native boundaries', () {
      final leap = value(Moment.parse('0000-02-29T12:00:00Z'));
      expect(
        value(leap.addCalendar(years: -1, disambiguation: Disambiguation.reject)).formatIsoDate(),
        '-0001-02-28',
      );
      expect(
        value(leap.subtractCalendar(months: 2, disambiguation: Disambiguation.reject))
            .formatIsoDate(),
        '-0001-12-29',
      );
      final last = value(Moment.fromEpochMicroseconds(8640000000000000000));
      expect(
        value(last.addCalendar(months: 1, days: -30, disambiguation: Disambiguation.reject)),
        last,
      );
      expect(
        last
            .addCalendar(years: 9223372036854775807, disambiguation: Disambiguation.reject)
            .getFailure()
            .getOrNull()!
            .kind,
        MomentErrorKind.outOfRange,
      );
      final first = value(Moment.fromEpochMicroseconds(-8640000000000000000));
      for (final moment in [first, last]) {
        final surrogate = value(
          Moment.utc(moment.parts.copyWith(year: 2000 + moment.parts.year % 400)),
        );
        expect(moment.weekday, surrogate.weekday);
        expect(moment.dayOfYear, surrogate.dayOfYear);
        expect(moment.isoWeek.week, surrogate.isoWeek.week);
        expect(
          moment.isoWeek.year - moment.parts.year,
          surrogate.isoWeek.year - surrogate.parts.year,
        );
        expect(
          value(moment.startOf(MomentUnit.day, disambiguation: Disambiguation.reject)),
          moment,
        );
      }
      for (final unit in [MomentUnit.year, MomentUnit.month, MomentUnit.week]) {
        expect(
          first.startOf(unit, disambiguation: Disambiguation.reject).getFailure().getOrNull()!.kind,
          MomentErrorKind.outOfRange,
        );
      }
      for (final unit in MomentUnit.values) {
        expect(
          last.endOf(unit, disambiguation: Disambiguation.reject).getFailure().getOrNull()!.kind,
          MomentErrorKind.outOfRange,
        );
      }
    });

    test('should retain Cron year bounds independently of Moment', () {
      final cron = Cron.parse('* * * * * *', tz.UTC).getOrNull()!;
      for (final year in [-1, 0, 10000, 20000]) {
        final moment = value(Moment.utc(MomentParts(year: year, month: 1, day: 1)));
        expect(cron.matches(moment), isFalse);
        expect(cron.next(moment), isA<Failure<ZonedMoment, CronError>>());
        expect(cron.previous(moment), isA<Failure<ZonedMoment, CronError>>());
      }
    });
  });
}

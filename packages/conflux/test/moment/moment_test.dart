import 'package:conflux/conflux.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

T value<T>(Result<T, MomentError> result) => result.getOrThrowWith((e) => StateError(e.message));
Moment parse(String text) => value(Moment.parse(text));
Matcher fails(MomentErrorKind kind) =>
    isA<Failure<Object?, MomentError>>().having((v) => v.error.kind, 'kind', kind);

void main() {
  group('MomentParts', () {
    test('should retain the first invalid field and its domain diagnostic', () {
      final result = Moment.utc(const MomentParts(year: 2025, month: 2, day: 29, hour: 25));
      expect(
        result,
        isA<Failure<UtcMoment, MomentError>>()
            .having((value) => value.error.field, 'field', 'day')
            .having((value) => value.error.message, 'message', 'day must be 1–28.'),
      );
    });
  });

  group('Moment', () {
    setUp(data.initializeTimeZones);

    test('should preserve signed microseconds through native UTC interop', () {
      for (final micros in [-62135596800000000, -1001, -1, 0, 1, 253402300799999999]) {
        final moment = value(Moment.fromEpochMicroseconds(micros));
        expect(moment.microsecondsSinceEpoch, micros);
        expect(moment.toDateTimeUtc().microsecondsSinceEpoch, micros);
        expect(moment.toDateTimeUtc().isUtc, isTrue);
        expect(value(Moment.fromDateTime(moment.toDateTimeUtc().toLocal())), moment);
      }
      expect(
        value(Moment.fromEpochMicroseconds(-1)).toDateTimeUtc(),
        DateTime.utc(1969, 12, 31, 23, 59, 59, 999, 999),
      );
    });

    test('should parse exact offsets and pad fractional digits without rounding', () {
      for (var digits = 1; digits <= 6; digits++) {
        final fraction = '123456'.substring(0, digits);
        final moment = parse('2026-01-18T10:30:00.$fraction+08:00');
        expect(moment.formatIso(), '2026-01-18T02:30:00.${fraction.padRight(6, '0')}Z');
        expect(moment.offset, const Duration(hours: 8));
        expect(moment.parts.hour, 10);
        expect(moment.partsUtc.hour, 2);
        expect(moment.formatIsoDate(), '2026-01-18');
        expect(moment, parse(moment.formatIsoOffset()));
      }
      expect(parse('2026-01-18T10:30:00Z').formatIso(), '2026-01-18T10:30:00.000000Z');
      expect(parse('2026-01-18T10:30:00-05:17:09').formatIso(), '2026-01-18T15:47:09.000000Z');
      expect(
        parse('2026-01-18T10:30:00+23:59:59').offset,
        const Duration(hours: 23, minutes: 59, seconds: 59),
      );
    });

    test('should reject unsupported syntax and invalid fields', () {
      for (final text in [
        '2026-01-18',
        '2026-01-18T10:30:00',
        '2026/01/18T10:30:00Z',
        '2026-01-18t10:30:00Z',
        '2026-01-18T10:30:00z',
        ' 2026-01-18T10:30:00Z',
        '2026-01-18T10:30:00Z\n',
        '2026-01-18T10:30:00.Z',
        '2026-01-18T10:30:00.1234567Z',
      ]) {
        expect(Moment.parse(text), fails(MomentErrorKind.invalidFormat), reason: text);
      }
      for (final text in [
        '2025-02-29T00:00:00Z',
        '2026-13-01T00:00:00Z',
        '2026-01-00T00:00:00Z',
        '2026-01-18T24:00:00Z',
        '2026-01-18T10:60:00Z',
        '2026-01-18T10:30:60Z',
      ]) {
        expect(Moment.parse(text), fails(MomentErrorKind.invalidField), reason: text);
      }
      for (final suffix in ['+24:00', '-24:00', '+00:60', '+00:00:60']) {
        expect(Moment.parse('2026-01-18T10:30:00$suffix'), fails(MomentErrorKind.invalidOffset));
      }
    });

    test('should validate parts instead of normalizing them', () {
      const parts = MomentParts(year: 2024, month: 2, day: 29);
      expect(value(Moment.utc(parts)).parts, parts);
      expect(parts.copyWith(), parts);
      expect(
        parts.copyWith(hour: 1, minute: 2, second: 3, millisecond: 4, microsecond: 5),
        const MomentParts(
          year: 2024,
          month: 2,
          day: 29,
          hour: 1,
          minute: 2,
          second: 3,
          millisecond: 4,
          microsecond: 5,
        ),
      );
      for (final invalid in [
        parts.copyWith(year: 2025),
        parts.copyWith(month: 0),
        parts.copyWith(day: -1),
        parts.copyWith(hour: -1),
        parts.copyWith(minute: 60),
        parts.copyWith(second: 60),
        parts.copyWith(millisecond: 1000),
        parts.copyWith(microsecond: -1),
      ]) {
        final result = Moment.utc(invalid);
        expect(result, fails(MomentErrorKind.invalidField));
        expect((result as Failure<UtcMoment, MomentError>).error.field, isNotNull);
      }
      expect(Moment.utc(parts.copyWith(year: 275761)), fails(MomentErrorKind.outOfRange));
      expect(parts.hashCode, parts.copyWith().hashCode);
    });

    test('should distinguish representations while comparing by instant', () {
      final utc = parse('2026-01-01T00:00:00Z');
      final zero = parse('2026-01-01T00:00:00-00:00');
      final named = value(utc.setZone(value(TimeZone.named('Etc/UTC'))));
      final alias = value(utc.setZone(value(TimeZone.named('UTC'))));
      expect({utc, zero, named, alias}.length, 4);
      expect(zero, parse('2026-01-01T00:00:00+00:00'));
      expect(zero.hashCode, parse('2026-01-01T00:00:00+00:00').hashCode);
      expect(named, value(utc.setZone(TimeZone.fromLocation(tz.getLocation('Etc/UTC')))));
      expect(utc, isNot(DateTime.utc(2026)));
      expect(zero.formatIsoOffset(), '2026-01-01T00:00:00.000000+00:00');
      for (final other in [zero, named, alias]) {
        expect(utc.compareTo(other), 0);
        expect(utc.isAtSameMomentAs(other), isTrue);
        expect(value(utc.difference(other)), Duration.zero);
        expect(identical(Moment.min(other, utc), other), isTrue);
        expect(identical(Moment.max(other, utc), other), isTrue);
      }
      final later = value(utc.addDuration(const Duration(microseconds: 1)));
      expect(utc.isBefore(later), isTrue);
      expect(later.isAfter(utc), isTrue);
      expect(value(utc.difference(later)), const Duration(microseconds: -1));
      expect(utc.isBetween(utc, later), isTrue);
      expect(later.isBetween(utc, later), isTrue);
      expect(utc.isBetween(later, utc), isFalse);
      expect(Moment.min(later, utc), utc);
      expect(Moment.max(utc, later), later);
      String family(Moment m) => switch (m) {
        UtcMoment() => 'utc',
        ZonedMoment() => 'zoned',
      };
      String zoneFamily(TimeZone z) => switch (z) {
        NamedTimeZone() => 'named',
        FixedTimeZone() => 'fixed',
      };
      expect(family(utc), 'utc');
      expect(family(zero), 'zoned');
      expect(zoneFamily((zero as ZonedMoment).zone), 'fixed');
      expect(zoneFamily(named.zone), 'named');
      final mapped = Moment.parse('2026-01-18T10:30:00+08:00').map((v) => v.toUtc());
      expect(value(mapped).formatIso(), '2026-01-18T02:30:00.000000Z');
    });

    test('should retain location and historical offset seconds across conversion', () {
      final zone = value(TimeZone.named('Europe/Paris'));
      final original = parse('1900-01-01T00:00:00.000001Z');
      final zoned = value(original.setZone(zone));
      expect(zoned.formatIsoOffset(), '1900-01-01T00:09:21.000001+00:09:21');
      expect(zoned.toUtc(), original);
      expect(parse(zoned.formatIsoOffset()).isAtSameMomentAs(zoned), isTrue);
      expect(parse(zoned.formatIsoOffset()), isNot(zoned));
      tz.timeZoneDatabase.clear();
      expect(zoned.formatIsoOffset(), '1900-01-01T00:09:21.000001+00:09:21');
      expect(identical((zoned.zone as NamedTimeZone).location, zone.location), isTrue);
    });

    test('should keep elapsed arithmetic exact across DST and preserve zones', () {
      final start = value(
        parse('2025-03-09T05:00:00.123456Z').setZone(value(TimeZone.named('America/New_York'))),
      );
      final end = value(start.addDuration(const Duration(days: 1)));
      expect(end.formatIsoOffset(), '2025-03-10T01:00:00.123456-04:00');
      expect((end as ZonedMoment).zone, start.zone);
      expect(value(end.difference(start)), const Duration(days: 1));
      expect(value(end.subtractDuration(const Duration(days: 1))), start);
      expect(value(end.addDuration(const Duration(days: -1))), start);
      expect(value(start.subtractDuration(const Duration(days: -1))), end);
    });

    test('should reject UTC and local overflow before integer arithmetic wraps', () {
      final first = parse('-271821-04-20T00:00:00Z');
      final last = parse('+275760-09-13T00:00:00Z');
      expect(
        first.subtractDuration(const Duration(microseconds: 1)),
        fails(MomentErrorKind.outOfRange),
      );
      expect(last.addDuration(const Duration(microseconds: 1)), fails(MomentErrorKind.outOfRange));
      expect(
        last.addDuration(const Duration(microseconds: 9223372036854775807)),
        fails(MomentErrorKind.outOfRange),
      );
      expect(
        last.subtractDuration(const Duration(microseconds: -9223372036854775808)),
        fails(MomentErrorKind.outOfRange),
      );
      expect(Moment.fromEpochMicroseconds(-8640000000000000001), fails(MomentErrorKind.outOfRange));
      expect(Moment.fromEpochMicroseconds(8640000000000000001), fails(MomentErrorKind.outOfRange));
      expect(Moment.parse('-271821-04-20T00:00:00+00:01'), fails(MomentErrorKind.outOfRange));
      expect(Moment.parse('+275760-09-13T00:00:00-00:01'), fails(MomentErrorKind.outOfRange));
      expect(
        first.setZone(value(TimeZone.fixed(const Duration(seconds: -1)))),
        fails(MomentErrorKind.outOfRange),
      );
      expect(
        last.setZone(value(TimeZone.fixed(const Duration(seconds: 1)))),
        fails(MomentErrorKind.outOfRange),
      );
      final localLast = parse('+275760-09-13T00:00:00+01:00');
      expect(
        localLast.addDuration(const Duration(microseconds: 1)),
        fails(MomentErrorKind.outOfRange),
      );
    });
  });
}

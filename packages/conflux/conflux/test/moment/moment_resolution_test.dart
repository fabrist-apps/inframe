import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

T value<T>(Result<T, MomentError> result) => result.getOrThrowWith((e) => StateError(e.message));
void main() {
  group('Moment local resolution', () {
    setUpAll(data.initializeTimeZones);
    test('should apply every policy to overlaps and gaps independently', () {
      final zone = value(TimeZone.named('America/New_York'));
      for (final policy in Disambiguation.values) {
        final overlap = Moment.zoned(
          const MomentParts(
            year: 2025,
            month: 11,
            day: 2,
            hour: 1,
            minute: 30,
            millisecond: 123,
            microsecond: 456,
          ),
          zone,
          disambiguation: policy,
        );
        final gap = Moment.zoned(
          const MomentParts(
            year: 2025,
            month: 3,
            day: 9,
            hour: 2,
            minute: 30,
            millisecond: 123,
            microsecond: 456,
          ),
          zone,
          disambiguation: policy,
        );
        if (policy == Disambiguation.reject) {
          expect(
            overlap,
            isA<Failure<ZonedMoment, MomentError>>().having(
              (r) => r.error.kind,
              'kind',
              MomentErrorKind.ambiguousLocalTime,
            ),
          );
          expect(
            gap,
            isA<Failure<ZonedMoment, MomentError>>().having(
              (r) => r.error.kind,
              'kind',
              MomentErrorKind.nonexistentLocalTime,
            ),
          );
        } else {
          expect(
            value(overlap).formatIso(),
            policy == Disambiguation.later
                ? '2025-11-02T06:30:00.123456Z'
                : '2025-11-02T05:30:00.123456Z',
          );
          expect(
            value(gap).formatIsoOffset(),
            policy == Disambiguation.earlier
                ? '2025-03-09T01:30:00.123456-05:00'
                : '2025-03-09T03:30:00.123456-04:00',
          );
          expect(identical(value(gap).zone, zone), isTrue);
        }
      }
    });

    test('should use the real size of half-hour and whole-day gaps', () {
      final fixtures = [
        (
          id: 'Australia/Lord_Howe',
          parts: const MomentParts(year: 2025, month: 10, day: 5, hour: 2, minute: 15),
          earlier: '2025-10-05T01:45:00.000000+10:30',
          later: '2025-10-05T02:45:00.000000+11:00',
        ),
        (
          id: 'Pacific/Apia',
          parts: const MomentParts(year: 2011, month: 12, day: 30, hour: 12),
          earlier: '2011-12-29T12:00:00.000000-10:00',
          later: '2011-12-31T12:00:00.000000+14:00',
        ),
      ];
      for (final fixture in fixtures) {
        final zone = value(TimeZone.named(fixture.id));
        for (final policy in Disambiguation.values) {
          final result = Moment.zoned(fixture.parts, zone, disambiguation: policy);
          if (policy == Disambiguation.reject) {
            expect(
              result,
              isA<Failure<ZonedMoment, MomentError>>().having(
                (r) => r.error.kind,
                'kind',
                MomentErrorKind.nonexistentLocalTime,
              ),
            );
          } else {
            expect(
              value(result).formatIsoOffset(),
              policy == Disambiguation.earlier ? fixture.earlier : fixture.later,
            );
          }
        }
      }
    });

    test('should resolve half-hour overlaps and exact transition edges', () {
      final zone = value(TimeZone.named('Australia/Lord_Howe'));
      const parts = MomentParts(year: 2025, month: 4, day: 6, hour: 1, minute: 45);
      expect(
        value(Moment.zoned(parts, zone, disambiguation: Disambiguation.earlier)).formatIso(),
        '2025-04-05T14:45:00.000000Z',
      );
      expect(
        value(Moment.zoned(parts, zone, disambiguation: Disambiguation.later)).formatIso(),
        '2025-04-05T15:15:00.000000Z',
      );
      final ny = value(TimeZone.named('America/New_York'));
      expect(
        Moment.zoned(
          const MomentParts(
            year: 2025,
            month: 3,
            day: 9,
            hour: 1,
            minute: 59,
            second: 59,
            millisecond: 999,
            microsecond: 999,
          ),
          ny,
          disambiguation: Disambiguation.reject,
        ).isSuccess,
        isTrue,
      );
      expect(
        Moment.zoned(
          const MomentParts(year: 2025, month: 3, day: 9, hour: 3),
          ny,
          disambiguation: Disambiguation.reject,
        ).isSuccess,
        isTrue,
      );
    });

    test('should replace fields explicitly without confusing conversion and reinterpretation', () {
      final utc = value(Moment.parse('2025-11-02T01:30:00Z'));
      final zone = value(TimeZone.named('America/New_York'));
      final converted = value(utc.setZone(zone));
      final reinterpreted = value(
        Moment.zoned(utc.parts, zone, disambiguation: Disambiguation.later),
      );
      expect(converted.formatIsoDate(), '2025-11-01');
      expect(reinterpreted.formatIso(), '2025-11-02T06:30:00.000000Z');
      final replaced = value(
        converted.withParts(utc.parts, disambiguation: Disambiguation.earlier),
      );
      expect(replaced.formatIso(), '2025-11-02T05:30:00.000000Z');
      expect((replaced as ZonedMoment).zone, zone);
      expect(
        converted.withParts(utc.parts.copyWith(day: 32), disambiguation: Disambiguation.compatible),
        isA<Failure<Moment, MomentError>>().having(
          (r) => r.error.kind,
          'kind',
          MomentErrorKind.invalidField,
        ),
      );
    });

    test(
      'should resolve fixed and UTC fields identically under every policy without a database',
      () {
        tz.timeZoneDatabase.clear();
        const parts = MomentParts(year: 2026, month: 1, day: 18, hour: 10, microsecond: 1);
        final utc = value(Moment.utc(parts));
        final zone = value(TimeZone.fixed(const Duration(hours: 8)));
        for (final policy in Disambiguation.values) {
          final fixed = value(Moment.zoned(parts, zone, disambiguation: policy));
          expect(fixed.formatIsoOffset(), '2026-01-18T10:00:00.000001+08:00');
          expect(
            value(utc.withParts(parts.copyWith(hour: 11), disambiguation: policy)),
            isA<UtcMoment>(),
          );
          expect(
            value(fixed.withParts(parts.copyWith(hour: 11), disambiguation: policy))
                .formatIsoOffset(),
            '2026-01-18T11:00:00.000001+08:00',
          );
        }
        expect(
          Moment.zoned(
            const MomentParts(year: -271821, month: 4, day: 20),
            zone,
            disambiguation: Disambiguation.reject,
          ),
          isA<Failure<ZonedMoment, MomentError>>().having(
            (r) => r.error.kind,
            'kind',
            MomentErrorKind.outOfRange,
          ),
        );
        expect(
          utc.withParts(parts.copyWith(year: 275761), disambiguation: Disambiguation.reject),
          isA<Failure<Moment, MomentError>>().having(
            (r) => r.error.kind,
            'kind',
            MomentErrorKind.outOfRange,
          ),
        );
        data.initializeTimeZones();
      },
    );

    test('should preserve a location defect instead of labeling it as validation', () {
      final broken = TimeZone.fromLocation(
        tz.Location('broken', [253402214400000], [5], [
          const tz.TimeZone(Duration.zero, isDst: false, abbreviation: 'B'),
        ]),
      );
      expect(
        () => Moment.zoned(
          const MomentParts(year: 9999, month: 12, day: 31),
          broken,
          disambiguation: Disambiguation.earlier,
        ),
        throwsRangeError,
      );
    });
  });
}

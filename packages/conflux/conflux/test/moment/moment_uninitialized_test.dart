import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('TimeZone without initialization', () {
    test('should construct UTC and fixed values without loading or mutating IANA data', () {
      expect(tz.timeZoneDatabase.isInitialized, isFalse);
      final utc = Moment.utc(const MomentParts(year: 2026, month: 1, day: 1));
      expect(utc.isSuccess, isTrue);
      expect(Moment.parse('2026-01-01T00:00:00+08:00').isSuccess, isTrue);
      for (final offset in [
        Duration.zero,
        const Duration(seconds: -86399),
        const Duration(seconds: 86399),
      ]) {
        expect(TimeZone.fixed(offset).isSuccess, isTrue);
      }
      for (final offset in [
        const Duration(days: 1),
        const Duration(days: -1),
        const Duration(microseconds: 1),
      ]) {
        expect(
          TimeZone.fixed(offset),
          isA<Failure<FixedTimeZone, MomentError>>().having(
            (e) => e.error.kind,
            'kind',
            MomentErrorKind.invalidOffset,
          ),
        );
      }
      expect(
        TimeZone.named('America/New_York'),
        isA<Failure<NamedTimeZone, MomentError>>().having(
          (e) => e.error.kind,
          'kind',
          MomentErrorKind.timezoneNotInitialized,
        ),
      );
      final borrowed = TimeZone.fromLocation(tz.UTC);
      expect(borrowed.id, 'Etc/UTC');
      expect(utc.flatMap((v) => v.setZone(borrowed)).isSuccess, isTrue);
      expect(tz.timeZoneDatabase.isInitialized, isFalse);
      tz.timeZoneDatabase.add(tz.UTC);
      expect(
        TimeZone.named('missing'),
        isA<Failure<NamedTimeZone, MomentError>>().having(
          (e) => e.error.kind,
          'kind',
          MomentErrorKind.unknownTimeZone,
        ),
      );
      expect(TimeZone.named('Etc/UTC').isSuccess, isTrue);
    });
  });
}

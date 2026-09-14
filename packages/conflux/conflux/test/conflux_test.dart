import 'package:conflux/conflux.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  group('Conflux', () {
    test('should initialize named timezone support', () {
      expect(timezone.timeZoneDatabase.isInitialized, isFalse);

      Conflux.initialize();

      final zone = (TimeZone.named('Asia/Kolkata') as Success<NamedTimeZone, MomentError>).value;
      final utc = (Moment.parse('2026-01-18T00:00:00Z') as Success<Moment, MomentError>).value;
      final local = (utc.setZone(zone) as Success<ZonedMoment, MomentError>).value;
      expect(local.formatIsoOffset(), '2026-01-18T05:30:00.000000+05:30');

      timezone.setLocalLocation(zone.location);
      Conflux.initialize();
      expect(timezone.local, same(zone.location));
      expect(timezone.getLocation('Asia/Kolkata'), same(zone.location));
    });
  });
}

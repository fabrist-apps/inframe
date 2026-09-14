import 'package:conflux/cron.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'support/moments.dart';

void main() {
  tz_data.initializeTimeZones();
  final utc = tz.UTC;
  final newYork = tz.getLocation('America/New_York');

  group('Cron', () {
    test('should keep large positive steps within field bounds', () {
      const step = '9223372036854775807';
      final cron = (Cron.parse('2/$step 0 0 */$step * *', utc) as Success<Cron, CronError>).value;

      expect(cron.seconds, {2});
      expect(cron.days, {1});
      final reparsed = (Cron.parse(cron.format(), utc) as Success<Cron, CronError>).value;
      expect(reparsed.seconds, cron.seconds);
      expect(reparsed.days, cron.days);
    });

    test('should parse five fields with second zero', () {
      final result = Cron.parse('*/15 9-17 * jan,mar mon-fri', utc);
      final cron = (result as Success<Cron, CronError>).value;

      expect(cron.seconds, {0});
      expect(cron.minutes, {0, 15, 30, 45});
      expect(cron.hours, orderedEquals([9, 10, 11, 12, 13, 14, 15, 16, 17]));
      expect(cron.months, {1, 3});
      expect(cron.weekdays, {1, 2, 3, 4, 5});
      expect(cron.location, same(utc));
      expect(cron.format(), '0 */15 9,10,11,12,13,14,15,16,17 * 1,3 1,2,3,4,5');
    });

    test('should parse six fields with lists ranges steps and Sunday aliases', () {
      final zeroSunday = Cron.parse('5,10-12/2 0 8 1-7/2 * 0', utc);
      final sevenSunday = Cron.parse('5,10-12/2 0 8 1-7/2 * 7', utc);

      final first = (zeroSunday as Success<Cron, CronError>).value;
      final second = (sevenSunday as Success<Cron, CronError>).value;
      expect(first.seconds, {5, 10, 12});
      expect(first.days, {1, 3, 5, 7});
      expect(first.weekdays, {0});
      expect(second.weekdays, {0});
    });

    test('should return typed errors for syntax and field bounds', () {
      for (final expression in [
        '* * *',
        '60 * * * * *',
        '* * 24 * * *',
        '* * * 0 * *',
        '* * * * foo *',
        '* * * * * */0',
        '0xA * * * * *',
        '+1 * * * * *',
        '* * * * * */+2',
        '* * * * * mon-sun/what',
      ]) {
        expect(Cron.parse(expression, utc), isA<Failure<Cron, CronError>>());
      }
    });

    test('should copy field sets and expose immutable values', () {
      final callerMinutes = <int>{5};
      final result = Cron.fromFields(
        minutes: callerMinutes,
        location: utc,
      );
      final cron = (result as Success<Cron, CronError>).value;

      callerMinutes.add(10);

      expect(cron.minutes, {5});
      expect(() => cron.minutes.add(15), throwsUnsupportedError);
      expect(cron.seconds, everyElement(inInclusiveRange(0, 59)));
      expect(cron.format(), '* 5 * * * *');
    });

    test('should reject explicitly empty or out-of-range field sets', () {
      expect(
        Cron.fromFields(seconds: const {}, location: utc),
        isA<Failure<Cron, CronError>>(),
      );
      expect(
        Cron.fromFields(hours: const {24}, location: utc),
        isA<Failure<Cron, CronError>>(),
      );
    });

    test('should match the supplied instant in its own location', () {
      final globalLocation = tz.local;
      final cron = (Cron.parse('0 0 9 * * *', newYork) as Success<Cron, CronError>).value;

      expect(cron.matches(utcMoment(2026, 1, 15, 14)), isTrue);
      expect(cron.matches(utcMoment(2026, 1, 15, 9)), isFalse);
      expect(tz.local, same(globalLocation));
    });

    test('should OR two restricted day fields', () {
      final cron = (Cron.parse('0 0 0 13 * mon', utc) as Success<Cron, CronError>).value;

      expect(cron.matches(utcMoment(2026, 1, 13)), isTrue);
      expect(cron.matches(utcMoment(2026, 1, 19)), isTrue);
      expect(cron.matches(utcMoment(2026, 1, 14)), isFalse);
    });

    test('should AND day fields when either starts with wildcard', () {
      final unrestrictedDay = (Cron.parse('0 0 0 * * mon', utc) as Success<Cron, CronError>).value;
      final steppedDay = (Cron.parse('0 0 0 */2 * mon', utc) as Success<Cron, CronError>).value;

      expect(unrestrictedDay.matches(utcMoment(2026, 1, 19)), isTrue);
      expect(unrestrictedDay.matches(utcMoment(2026, 1, 20)), isFalse);
      expect(steppedDay.matches(utcMoment(2026, 1, 19)), isTrue);
      expect(steppedDay.matches(utcMoment(2026, 1, 26)), isFalse);
    });

    test('should preserve wildcard-sensitive semantics through format', () {
      final original = (Cron.parse('0 0 0 */2 jan,mar mon', utc) as Success<Cron, CronError>).value;
      final formatted = original.format();
      final reparsed = (Cron.parse(formatted, utc) as Success<Cron, CronError>).value;

      for (final instant in [
        utcMoment(2026, 1, 19),
        utcMoment(2026, 1, 20),
        utcMoment(2026, 3, 2),
      ]) {
        expect(reparsed.matches(instant), original.matches(instant));
      }
    });

    test('should canonicalize equivalent names aliases and duplicate values', () {
      final named = (Cron.parse('0 0 0 1 JAN SUN', utc) as Success<Cron, CronError>).value;
      final numeric = (Cron.parse('0 0 0 1 1 7,0', utc) as Success<Cron, CronError>).value;

      expect(named.format(), '0 0 0 1 1 0');
      expect(numeric.format(), named.format());
    });
  });
}

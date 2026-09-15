// Explicit types verify non-nullable versus nullable conversion results.
// ignore_for_file: omit_local_variable_types
import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

Moment _moment(String text) => Moment.parse(text).getOrThrowWith((e) => StateError(e.message));

void main() {
  group('Val Moment integration', () {
    test('should retain existing Moment instances and reject native/string inputs', () {
      for (final text in ['2026-01-01T00:00:00.123456Z', '2026-01-01T00:00:00.123456+05:30']) {
        final moment = _moment(text);
        expect(Val.moment().parse(moment), same(moment));
      }
      expect(issues(Val.moment(), DateTime.utc(2026)).single.code, 'INVALID_TYPE');
      expect(
        issues(Val.moment(name: 'Start'), '2026-01-01T00:00:00Z').single.message,
        'Start must be a Moment',
      );
      expect(issues(Val.moment(code: 'TYPE', message: ''), null).single.message, '');
    });
    test('should compare instant bounds inclusively across zone representations', () {
      final utc = _moment('2026-01-01T00:00:00Z');
      final zoned = _moment('2026-01-01T05:30:00+05:30');
      expect(Val.moment().min(utc).max(utc).parse(zoned), same(zoned));
      final earlier = _moment('2025-12-31T23:59:59Z');
      final later = _moment('2026-01-01T00:00:01Z');
      final minimum = issues(Val.moment(name: 'Start').min(utc), earlier).single;
      expect(
        (minimum.code, minimum.message),
        ('MIN_MOMENT', 'Start must be at or after 2026-01-01T00:00:00.000000Z'),
      );
      final maximum = issues(Val.moment().max(utc), later).single;
      expect(
        (maximum.code, maximum.message),
        ('MAX_MOMENT', 'Must be at or before 2026-01-01T00:00:00.000000Z'),
      );
      expect(
        issues(Val.moment().min(utc, code: 'C'), earlier).single.message,
        'Must be at or after ${utc.formatIso()}',
      );
      expect(issues(Val.moment().max(utc, message: ''), later).single.code, 'MAX_MOMENT');
    });
    test(
      'should parse strict ISO strings while retaining instant precision and representation',
      () {
        final Schema<Moment> schema = Val.string(name: 'Start').moment();
        for (final input in ['2026-01-01T00:00:00.123456Z', '2026-01-01T05:30:00.123456+05:30']) {
          final result = schema.parse(input);
          expect(result, _moment(input));
          expect(result.microsecondsSinceEpoch % 1000000, 123456);
          expect(Val.string().datetime().parse(input), input);
        }
        expect(schema.parse('2026-01-01T00:00:00+00:00'), isA<ZonedMoment>());
        expect(schema.parse('2026-01-01T00:00:00Z'), isA<UtcMoment>());
        for (final input in [
          '2026-01-01',
          '2026-01-01T00:00:00',
          '2026-02-30T00:00:00Z',
          '2026-01-01T00:00:00.1234567Z',
          ' 2026-01-01T00:00:00Z',
        ]) {
          final error = issues(schema, input).single;
          expect(
            (error.code, error.message),
            ('INVALID_MOMENT', 'Start must be a valid timestamp'),
          );
          expect(issues(Val.string().datetime(), input).single.code, 'INVALID_MOMENT');
        }
      },
    );
    test('should skip conversion and later checks when source checks fail', () {
      var after = 0;
      final schema = Val.string(code: 'TEXT')
          .minLength(50, code: 'SHORT')
          .moment(code: 'TIME')
          .refine((_) {
            after++;
            return false;
          });
      expect(issues(schema, 'bad').single.code, 'SHORT');
      expect(issues(schema, 1).single.code, 'TEXT');
      expect(after, 0);
      final bound = _moment('2026-01-01T00:00:00Z');
      expect(Val.string().moment().min(bound).max(bound).parse('2026-01-01T00:00:00Z'), bound);
      final errors = issues(
        Val.string().moment().min(bound).refine((_) => false),
        '2025-01-01T00:00:00Z',
      );
      expect(errors.single.code, 'MIN_MOMENT');
      final defect = StateError('source');
      expect(
        () => Val.string().refine((_) => throw defect).moment().parse('x'),
        throwsA(same(defect)),
      );
    });
    test('should retain optional and nullable ordering through conversion', () {
      var early = 0;
      final Schema<Moment?> schema = Val.string(name: 'Start')
          .refine((_) {
            early++;
            return false;
          })
          .nullable()
          .moment();
      expect(schema.parse(null), isNull);
      expect(early, 0);
      expect(
        issues(schema.refine((value) => value != null), null).single.message,
        'Start is invalid',
      );
      expect(
        issues(Val.string().nullable().refine((value) => value != null).moment(), null).single.code,
        'CUSTOM',
      );
      final object = Val.object({'start': Val.string().optional().moment()});
      expect(object.parse({}), isEmpty);
      expect(issues(object, {'start': null}).single.code, 'NOT_NULL');
      expect(
        Val.object({'start': Val.string().nullable().optional().moment()}).parse({'start': null}),
        {'start': null},
      );
      expect(schema.min(_moment('2026-01-01T00:00:00Z')).parse(null), isNull);
    });
    test('should preserve configured parser issues at structural field paths', () {
      final object = Val.object({
        'start': Val.string().moment(code: 'TIME', message: 'Timestamp required'),
      });
      final error = issues(object, {'start': '2026-02-30T00:00:00Z'}).single;
      expect(
        (error.code, error.message),
        ('TIME', 'Timestamp required'),
      );
      expect(error.path, [const FieldSegment('start')]);
      expect(
        issues(Val.string(name: 'Start').datetime(code: 'C'), 'bad').single.message,
        'Start must be a valid timestamp',
      );
    });
  });
}

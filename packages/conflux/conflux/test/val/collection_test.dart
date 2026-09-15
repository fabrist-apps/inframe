// Explicit types prove nullable collection outputs.
// ignore_for_file: omit_local_variable_types
import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

void main() {
  group('Val collections', () {
    test('should preserve present null in typed lists and maps', () {
      final Schema<List<String?>> list = Val.list(Val.string().nullable());
      expect(list.parse(['x', null]), ['x', null]);
      final Schema<Map<String, String?>> map = Val.map(Val.string().nullable());
      expect(map.parse({'x': null}), {'x': null});
      expect(Val.list(Val.string().optional()).parse(['x']), ['x']);
      expect(issues(Val.list(Val.string().optional()), [null]).single.code, 'NOT_NULL');
    });
    test('should flatten nested failures in key and index order', () {
      final schema = Val.map(Val.list(Val.object({'name': Val.string(name: 'Name')})));
      final errors = issues(schema, {
        'b': [
          {'name': 1},
          <String, Object?>{},
        ],
        'a': [
          {'name': null},
        ],
      });
      expect(errors.map((e) => e.path), [
        [const FieldSegment('b'), IndexSegment(0), const FieldSegment('name')],
        [const FieldSegment('b'), IndexSegment(1), const FieldSegment('name')],
        [const FieldSegment('a'), IndexSegment(0), const FieldSegment('name')],
      ]);
      expect(errors.map((e) => e.code), ['INVALID_TYPE', 'REQUIRED', 'NOT_NULL']);
    });
    test('should reject non-string keys before validating any map values', () {
      var calls = 0;
      final schema = Val.map(
        Val.string().refine((_) {
          calls++;
          return true;
        }),
      );
      expect(issues(schema, <Object?, Object?>{'x': 'ok', 1: 'bad'}).single.path, isEmpty);
      expect(calls, 0);
      expect(schema.parse(<Object?, Object?>{'x': 'ok'}), {'x': 'ok'});
    });
    test('should skip list and map checks until all children succeed', () {
      var calls = 0;
      final list = Val.list(Val.string()).minLength(4).unique().refine((_) {
        calls++;
        return false;
      });
      expect(issues(list, [1, null]).map((e) => e.code), ['INVALID_TYPE', 'NOT_NULL']);
      expect(calls, 0);
      expect(issues(list, ['a', 'a']).single.code, 'MIN_LENGTH');
      final map = Val.map(Val.int()).refine((_) {
        calls++;
        return false;
      });
      final before = calls;
      expect(issues(map, {'x': 'bad'}).single.code, 'INVALID_TYPE');
      expect(calls, before);
    });
    test('should measure list counts', () {
      expect(Val.list(Val.string()).minLength(1).maxLength(1).length(1).parse(['😀']), ['😀']);
      expect(
        issues(Val.list(Val.string()).notEmpty(), []).single.message,
        'Must contain at least 1 item',
      );
      expect(
        issues(Val.list(Val.string(), name: 'Tags').length(2), []).single.message,
        'Tags must contain exactly 2 items',
      );
      expect(issues(Val.list(Val.string()).maxLength(0, code: 'C'), ['x']).single.code, 'C');
      expect(issues(Val.list(Val.string()).minLength(2, message: ''), []).single.message, '');
      expect(
        issues(Val.list(Val.string(), name: 'Tags'), 'x').single.message,
        'Tags must be a list',
      );
      expect(
        issues(Val.map(Val.int(), name: 'Counts'), null).single.message,
        'Counts must not be null',
      );
    });
    test('should use parsed equality and emit one uniqueness issue', () {
      final lists = Val.list(Val.list(Val.int())).unique();
      expect(
        lists.parse([
          [1],
          [1],
        ]),
        [
          [1],
          [1],
        ],
      );
      final borrowed = [1];
      final instances = Val.list(Val.instance<List<int>>()).unique();
      expect(issues(instances, [borrowed, borrowed, borrowed]).single.code, 'UNIQUE');
      expect(
        issues(Val.list(Val.string().nullable()).unique(), [null, null]).single.code,
        'UNIQUE',
      );
      final utc = Moment.parse('2026-01-01T00:00:00Z')
          .getOrThrowWith((error) => StateError(error.message));
      final fixed = Moment.parse('2026-01-01T00:00:00+00:00')
          .getOrThrowWith((error) => StateError(error.message));
      expect(Val.list(Val.instance<Moment>()).unique().parse([utc, fixed]), [utc, fixed]);
      expect(issues(Val.list(Val.instance<Moment>()).unique(), [utc, utc]).single.path, isEmpty);
    });
    test('should detach containers, borrow instances, and isolate derivation and reuse', () {
      final input = <String, List<String>>{
        'x': ['a'],
      };
      final schema = Val.map(Val.list(Val.string()));
      final output = schema.parse(input);
      input['x']!.add('b');
      expect(output, {
        'x': ['a'],
      });
      expect(output.clear, throwsUnsupportedError);
      expect(() => output['x']!.add('c'), throwsUnsupportedError);
      final original = Val.list(Val.string());
      issues(original.notEmpty(), []);
      expect(original.parse([]), isEmpty);
      expect(original.parse(['ok']), ['ok']);
      final error = issues(
        Val.list(
          Val.string(name: 'Item').refine((_) => false, path: [const FieldSegment('detail')]),
          name: 'Items',
        ),
        ['x'],
      ).single;
      expect(error.path, [IndexSegment(0), const FieldSegment('detail')]);
      expect(error.message, 'Item is invalid');
    });
  });
}

// Explicit types exercise the public contract.
// ignore_for_file: omit_local_variable_types

import 'package:conflux/conflux.dart';
import 'package:conflux/val.dart' as direct;
import 'package:test/test.dart';

List<ValidationIssue> issues(Schema<Object?> schema, Object? input) => schema
    .safeParse(input)
    .match(
      onSuccess: (_) => throw StateError('Expected failure'),
      onFailure: (errors) => errors.toList(),
    );

void main() {
  group('Schema', () {
    test('should return a validated string unchanged through both entrypoints', () {
      expect(Val.string().parse('hello'), 'hello');
      expect(direct.Val.string().parse('hello'), 'hello');
      final Result<String, NonEmptyList<ValidationIssue>> result = Val.string().safeParse('x');
      expect(result.getOrNull(), 'x');
    });
    test('should skip incompatible checks and propagate callback exceptions', () {
      var calls = 0;
      final schema = Val.string().refine((v) {
        calls++;
        return false;
      });
      expect(issues(schema, 1).single.code, 'INVALID_TYPE');
      expect(calls, 0);
      expect(issues(schema, 'x').single.message, 'Invalid value');
      final defect = StateError('callback');
      expect(() => Val.string().refine((_) => throw defect).parse('x'), throwsA(same(defect)));
    });
    test('should preserve nullable stage ordering and typed output', () {
      var early = 0;
      final base = Val.string(name: ' Label ').refine((v) {
        early++;
        return false;
      });
      final Schema<String?> nullable = base.nullable();
      expect(nullable.parse(null), isNull);
      expect(early, 0);
      expect(issues(nullable.refine((v) => v != null), null).single.message, 'Label is invalid');
      expect(issues(base, null).single.code, 'NOT_NULL');
      expect(nullable.nullable().parse(null), isNull);
    });
    test('should stop chained checks after the first failure', () {
      final schema = Val.string(name: 'Password').minLength(8).maxLength(2).refine((_) => false);
      expect(issues(schema, 'four').map((e) => e.code), ['MIN_LENGTH']);
      expect(issues(schema, 'four').first.message, 'Password must contain at least 8 characters');
      expect(Val.string().length(2).parse('😀'), '😀');
      expect(
        issues(Val.string().notEmpty(), '').single.message,
        'Must contain at least 1 character',
      );
    });
    test('should throw an exception carrying the same failure details', () {
      final schema = Val.string().minLength(4);
      final failure = issues(schema, 'x');
      expect(
        () => schema.parse('x'),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.issues.map((v) => (v.code, v.message)),
            'issues',
            failure.map((v) => (v.code, v.message)),
          ),
        ),
      );
      expect(() => failure.first.path.add(const FieldSegment('x')), throwsUnsupportedError);
      expect(() => IndexSegment(-1), throwsArgumentError);
      expect(const FieldSegment(''), const FieldSegment(''));
      expect(IndexSegment(0), IndexSegment(0));
    });
  });
  group('ObjectSchema', () {
    test('should distinguish absence from present null and last presence selection', () {
      final object = Val.object({
        'a': Val.string(name: 'A').required(code: 'M'),
        'b': Val.string().optional(),
        'c': Val.string().nullable(),
      });
      expect(object.parse({'a': 'a', 'c': null}), {'a': 'a', 'c': null});
      expect(issues(object, {'a': 'a', 'b': null, 'c': null}).single.code, 'NOT_NULL');
      expect(issues(object, {'c': null}).single.code, 'M');
      expect(issues(object, {'c': null}).single.message, 'A is required');
      final field = Val.string().required(code: 'M').optional().required();
      expect(issues(Val.object({'x': field}), {}).single.code, 'REQUIRED');
      expect(Val.object({'x': field.optional()}).parse({}), isEmpty);
    });
    test('should order nested fields and extras and skip incomplete object refinements', () {
      var calls = 0;
      final schema =
          Val.object({
            'nested': Val.object({'b': Val.string(), 'a': Val.string()}),
          }).refine((_) {
            calls++;
            return false;
          });
      final errors = issues(schema, {
        'extra': 1,
        'nested': {'a': 2, 'b': null},
      });
      expect(errors.map((e) => e.path), [
        [const FieldSegment('nested'), const FieldSegment('b')],
        [const FieldSegment('nested'), const FieldSegment('a')],
        [const FieldSegment('extra')],
      ]);
      expect(calls, 0);
      expect(errors.map((e) => e.code), ['NOT_NULL', 'INVALID_TYPE', 'UNRECOGNIZED_KEY']);
    });
    test('should reject non-string keys before callbacks regardless of map generic types', () {
      var calls = 0;
      final schema = Val.object({
        'x': Val.string().refine((_) {
          calls++;
          return true;
        }),
      });
      expect(issues(schema, <Object?, Object?>{'x': 'x', 1: 'bad'}).single.code, 'INVALID_TYPE');
      expect(calls, 0);
      expect(schema.parse(<Object?, Object?>{'x': 'x'}), {'x': 'x'});
    });
    test('should apply local immutable policies before refinements with last policy winning', () {
      final borrowed = <int>[1];
      final input = {'x': 'ok', 'extra': borrowed};
      final base = Val.object({'x': Val.string()}, name: 'Profile');
      expect(issues(base, input).single.message, 'Property is not allowed in Profile');
      expect(base.strip().refine((v) => !v.containsKey('extra')).parse(input), {'x': 'ok'});
      final output = base.strip().passthrough().parse(input);
      expect(output['extra'], same(borrowed));
      expect(() => output['x'] = 'new', throwsUnsupportedError);
      expect(input['x'], 'ok');
      expect(
        issues(base.passthrough().strict(code: 'EXTRA', message: 'No extras'), input).single.code,
        'EXTRA',
      );
      expect(issues(base, input).single.code, 'UNRECOGNIZED_KEY');
      expect(
        issues(Val.object({'nested': base}).strip(), {'nested': input, 'other': 1}).single.path,
        [const FieldSegment('nested'), const FieldSegment('extra')],
      );
      expect(base.strip().nullable().refine((v) => v == null).parse(null), isNull);
    });
    test('should copy fields and relative paths and isolate repeated parsing', () {
      final path = <PathSegment>[const FieldSegment('confirm')];
      final child = Val.string(name: 'Child').refine((_) => false, code: 'APP', path: path);
      path.clear();
      final fields = <String, Schema<Object?>>{'key': child};
      final schema = Val.object(fields, name: 'Parent');
      fields.clear();
      final error = issues(schema, {'key': 'x'}).single;
      expect(error.path, [const FieldSegment('key'), const FieldSegment('confirm')]);
      expect(error.message, 'Child is invalid');
      expect(error.code, 'APP');
      final reusable = Val.object({'x': Val.string()});
      issues(reusable, {'x': 1});
      expect(reusable.parse({'x': 'ok'}), {'x': 'ok'});
      expect(
        () => (reusable.safeParse({
          'x': 1,
        }) as Failure<Map<String, Object?>, NonEmptyList<ValidationIssue>>).error.values.clear(),
        throwsUnsupportedError,
      );
    });
  });
}

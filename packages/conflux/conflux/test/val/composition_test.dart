import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

void main() {
  group('ObjectSchema composition', () {
    test('should replace fields without moving them and append in incoming order', () {
      final base = Val.object({'b': Val.string(), 'a': Val.string()});
      final extended = base.extend({'b': Val.int(), 'c': Val.boolean()});
      expect(extended.fields.keys, ['b', 'a', 'c']);
      expect(extended.parse({'a': 'x', 'b': 1, 'c': true}).keys, ['b', 'a', 'c']);
      expect(base.parse({'a': 'x', 'b': 'old'}), {'b': 'old', 'a': 'x'});
    });
    test('should retain left settings and adopt right merge policy and fields', () {
      final left = Val.object(
        {'x': Val.string()},
        name: 'Left',
        code: 'LEFT_TYPE',
      ).required(code: 'LEFT_MISSING').nullable().passthrough();
      final right = Val.object({
        'x': Val.int(),
        'y': Val.string().optional(),
      }, name: 'Right').strict(code: 'RIGHT_EXTRA', message: 'Right extras');
      final merged = left.merge(right);
      expect(merged.parse(null), isNull);
      expect(merged.parse({'x': 1}), {'x': 1});
      expect(issues(merged, 1).single.code, 'LEFT_TYPE');
      expect(issues(merged, 1).single.message, 'Left must be an object with string keys');
      expect(issues(Val.object({'merged': merged}), {}).single.code, 'LEFT_MISSING');
      expect(issues(merged, {'x': 1, 'extra': true}).single.code, 'RIGHT_EXTRA');
      expect(issues(merged, {'x': 1, 'extra': true}).single.message, 'Right extras');
    });
    test('should pick and omit in schema order and reject unknown keys', () {
      final schema = Val.object({'a': Val.string(), 'b': Val.string(), 'c': Val.string()});
      expect(schema.pick(['c', 'a', 'a']).fields.keys, ['a', 'c']);
      expect(schema.omit(['b', 'b']).fields.keys, ['a', 'c']);
      expect(() => schema.pick(['missing']), throwsArgumentError);
      expect(() => schema.omit(['missing']), throwsArgumentError);
      expect(schema.pick([]).parse({}), isEmpty);
    });
    test('should make only immediate fields optional and retain child refinements', () {
      final schema = Val.object({
        'nested': Val.object({'x': Val.string()}),
        'label': Val.string(name: 'Label').refine((_) => false),
      }).partial();
      expect(schema.parse({}), isEmpty);
      expect(issues(schema, {'nested': <String, Object?>{}}).single.code, 'REQUIRED');
      expect(issues(schema, {'nested': null}).single.code, 'NOT_NULL');
      expect(issues(schema, {'label': 'x'}).single.message, 'Label is invalid');
    });
    test('should reject shape changes after root refinements on either merge side', () {
      final plain = Val.object({'x': Val.string()});
      final refined = plain.refine((value) => value['x'] == 'ok');
      for (final operation in <Object? Function()>[
        () => refined.extend({}),
        () => refined.pick(['x']),
        () => refined.omit(['x']),
        refined.partial,
        () => refined.merge(plain),
        () => plain.merge(refined),
        () => plain.nullable().refine((_) => true).partial(),
      ]) {
        expect(operation, throwsArgumentError);
      }
      expect(refined.strip().parse({'x': 'ok', 'extra': true}), {'x': 'ok'});
    });
    test('should preserve nullable wrapping and presence after multiple shape changes', () {
      final schema = Val.object({
        'x': Val.string(),
      }, name: 'Root').optional().nullable().extend({'y': Val.int()}).omit(['x']).partial().strip();
      expect(schema.parse(null), isNull);
      expect(schema.parse({'extra': true}), isEmpty);
      expect(Val.object({'root': schema}).parse({}), isEmpty);
      expect(issues(schema, {'y': null}).single.path, [const Field('y')]);
    });
  });
  group('Val unions', () {
    test('should select the first successful parsed branch and skip later callbacks', () {
      var later = 0;
      final first = Val.object({'x': Val.string()}).strip();
      final second = Val.object({'x': Val.string()}).passthrough().refine((_) {
        later++;
        return true;
      });
      expect(Val.anyOf([first, second]).parse({'x': 'ok', 'extra': 1}), {'x': 'ok'});
      expect(later, 0);
      expect(Val.anyOf<Object>([Val.string(), Val.int()]).parse(3), 3);
    });
    test('should return one summary when every branch fails and copy the branches', () {
      final branches = <Schema<Object?>>[Val.string(), Val.int()];
      final schema = Val.anyOf(branches, name: 'Choice', code: 'CHOICE');
      branches.clear();
      expect(schema.parse(3), 3);
      final error = issues(schema, false).single;
      expect(
        (error.code, error.kind, error.message),
        ('CHOICE', IssueKind.invalidUnion, 'Choice must match one of the allowed schemas'),
      );
      expect(
        issues(Val.anyOf<Object>([Val.string(), Val.int()]), null).single.code,
        'INVALID_UNION',
      );
      expect(() => Val.anyOf<Object>([]), throwsArgumentError);
    });
    test('should not retry after a selected branch fails union refinement', () {
      var later = 0;
      final schema = Val.anyOf([
        Val.string(),
        Val.string().refine((_) {
          later++;
          return true;
        }),
      ]).refine((_) => false);
      expect(issues(schema, 'x').single.code, 'CUSTOM');
      expect(later, 0);
      final defect = StateError('branch');
      final throwing = Val.anyOf([Val.string().refine((_) => throw defect), Val.string()]);
      expect(() => throwing.parse('x'), throwsA(same(defect)));
    });
    test('should let nullable branches accept null but require outer optionality for absence', () {
      final schema = Val.anyOf<String?>([Val.string().nullable(), Val.string().optional()]);
      expect(schema.parse(null), isNull);
      expect(issues(Val.object({'x': schema}), {}).single.code, 'REQUIRED');
      expect(Val.object({'x': schema.optional()}).parse({}), isEmpty);
      expect(Val.anyOf([Val.string()]).nullable().refine((v) => v == null).parse(null), isNull);
    });
  });
  group('Val discriminated objects', () {
    ObjectSchema<Map<String, Object?>> email() => Val.object({
      'kind': Val.literal('email'),
      'address': Val.string().email(),
    });
    test('should validate only the selected branch and retain its policy and issues', () {
      var other = 0;
      final schemas = {
        'email': email().strip(),
        'sms': Val.object({'kind': Val.literal('sms'), 'number': Val.string()}).refine((_) {
          other++;
          return false;
        }),
      };
      final schema = Val.discriminated(discriminatorKey: 'kind', schemas: schemas);
      schemas.clear();
      expect(schema.parse({'kind': 'email', 'address': 'a@b.co', 'extra': true}), {
        'kind': 'email',
        'address': 'a@b.co',
      });
      expect(issues(schema, {'kind': 'email', 'address': 'bad'}).single.path, [
        const Field('address'),
      ]);
      expect(other, 0);
    });
    test('should report selection errors at the discriminator and root type independently', () {
      final schema = Val.discriminated(
        discriminatorKey: 'kind',
        schemas: {'email': email()},
        name: 'Action',
        code: 'SELECT',
        message: 'Pick an action',
      );
      for (final input in <Map<String, Object?>>[
        {},
        {'kind': 1},
        {'kind': 'other'},
      ]) {
        final error = issues(schema, input).single;
        expect(
          (error.code, error.kind, error.message),
          ('SELECT', IssueKind.invalidDiscriminator, 'Pick an action'),
        );
        expect(error.path, [const Field('kind')]);
      }
      final root = issues(schema, {1: 'email'}).single;
      expect(root.code, 'INVALID_TYPE');
      expect(root.message, 'Action must be an object with string keys');
      expect(root.path, isEmpty);
      expect(schema.nullable().parse(null), isNull);
      expect(Val.object({'action': schema.optional()}).parse({}), isEmpty);
    });
    test('should reject invalid discriminator registrations at construction', () {
      for (final branch in [
        Val.object({'kind': Val.literal('wrong')}),
        Val.object({'kind': Val.string()}),
        Val.object({'kind': Val.literal('email').optional()}),
        Val.object({'kind': Val.literal('email').nullable()}),
        email().optional(),
        email().nullable(),
        Val.object({}),
      ]) {
        expect(
          () => Val.discriminated(discriminatorKey: 'kind', schemas: {'email': branch}),
          throwsArgumentError,
        );
      }
      expect(() => Val.discriminated(discriminatorKey: 'kind', schemas: {}), throwsArgumentError);
    });
  });
}

import 'dart:convert';

import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

void main() {
  group('ValidationIssue serialization', () {
    test('should encode exactly four fields with compact structural paths', () {
      final issue = ValidationIssue(
        code: 'SHORT',
        message: 'Too short',
        kind: IssueKind.tooSmall,
        path: [const Field('users'), Index(0), const Field('name')],
      );
      final map = {
        'code': 'SHORT',
        'message': 'Too short',
        'kind': 'tooSmall',
        'path': ['users', 0, 'name'],
      };
      expect(issue.toMap(), map);
      expect(jsonDecode(issue.toJson()), map);
      final restored = ValidationIssueMapper.fromJson(issue.toJson());
      expect(restored.toMap(), map);
      expect(restored.path, [const Field('users'), Index(0), const Field('name')]);
      expect(ValidationIssueMapper.fromMap(issue.toMap()).toMap(), map);
    });
    test('should pin every kind wire value and preserve empty strings and root paths', () {
      const kinds = [
        'missing',
        'invalidType',
        'invalidValue',
        'invalidFormat',
        'tooSmall',
        'tooBig',
        'invalidLength',
        'notMultipleOf',
        'unsafeInteger',
        'notFinite',
        'notUnique',
        'unrecognizedKey',
        'invalidUnion',
        'invalidDiscriminator',
        'maxDepth',
        'custom',
      ];
      for (var i = 0; i < kinds.length; i++) {
        final issue = ValidationIssue(code: '', message: '', kind: IssueKind.values[i], path: []);
        expect(issue.toMap(), {'code': '', 'message': '', 'kind': kinds[i], 'path': <Object>[]});
        expect(ValidationIssueMapper.fromJson(issue.toJson()).kind, IssueKind.values[i]);
      }
    });
    test('should reject malformed required fields without primitive coercion', () {
      final valid = <String, Object?>{
        'code': 'C',
        'message': 'M',
        'kind': 'custom',
        'path': <Object>[],
      };
      for (final key in valid.keys) {
        final missing = {...valid}..remove(key);
        expect(
          () => ValidationIssueMapper.fromMap(missing),
          throwsA(isA<Exception>()),
          reason: key,
        );
        expect(
          () => ValidationIssueMapper.fromMap({...valid, key: null}),
          throwsA(isA<Exception>()),
          reason: key,
        );
      }
      for (final (key, value) in <(String, Object)>[
        ('code', 1),
        ('code', false),
        ('message', 1),
        ('kind', 1),
        ('kind', 'unknown'),
        ('path', 'x'),
        ('path', <String, Object?>{}),
      ]) {
        expect(
          () => ValidationIssueMapper.fromMap({...valid, key: value}),
          throwsA(isA<Exception>()),
          reason: '$key $value',
        );
        expect(
          () => ValidationIssueMapper.fromJson(jsonEncode({...valid, key: value})),
          throwsA(isA<Exception>()),
        );
      }
    });
    test('should reject malformed path segments but retain empty fields and zero indices', () {
      final valid = <String, Object?>{
        'code': 'C',
        'message': 'M',
        'kind': 'custom',
        'path': ['', 0],
      };
      expect(ValidationIssueMapper.fromMap(valid).path, [const Field(''), Index(0)]);
      for (final segment in <Object?>[
        -1,
        0.0,
        true,
        null,
        [],
        <String, Object?>{},
        const Field('x'),
      ]) {
        expect(
          () => ValidationIssueMapper.fromMap({
            ...valid,
            'path': [segment],
          }),
          throwsA(isA<Exception>()),
          reason: '$segment',
        );
      }
    });
    test('should detach paths during construction, decode, and generated copying', () {
      final path = <PathSegment>[const Field('x')];
      final issue = ValidationIssue(code: 'C', message: 'M', kind: IssueKind.custom, path: path);
      path.clear();
      expect(issue.path, [const Field('x')]);
      final encoded = <Object>['y', 0];
      final restored = ValidationIssueMapper.fromMap({
        'code': 'C',
        'message': 'M',
        'kind': 'custom',
        'path': encoded,
      });
      encoded.clear();
      expect(restored.path, [const Field('y'), Index(0)]);
      expect(restored.path.clear, throwsUnsupportedError);
      final replacement = <PathSegment>[const Field('z')];
      final copied = restored.copyWith(path: replacement);
      replacement.clear();
      expect(copied.path, [const Field('z')]);
      expect(copied.path.clear, throwsUnsupportedError);
      expect(restored.copyWith(message: 'new').path.clear, throwsUnsupportedError);
    });
    test('should round-trip real nested failures and relative refinement paths', () {
      final schema = Val.object({
        'users': Val.list(
          Val.object({
            'password': Val.string(name: 'Password').minLength(8, code: 'PASSWORD_TOO_SHORT'),
          }).refine((_) => false, path: [const Field('confirmation')]),
        ),
      });
      for (final input in [
        {
          'users': [
            {'password': 'short'},
          ],
        },
        {
          'users': [
            {'password': 'long enough'},
          ],
        },
      ]) {
        final issue = issues(schema, input).single;
        final restored = ValidationIssueMapper.fromJson(issue.toJson());
        expect(
          (restored.code, restored.message, restored.kind),
          (issue.code, issue.message, issue.kind),
        );
        expect(restored.path, issue.path);
        expect(restored.path.take(2), [const Field('users'), Index(0)]);
      }
    });
  });
}

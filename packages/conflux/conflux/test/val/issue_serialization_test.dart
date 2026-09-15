import 'dart:convert';

import 'package:conflux/conflux.dart' show Conflux;
import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

void main() {
  setUpAll(Conflux.initialize);

  group('ValidationIssue serialization', () {
    test('should encode exactly three fields with compact structural paths', () {
      final issue = ValidationIssue(
        code: 'SHORT',
        message: 'Too short',
        path: [const FieldSegment('users'), IndexSegment(0), const FieldSegment('name')],
      );
      final map = {
        'code': 'SHORT',
        'message': 'Too short',
        'path': ['users', 0, 'name'],
      };
      expect(issue.toMap(), map);
      expect(jsonDecode(issue.toJson()), map);
      final restored = ValidationIssueMapper.fromJson(issue.toJson());
      expect(restored.toMap(), map);
      expect(restored.path, [
        const FieldSegment('users'),
        IndexSegment(0),
        const FieldSegment('name'),
      ]);
      expect(ValidationIssueMapper.fromMap(issue.toMap()).toMap(), map);
    });
    test('should reject malformed path segments but retain empty fields and zero indices', () {
      final valid = <String, Object?>{
        'code': 'C',
        'message': 'M',
        'path': ['', 0],
      };
      expect(ValidationIssueMapper.fromMap(valid).path, [const FieldSegment(''), IndexSegment(0)]);
      for (final segment in <Object?>[
        -1,
        0.0,
        true,
        null,
        [],
        <String, Object?>{},
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
      final path = <PathSegment>[const FieldSegment('x')];
      final issue = ValidationIssue(code: 'C', message: 'M', path: path);
      path.clear();
      expect(issue.path, [const FieldSegment('x')]);
      final encoded = <Object>['y', 0];
      final restored = ValidationIssueMapper.fromMap({
        'code': 'C',
        'message': 'M',
        'path': encoded,
      });
      encoded.clear();
      expect(restored.path, [const FieldSegment('y'), IndexSegment(0)]);
      expect(restored.path.clear, throwsUnsupportedError);
      final replacement = <PathSegment>[const FieldSegment('z')];
      final copied = restored.copyWith(path: replacement);
      replacement.clear();
      expect(copied.path, [const FieldSegment('z')]);
      expect(copied.path.clear, throwsUnsupportedError);
      expect(restored.copyWith(message: 'new').path.clear, throwsUnsupportedError);
    });
    test('should round-trip real nested failures and relative refinement paths', () {
      final schema = Val.object({
        'users': Val.list(
          Val.object({
            'password': Val.string(name: 'Password').minLength(8, code: 'PASSWORD_TOO_SHORT'),
          }).refine((_) => false, path: [const FieldSegment('confirmation')]),
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
          (restored.code, restored.message),
          (issue.code, issue.message),
        );
        expect(restored.path, issue.path);
        expect(restored.path.take(2), [const FieldSegment('users'), IndexSegment(0)]);
      }
    });
  });
}

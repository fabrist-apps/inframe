import 'package:chrono_id/chrono_id.dart';
import 'package:conflux/val.dart';
import 'package:test/test.dart';

import 'schema_test.dart' show issues;

void main() {
  group('Val Chrono ID integration', () {
    test('should preserve structurally valid IDs including future timestamps', () {
      for (final (prefix, size, id) in <(String?, int, String)>[
        (null, 24, '000000000000000000000000'),
        ('use', 24, 'use_000000000000000000000000'),
        ('Use1', 16, 'Use1_zzzzzzzz00000000'),
        (null, 16, 'zzzzzzzzZZZZZZZZ'),
      ]) {
        expect(ChronoID.isValid(id, prefix: prefix, size: size), isTrue);
        expect(Val.chronoId(prefix: prefix, size: size).parse(id), id);
        expect(Val.string().chronoId(prefix: prefix, size: size).parse(id), id);
      }
    });
    test('should delegate malformed candidates and exact prefix/size behavior to the core', () {
      for (final input in [
        'use_000000000000000000000000',
        '00000000000000000000000!',
        ' 000000000000000000000000',
        '000000000000000000000000\n',
        'short',
        'use__000000000000000000000000',
      ]) {
        expect(ChronoID.isValid(input), isFalse);
        expect(issues(Val.chronoId(), input).single.code, 'INVALID_CHRONO_ID');
      }
      expect(
        issues(Val.chronoId(prefix: 'use'), 'Use_000000000000000000000000').single.code,
        'INVALID_CHRONO_ID',
      );
      expect(
        issues(Val.chronoId(size: 16), '000000000000000000000000').single.code,
        'INVALID_CHRONO_ID',
      );
    });
    test('should reject invalid configuration eagerly for both forms', () {
      for (final prefix in ['', '1use', 'u_se', 'use-']) {
        expect(() => Val.chronoId(prefix: prefix), throwsArgumentError);
        expect(() => Val.string().chronoId(prefix: prefix), throwsArgumentError);
      }
      for (final size in [-1, 0, 15]) {
        expect(() => Val.chronoId(size: size), throwsArgumentError);
        expect(() => Val.string().chronoId(size: size), throwsArgumentError);
      }
    });
    test('should keep format overrides independent of type and presence errors', () {
      final schema = Val.chronoId(name: ' User ID ', code: 'ID');
      final error = issues(schema, 'bad').single;
      expect(
        (error.code, error.kind, error.message),
        ('ID', IssueKind.invalidFormat, 'User ID must be a valid Chrono ID'),
      );
      expect(issues(schema, 1).single.code, 'INVALID_TYPE');
      expect(issues(Val.chronoId(message: ''), 'bad').single.message, '');
      expect(issues(Val.string(code: 'TEXT').chronoId(code: 'ID'), 1).single.code, 'TEXT');
      expect(issues(Val.object({'id': schema}), {}).single.code, 'REQUIRED');
      expect(issues(Val.object({'id': schema}), {'id': 'bad'}).single.path, [const Field('id')]);
      expect(Val.object({'id': schema.optional()}).parse({}), isEmpty);
      expect(schema.nullable().parse(null), isNull);
    });
    test('should preserve constraints and specialized methods without mutating the source', () {
      final source = Val.string().minLength(1);
      final schema = source.chronoId().endsWith('0');
      expect(schema.parse('000000000000000000000000'), '000000000000000000000000');
      expect(issues(schema, '').map((e) => e.code), [
        'MIN_LENGTH',
        'INVALID_CHRONO_ID',
        'ENDS_WITH',
      ]);
      expect(source.parse('ordinary'), 'ordinary');
      expect(issues(schema, 'ordinary').first.code, 'INVALID_CHRONO_ID');
    });
  });
}

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
        expect(Val.string().chronoId(prefix: prefix, size: size).parse(id), id);
      }
    });
    test('should keep format overrides independent of type and presence errors', () {
      final schema = Val.string(name: ' User ID ').chronoId(code: 'ID');
      final error = issues(schema, 'bad').single;
      expect(
        (error.code, error.message),
        ('ID', 'User ID must be a valid Chrono ID'),
      );
      expect(issues(schema, 1).single.code, 'INVALID_TYPE');
      expect(issues(Val.string(code: 'TEXT').chronoId(code: 'ID'), 1).single.code, 'TEXT');
      expect(issues(Val.object({'id': schema}), {}).single.code, 'REQUIRED');
      expect(issues(Val.object({'id': schema}), {'id': 'bad'}).single.path, [
        const FieldSegment('id'),
      ]);
      expect(Val.object({'id': schema.optional()}).parse({}), isEmpty);
      expect(schema.nullable().parse(null), isNull);
    });
    test('should preserve constraints and specialized methods without mutating the source', () {
      final source = Val.string().minLength(1);
      final schema = source.chronoId().endsWith('0');
      expect(schema.parse('000000000000000000000000'), '000000000000000000000000');
      expect(issues(schema, '').single.code, 'MIN_LENGTH');
      expect(source.parse('ordinary'), 'ordinary');
      expect(issues(schema, 'ordinary').first.code, 'INVALID_CHRONO_ID');
    });
  });
}

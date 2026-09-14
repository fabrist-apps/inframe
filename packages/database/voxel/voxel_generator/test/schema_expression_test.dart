import 'package:test/test.dart';
import 'package:voxel_generator/src/migration/schema_expression.dart';

void main() {
  group('parseSchemaExpression', () {
    test('should decode one quoted string literal', () {
      expect(parseSchemaExpression("'Ada''s app'"), {
        'formatVersion': 1,
        'kind': 'literal',
        'literalType': 'string',
        'value': "Ada's app",
      });
    });

    test('should reject quoted SQL containing another expression', () {
      expect(
        () => parseSchemaExpression("'a' || 'b'"),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

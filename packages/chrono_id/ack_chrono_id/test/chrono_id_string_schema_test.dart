import 'package:ack/ack.dart';
import 'package:ack_chrono_id/ack_chrono_id.dart';
import 'package:chrono_id/chrono_id.dart';
import 'package:test/test.dart';

void main() {
  group('ChronoIDStringSchema', () {
    test('should validate a generated ID through an Ack object', () {
      final id = ChronoID.generate(prefix: 'use');
      final schema = Ack.object({'id': Ack.string().chronoId(prefix: 'use')});

      final result = schema.safeParse({'id': id});

      expect(result.isOk, isTrue);
      expect(result.getOrNull(), {'id': id});
    });

    test('should support default, prefixed, and custom-size IDs', () {
      final defaultId = ChronoID.generate();
      final prefixedId = ChronoID.generate(prefix: 'use');
      final customId = ChronoID.generate(size: 32);

      expect(Ack.string().chronoId().safeParse(defaultId).getOrNull(), defaultId);
      expect(
        Ack.string().chronoId(prefix: 'use').safeParse(prefixedId).getOrNull(),
        prefixedId,
      );
      expect(Ack.string().chronoId(size: 32).safeParse(customId).getOrNull(), customId);
    });

    test('should reject malformed IDs and mismatched configuration', () {
      final prefixedId = ChronoID.generate(prefix: 'use');
      final customId = ChronoID.generate(size: 32);

      expect(Ack.string().chronoId().safeParse('invalid').isFail, isTrue);
      expect(Ack.string().chronoId(prefix: 'Use').safeParse(prefixedId).isFail, isTrue);
      expect(Ack.string().chronoId().safeParse(customId).isFail, isTrue);
    });

    test('should reject invalid configuration during schema construction', () {
      expect(() => Ack.string().chronoId(size: 15), throwsArgumentError);
      expect(() => Ack.string().chronoId(prefix: ''), throwsArgumentError);
      expect(() => Ack.string().chronoId(prefix: 'user_id'), throwsArgumentError);
    });

    test('should report the default refinement error at the nested field path', () {
      final schema = Ack.object({
        'user': Ack.object({'id': Ack.string().chronoId(prefix: 'use')}),
      });

      final result = schema.safeParse({
        'user': {'id': 'invalid'},
      });
      final error = _leafError(result.getError());

      expect(error, isA<SchemaValidationError>());
      expect(error.path, '#/user/id');
      expect(error.message, 'The value must be a valid Chrono ID.');
    });

    test('should use a custom refinement message', () {
      final result = Ack.string().chronoId(message: 'Use a Chrono ID.').safeParse('invalid');

      expect(result.getError().message, 'Use a Chrono ID.');
    });

    test('should retain Ack string type errors', () {
      final result = Ack.string().chronoId().safeParse(42);

      expect(result.getError(), isA<TypeMismatchError>());
    });

    test('should preserve existing constraints without changing the original schema', () {
      final original = Ack.string().minLength(20);
      final chronoId = original.chronoId(size: 16);
      const structurallyValid = '0000000000000000';
      const nonChronoLength20 = '____________________';

      expect(original.refinements, isEmpty);
      expect(original.safeParse(nonChronoLength20).isOk, isTrue);
      expect(original.safeParse(structurallyValid).isFail, isTrue);
      expect(chronoId.refinements, hasLength(1));
      expect(chronoId.safeParse(nonChronoLength20).isFail, isTrue);
      expect(chronoId.safeParse(structurallyValid).isFail, isTrue);
    });

    test('should retain validation after subsequent fluent constraints', () {
      final schema = Ack.string().chronoId(size: 16).maxLength(16);

      expect(schema.safeParse('0000000000000000').isOk, isTrue);
      expect(schema.safeParse('000000000000000_').isFail, isTrue);
    });

    test('should retain Ack optional and nullable behavior', () {
      final optionalObject = Ack.object({
        'id': Ack.string().chronoId().optional(),
      });
      final nullable = Ack.string().chronoId().nullable();

      expect(optionalObject.safeParse({}).getOrNull(), isEmpty);
      expect(nullable.safeParse(null).isOk, isTrue);
      expect(nullable.safeParse(null).getOrNull(), isNull);
    });
  });
}

SchemaError _leafError(SchemaError error) {
  var current = error;
  while (current is SchemaNestedError) {
    current = current.errors.single;
  }
  return current;
}

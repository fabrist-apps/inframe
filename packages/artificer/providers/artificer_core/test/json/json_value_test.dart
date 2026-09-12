import 'dart:convert';

import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('JsonValue', () {
    test('should snapshot nested Dart collections', () {
      final nested = <Object?>[1, true];
      final source = <String, Object?>{'nested': nested};

      final value = JsonValue.fromDart(source);
      nested.add('changed');
      source['later'] = null;

      expect(value.toDart(), {
        'nested': [1, true],
      });
      expect(() => (value.toDart()! as Map<String, Object?>)['x'] = 1, throwsUnsupportedError);
    });

    test('should parse and encode every JSON kind', () {
      const source = '{"null":null,"bool":true,"number":2.5,"string":"x","array":[1]}';

      final value = JsonValue.parse(source);

      expect(jsonDecode(value.encode()), jsonDecode(source));
    });

    test('should reject invalid wire values and cycles', () {
      final cycle = <Object?>[];
      cycle.add(cycle);

      expect(() => JsonValue.fromDart(double.nan), throwsArgumentError);
      expect(() => JsonValue.fromDart({1: 'value'}), throwsArgumentError);
      expect(() => JsonValue.fromDart(DateTime(2026)), throwsArgumentError);
      expect(() => JsonValue.fromDart(cycle), throwsArgumentError);
      expect(() => JsonValue.parse('{'), throwsFormatException);
    });
  });

  group('JsonObject', () {
    test('should reject a non-object root', () {
      expect(() => JsonObject.fromDart([1]), throwsArgumentError);
      expect(() => JsonObject.parse('[1]'), throwsFormatException);
    });
  });
}

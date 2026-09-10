import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('JsonPatch.fromJson', () {
    test('should report an empty patch', () {
      expect(JsonPatch.fromJson(<Object?>[]).isEmpty, isTrue);
    });

    test('should round-trip ordered operations and preserve explicit null', () {
      final wire = <Object?>[
        <String, Object?>{'op': 'add', 'path': '/a', 'value': null, 'ignored': true},
        <String, Object?>{
          'op': 'replace',
          'path': '/b',
          'value': <Object?>[1, 2],
        },
        <String, Object?>{'op': 'test', 'path': '/b/0', 'value': 1},
        <String, Object?>{'op': 'remove', 'path': '/c'},
      ];

      final patch = JsonPatch.fromJson(wire);

      expect(patch.operations, <Matcher>[
        isA<JsonAdd>().having((operation) => operation.value, 'value', isNull),
        isA<JsonReplace>(),
        isA<JsonTest>(),
        isA<JsonRemove>(),
      ]);
      expect(patch.toJson(), <Object?>[
        <String, Object?>{'op': 'add', 'path': '/a', 'value': null},
        <String, Object?>{
          'op': 'replace',
          'path': '/b',
          'value': <Object?>[1, 2],
        },
        <String, Object?>{'op': 'test', 'path': '/b/0', 'value': 1},
        <String, Object?>{'op': 'remove', 'path': '/c'},
      ]);
    });

    test('should reject malformed patch structure', () {
      final invalid = <Object?>[
        null,
        <String, Object?>{'path': ''},
        <String, Object?>{'op': 'unknown', 'path': ''},
        <String, Object?>{'op': 'add', 'path': ''},
        <Object?, Object?>{1: 'member', 'op': 'remove', 'path': ''},
        <String, Object?>{'op': 'remove', 'path': '#'},
      ];

      expect(() => JsonPatch.fromJson(null), throwsFormatException);
      for (final operation in invalid) {
        expect(() => JsonPatch.fromJson(<Object?>[operation]), throwsFormatException);
      }
    });

    test('should reject invalid wire values with FormatException', () {
      final cycle = <Object?>[];
      cycle.add(cycle);

      expect(
        () => JsonPatch.fromJson(<Object?>[
          <String, Object?>{'op': 'add', 'path': '', 'value': cycle},
        ]),
        throwsFormatException,
      );
    });
  });

  group('JsonPatch ownership', () {
    test('should snapshot operation values and operation order', () {
      final value = <String, Object?>{
        'items': <Object?>[1],
      };
      final operations = <JsonPatchOperation>[JsonAdd(JsonPointer.root, value)];
      final patch = JsonPatch(operations);

      (value['items']! as List<Object?>).add(2);
      operations.clear();

      expect(patch.operations, hasLength(1));
      expect((patch.operations.single as JsonAdd).value, <String, Object?>{
        'items': <Object?>[1],
      });
      expect(patch.operations.clear, throwsUnsupportedError);
      expect(
        () => ((patch.operations.single as JsonAdd).value! as Map<String, Object?>).clear(),
        throwsUnsupportedError,
      );
    });

    test('should return detached mutable wire data', () {
      final patch = JsonPatch([
        JsonAdd(JsonPointer.root, <String, Object?>{
          'items': <Object?>[1],
        }),
      ]);

      final first = patch.toJson();
      ((first.single['value']! as Map<String, Object?>)['items']! as List<Object?>).add(2);
      first.clear();

      expect(patch.toJson(), <Object?>[
        <String, Object?>{
          'op': 'add',
          'path': '',
          'value': <String, Object?>{
            'items': <Object?>[1],
          },
        },
      ]);
    });
  });
}

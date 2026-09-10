import 'dart:math';

import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('JsonPatch.diff', () {
    test('should transform a nested source into the target through wire data', () {
      final before = <String, Object?>{
        'name': 'draft',
        'metadata': <String, Object?>{'keep': true, 'remove': 1},
        'items': <Object?>[1, 2, 3],
      };
      final after = <String, Object?>{
        'name': 'published',
        'metadata': <String, Object?>{'keep': true, 'add': null},
        'items': <Object?>[1, 4],
      };

      final generated = JsonPatch.diff(before, after);
      final received = JsonPatch.fromJson(generated.toJson());

      expect(JsonPatch.patch(before, received), after);
      expect(before['name'], 'draft');
    });

    test('should emit no operations for JSON-equal values', () {
      expect(JsonPatch.diff(1, 1.0).isEmpty, isTrue);
      expect(
        JsonPatch.diff(
          <String, Object?>{
            'first': 1,
            'second': <Object?>[2.0],
          },
          <String, Object?>{
            'second': <Object?>[2],
            'first': 1.0,
          },
        ).isEmpty,
        isTrue,
      );
    });

    test('should process removals and common keys in source order before additions', () {
      final patch = JsonPatch.diff(
        <String, Object?>{
          'remove': 1,
          'common': <String, Object?>{'value': 1},
          'keep': true,
        },
        <String, Object?>{
          'keep': true,
          'common': <String, Object?>{'value': 2},
          'add': 3,
        },
      );

      expect(patch.toJson(), <Object?>[
        <String, Object?>{'op': 'remove', 'path': '/remove'},
        <String, Object?>{'op': 'replace', 'path': '/common/value', 'value': 2},
        <String, Object?>{'op': 'add', 'path': '/add', 'value': 3},
      ]);
    });

    test('should edit positional array gaps with live indices', () {
      expect(
        JsonPatch.diff(<Object?>['a', 'b', 'c', 'd'], <Object?>['a', 'changed']).toJson(),
        <Object?>[
          <String, Object?>{'op': 'replace', 'path': '/1', 'value': 'changed'},
          <String, Object?>{'op': 'remove', 'path': '/2'},
          <String, Object?>{'op': 'remove', 'path': '/2'},
        ],
      );
      expect(
        JsonPatch.diff(<Object?>['a'], <Object?>['a', 'b', 'c']).toJson(),
        <Object?>[
          <String, Object?>{'op': 'add', 'path': '/1', 'value': 'b'},
          <String, Object?>{'op': 'add', 'path': '/2', 'value': 'c'},
        ],
      );
    });

    test('should encode root absence transitions without encoding the marker', () {
      expect(JsonPatch.diff(JsonAbsent.instance, JsonAbsent.instance).isEmpty, isTrue);
      expect(JsonPatch.diff(JsonAbsent.instance, null).toJson(), <Object?>[
        <String, Object?>{'op': 'add', 'path': '', 'value': null},
      ]);
      expect(JsonPatch.diff(null, JsonAbsent.instance).toJson(), <Object?>[
        <String, Object?>{'op': 'remove', 'path': ''},
      ]);
    });

    test('should validate both complete input documents with located errors', () {
      expect(
        () => JsonPatch.diff(<Object?>[double.nan], null),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains(r'$before[0]'),
          ),
        ),
      );
      expect(
        () => JsonPatch.diff(null, <String, Object?>{'bad': Object()}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message.toString(),
            'message',
            contains(r'$after.bad'),
          ),
        ),
      );
    });

    test('should accept shared references and capture separate target occurrences', () {
      final shared = <Object?>[1];
      final after = <String, Object?>{'first': shared, 'second': shared};

      final result =
          JsonPatch.patch(<String, Object?>{}, JsonPatch.diff(<String, Object?>{}, after))!
              as Map<String, Object?>;
      (result['first']! as List<Object?>).add(2);

      expect(result['first'], <Object?>[1, 2]);
      expect(result['second'], <Object?>[1]);
      expect(shared, <Object?>[1]);
    });

    test('should round-trip generated valid document pairs', () {
      final random = Random(7421);

      for (var iteration = 0; iteration < 300; iteration++) {
        final before = _jsonValue(random, depth: 3);
        final after = _jsonValue(random, depth: 3);
        final patch = JsonPatch.diff(before, after);
        final received = JsonPatch.fromJson(patch.toJson());

        expect(JsonPatch.patch(before, received), after, reason: 'pair $iteration');
        expect(
          patch.operations,
          everyElement(anyOf(isA<JsonAdd>(), isA<JsonRemove>(), isA<JsonReplace>())),
        );
      }
    });
  });
}

Object? _jsonValue(Random random, {required int depth}) {
  final scalarChoice = random.nextInt(depth == 0 ? 5 : 7);
  return switch (scalarChoice) {
    0 => null,
    1 => random.nextBool(),
    2 => random.nextInt(20) - 10,
    3 => random.nextDouble() * 10,
    4 => 'value-${random.nextInt(8)}',
    5 => <Object?>[
      for (var index = 0; index < random.nextInt(4); index++) _jsonValue(random, depth: depth - 1),
    ],
    _ => <String, Object?>{
      for (var index = 0; index < random.nextInt(4); index++)
        'key-$index': _jsonValue(random, depth: depth - 1),
    },
  };
}

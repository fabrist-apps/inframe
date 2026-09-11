import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('JsonPatch.patch', () {
    group('ownership', () {
      test('should return detached mutable data and preserve shared input occurrences', () {
        final shared = <Object?>[1];
        final document = <String, Object?>{'first': shared, 'second': shared};

        final result = JsonPatch.patch(document, JsonPatch([]))! as Map<String, Object?>;
        (result['first']! as List<Object?>).add(2);

        expect(document, <String, Object?>{
          'first': <Object?>[1],
          'second': <Object?>[1],
        });
        expect(result['first'], <Object?>[1, 2]);
        expect(result['second'], <Object?>[1]);
      });

      test('should preserve input when a later operation fails', () {
        final document = <String, Object?>{'value': 1};
        final patch = JsonPatch([
          JsonReplace(JsonPointer.parse('/value'), 2),
          JsonRemove(JsonPointer.parse('/missing')),
        ]);

        expect(() => JsonPatch.patch(document, patch), throwsA(isA<JsonPatchException>()));
        expect(document, <String, Object?>{'value': 1});
      });
    });

    group('validation', () {
      test('should validate the complete document for an empty patch', () {
        final cycle = <Object?>[];
        cycle.add(cycle);
        final invalidValues = <Object?>[
          double.nan,
          double.infinity,
          Object(),
          <Object?, Object?>{1: 'value'},
          <Object?>[JsonAbsent.instance],
          cycle,
        ];

        for (final value in invalidValues) {
          expect(
            () => JsonPatch.patch(value, JsonPatch([])),
            throwsA(
              isA<ArgumentError>().having(
                (error) => error.message.toString(),
                'message',
                contains(r'$'),
              ),
            ),
          );
        }
      });

      test('should reject invalid programmatic operation payloads with their location', () {
        expect(
          () => JsonAdd(JsonPointer.root, <Object?>[double.nan]),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message.toString(),
              'message',
              contains(r'$value[0]'),
            ),
          ),
        );
        expect(() => JsonTest(JsonPointer.root, JsonAbsent.instance), throwsArgumentError);
      });
    });

    group('paths and failures', () {
      test('should overwrite an object member with add', () {
        expect(
          JsonPatch.patch(
            <String, Object?>{'value': 'before'},
            JsonPatch([JsonAdd(JsonPointer.parse('/value'), 'after')]),
          ),
          <String, Object?>{'value': 'after'},
        );
      });

      test('should treat numeric object keys literally', () {
        final result = JsonPatch.patch(
          <String, Object?>{'01': 'before'},
          JsonPatch([JsonReplace(JsonPointer.parse('/01'), 'after')]),
        );

        expect(result, <String, Object?>{'01': 'after'});
      });

      test('should reject invalid array tokens and indices', () {
        for (final path in <String>['/-', '/01', '/+1', '/-1', '/2']) {
          _expectFailure(
            () => JsonPatch.patch(<Object?>[0], JsonPatch([JsonRemove(JsonPointer.parse(path))])),
            reason: JsonPatchFailure.invalidArrayIndex,
            path: path,
          );
        }
      });

      test('should distinguish missing targets from wrong container types', () {
        _expectFailure(
          () => JsonPatch.patch(
            <String, Object?>{},
            JsonPatch([JsonAdd(JsonPointer.parse('/missing/child'), 1)]),
          ),
          reason: JsonPatchFailure.missingTarget,
          path: '/missing/child',
        );
        _expectFailure(
          () => JsonPatch.patch(
            <String, Object?>{},
            JsonPatch([JsonReplace(JsonPointer.parse('/missing'), 1)]),
          ),
          reason: JsonPatchFailure.missingTarget,
          path: '/missing',
        );
        _expectFailure(
          () => JsonPatch.patch(
            <String, Object?>{'scalar': 1},
            JsonPatch([JsonAdd(JsonPointer.parse('/scalar/child'), 2)]),
          ),
          reason: JsonPatchFailure.wrongContainerType,
          path: '/scalar/child',
        );
      });

      test('should report the zero-based operation index for a failed test', () {
        try {
          JsonPatch.patch(
            <String, Object?>{'value': 1},
            JsonPatch([
              JsonAdd(JsonPointer.parse('/added'), true),
              JsonTest(JsonPointer.parse('/value'), 2),
            ]),
          );
          fail('Expected JsonPatchException.');
        } on JsonPatchException catch (error) {
          expect(error.operationIndex, 1);
          expect(error.path, JsonPointer.parse('/value'));
          expect(error.reason, JsonPatchFailure.testFailed);
          expect(error.message, isNotEmpty);
        }
      });
    });

    group('JSON equality', () {
      test('should ignore map order and compare numbers numerically', () {
        final document = <String, Object?>{
          'value': <String, Object?>{
            'first': 1,
            'second': <Object?>[2.0],
          },
        };
        final expected = <String, Object?>{
          'second': <Object?>[2],
          'first': 1.0,
        };

        expect(
          JsonPatch.patch(
            document,
            JsonPatch([JsonTest(JsonPointer.parse('/value'), expected)]),
          ),
          document,
        );
      });
    });

    group('root absence', () {
      test('should preserve an absent root for an empty patch', () {
        expect(JsonPatch.patch(JsonAbsent.instance, JsonPatch([])), same(JsonAbsent.instance));
      });

      test('should add, replace, remove, and recreate the root', () {
        expect(
          JsonPatch.patch(JsonAbsent.instance, JsonPatch([JsonAdd(JsonPointer.root, null)])),
          isNull,
        );
        expect(
          JsonPatch.patch(null, JsonPatch([JsonReplace(JsonPointer.root, 1)])),
          1,
        );
        expect(
          JsonPatch.patch(1, JsonPatch([const JsonRemove(JsonPointer.root)])),
          same(JsonAbsent.instance),
        );
        expect(
          JsonPatch.patch(
            <String, Object?>{'old': true},
            JsonPatch([
              const JsonRemove(JsonPointer.root),
              JsonAdd(JsonPointer.root, <String, Object?>{'new': true}),
            ]),
          ),
          <String, Object?>{'new': true},
        );
      });

      test('should fail operations that require an existing root', () {
        final operations = <JsonPatchOperation>[
          const JsonRemove(JsonPointer.root),
          JsonReplace(JsonPointer.root, null),
          JsonTest(JsonPointer.root, null),
          JsonAdd(JsonPointer.parse('/child'), 1),
        ];

        for (final operation in operations) {
          _expectFailure(
            () => JsonPatch.patch(JsonAbsent.instance, JsonPatch([operation])),
            reason: JsonPatchFailure.missingTarget,
            path: operation.path.toString(),
          );
        }
      });
    });

    test('should insert and append array values without deduplication', () {
      final patch = JsonPatch([JsonAdd(JsonPointer.parse('/0'), 'new')]);
      final once = JsonPatch.patch(<Object?>['old'], patch);
      final twice = JsonPatch.patch(once, patch);

      expect(once, <Object?>['new', 'old']);
      expect(twice, <Object?>['new', 'new', 'old']);
      expect(
        JsonPatch.patch(once, JsonPatch([JsonAdd(JsonPointer.parse('/-'), 'last')])),
        <Object?>['new', 'old', 'last'],
      );
    });
  });
}

void _expectFailure(
  void Function() operation, {
  required JsonPatchFailure reason,
  required String path,
}) {
  expect(
    operation,
    throwsA(
      isA<JsonPatchException>()
          .having((error) => error.reason, 'reason', reason)
          .having((error) => error.path.toString(), 'path', path),
    ),
  );
}

import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('JsonPatch move and copy', () {
    test('should resolve a same-array move destination after removal', () {
      final result = JsonPatch.patch(
        <Object?>['a', 'b', 'c', 'd'],
        JsonPatch([
          JsonMove(from: JsonPointer.parse('/1'), path: JsonPointer.parse('/3')),
        ]),
      );

      expect(result, <Object?>['a', 'c', 'd', 'b']);
    });

    test('should move backward and append using post-removal indices', () {
      expect(
        JsonPatch.patch(
          <Object?>['a', 'b', 'c', 'd'],
          JsonPatch([
            JsonMove(from: JsonPointer.parse('/3'), path: JsonPointer.parse('/1')),
            JsonMove(from: JsonPointer.parse('/0'), path: JsonPointer.parse('/-')),
          ]),
        ),
        <Object?>['d', 'b', 'c', 'a'],
      );
    });

    test('should copy the root into a descendant without aliases or cycles', () {
      final result =
          JsonPatch.patch(
                <String, Object?>{
                  'container': <String, Object?>{},
                  'value': <Object?>[1],
                },
                JsonPatch([
                  JsonCopy(from: JsonPointer.root, path: JsonPointer.parse('/container/copy')),
                ]),
              )!
              as Map<String, Object?>;

      final copied =
          (result['container']! as Map<String, Object?>)['copy']! as Map<String, Object?>;
      (copied['value']! as List<Object?>).add(2);

      expect(result['value'], <Object?>[1]);
      expect(copied['value'], <Object?>[1, 2]);
      expect(copied['container']! as Map<String, Object?>, isEmpty);
    });

    test('should create independent copies from one source', () {
      final result =
          JsonPatch.patch(
                <String, Object?>{
                  'source': <Object?>[1],
                },
                JsonPatch([
                  JsonCopy(from: JsonPointer.parse('/source'), path: JsonPointer.parse('/first')),
                  JsonCopy(from: JsonPointer.parse('/source'), path: JsonPointer.parse('/second')),
                ]),
              )!
              as Map<String, Object?>;

      (result['first']! as List<Object?>).add(2);
      expect(result['source'], <Object?>[1]);
      expect(result['second'], <Object?>[1]);
    });

    test('should resolve a missing source before move validation or destination traversal', () {
      _expectFailure(
        () => JsonPatch.patch(
          <String, Object?>{},
          JsonPatch([
            JsonMove(
              from: JsonPointer.parse('/missing'),
              path: JsonPointer.parse('/missing/child'),
            ),
          ]),
        ),
        reason: JsonPatchFailure.missingTarget,
        path: '/missing',
      );
      _expectFailure(
        () => JsonPatch.patch(
          <String, Object?>{},
          JsonPatch([
            JsonCopy(from: JsonPointer.parse('/missing'), path: JsonPointer.parse('/also/missing')),
          ]),
        ),
        reason: JsonPatchFailure.missingTarget,
        path: '/missing',
      );
    });

    test('should check source existence for same-path moves', () {
      expect(
        JsonPatch.patch(
          <String, Object?>{'value': 1},
          JsonPatch([
            JsonMove(from: JsonPointer.parse('/value'), path: JsonPointer.parse('/value')),
          ]),
        ),
        <String, Object?>{'value': 1},
      );
      _expectFailure(
        () => JsonPatch.patch(
          <String, Object?>{},
          JsonPatch([
            JsonMove(from: JsonPointer.parse('/missing'), path: JsonPointer.parse('/missing')),
          ]),
        ),
        reason: JsonPatchFailure.missingTarget,
        path: '/missing',
      );
    });

    test('should reject decoded descendant destinations without changing input', () {
      final document = <String, Object?>{
        'a/b': <String, Object?>{'value': 1},
      };

      _expectFailure(
        () => JsonPatch.patch(
          document,
          JsonPatch([
            JsonMove(from: JsonPointer.parse('/a~1b'), path: JsonPointer.parse('/a~1b/child')),
          ]),
        ),
        reason: JsonPatchFailure.invalidMove,
        path: '/a~1b/child',
      );
      expect(document, <String, Object?>{
        'a/b': <String, Object?>{'value': 1},
      });

      expect(
        JsonPatch.patch(
          <String, Object?>{'a': 1, 'ab': <String, Object?>{}},
          JsonPatch([
            JsonMove(from: JsonPointer.parse('/a'), path: JsonPointer.parse('/ab/value')),
          ]),
        ),
        <String, Object?>{
          'ab': <String, Object?>{'value': 1},
        },
      );
    });

    test('should keep caller data unchanged when a move destination fails after removal', () {
      final document = <String, Object?>{'source': 1};

      _expectFailure(
        () => JsonPatch.patch(
          document,
          JsonPatch([
            JsonAdd(JsonPointer.parse('/before'), true),
            JsonMove(from: JsonPointer.parse('/source'), path: JsonPointer.parse('/missing/child')),
          ]),
        ),
        reason: JsonPatchFailure.missingTarget,
        path: '/missing/child',
        operationIndex: 1,
      );
      expect(document, <String, Object?>{'source': 1});
    });

    test('should apply root move and copy rules', () {
      final document = <String, Object?>{
        'child': <Object?>[1],
      };

      final movedRoot = JsonPatch.patch(
        document,
        JsonPatch([const JsonMove(from: JsonPointer.root, path: JsonPointer.root)]),
      );
      expect(movedRoot, document);
      expect(identical(movedRoot, document), isFalse);

      final copiedRoot = JsonPatch.patch(
        document,
        JsonPatch([const JsonCopy(from: JsonPointer.root, path: JsonPointer.root)]),
      );
      expect(copiedRoot, document);
      expect(identical(copiedRoot, document), isFalse);

      expect(
        JsonPatch.patch(
          document,
          JsonPatch([JsonMove(from: JsonPointer.parse('/child'), path: JsonPointer.root)]),
        ),
        <Object?>[1],
      );
      expect(
        JsonPatch.patch(
          document,
          JsonPatch([JsonCopy(from: JsonPointer.parse('/child'), path: JsonPointer.root)]),
        ),
        <Object?>[1],
      );

      _expectFailure(
        () => JsonPatch.patch(
          document,
          JsonPatch([JsonMove(from: JsonPointer.root, path: JsonPointer.parse('/child/new'))]),
        ),
        reason: JsonPatchFailure.invalidMove,
        path: '/child/new',
      );
      for (final operation in <JsonPatchOperation>[
        const JsonMove(from: JsonPointer.root, path: JsonPointer.root),
        const JsonCopy(from: JsonPointer.root, path: JsonPointer.root),
      ]) {
        _expectFailure(
          () => JsonPatch.patch(JsonAbsent.instance, JsonPatch([operation])),
          reason: JsonPatchFailure.missingTarget,
          path: '',
        );
      }
    });

    test('should round-trip named move and copy operations through wire data', () {
      final patch = JsonPatch([
        JsonMove(from: JsonPointer.parse('/from'), path: JsonPointer.parse('/to')),
        JsonCopy(from: JsonPointer.parse('/to'), path: JsonPointer.parse('/copy')),
      ]);

      final received = JsonPatch.fromJson(patch.toJson());

      expect(received.toJson(), patch.toJson());
      expect(received.operations.first, isA<JsonMove>());
      expect(received.operations.last, isA<JsonCopy>());
      expect(
        () => JsonPatch.fromJson(<Object?>[
          <String, Object?>{'op': 'move', 'path': '/to'},
        ]),
        throwsFormatException,
      );
      expect(
        () => JsonPatch.fromJson(<Object?>[
          <String, Object?>{'op': 'copy', 'from': 1, 'path': '/to'},
        ]),
        throwsFormatException,
      );
    });
  });
}

void _expectFailure(
  void Function() operation, {
  required JsonPatchFailure reason,
  required String path,
  int operationIndex = 0,
}) {
  expect(
    operation,
    throwsA(
      isA<JsonPatchException>()
          .having((error) => error.operationIndex, 'operationIndex', operationIndex)
          .having((error) => error.reason, 'reason', reason)
          .having((error) => error.path.toString(), 'path', path),
    ),
  );
}

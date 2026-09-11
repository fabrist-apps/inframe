import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('JsonPatch.diff array alignment', () {
    test('should preserve an insertion in the title-and-tags example', () {
      final before = <String, Object?>{
        'title': 'Draft',
        'tags': <Object?>['dart', 'flutter'],
      };
      final after = <String, Object?>{
        'title': 'Published',
        'tags': <Object?>['dart', 'json', 'flutter'],
      };

      expect(JsonPatch.diff(before, after).toJson(), <Object?>[
        <String, Object?>{'op': 'replace', 'path': '/title', 'value': 'Published'},
        <String, Object?>{'op': 'add', 'path': '/tags/1', 'value': 'json'},
      ]);
    });

    test('should use the source-advancing tie-break for duplicate values', () {
      expect(JsonPatch.diff(<Object?>[1, 2, 1], <Object?>[1, 1, 2]).toJson(), <Object?>[
        <String, Object?>{'op': 'remove', 'path': '/1'},
        <String, Object?>{'op': 'add', 'path': '/2', 'value': 2},
      ]);
    });

    test('should include boundary cells in the table capacity', () {
      final atLimit = _shiftedIntegers(sourceLength: 255, targetLength: 255);
      final aboveLimit = _shiftedIntegers(sourceLength: 256, targetLength: 255);

      expect(JsonPatch.diff(atLimit.source, atLimit.target).operations.first, isA<JsonAdd>());
      expect(
        JsonPatch.diff(aboveLimit.source, aboveLimit.target).operations.first,
        isA<JsonReplace>(),
      );
    });

    test('should let later arrays align after one array exceeds only the table limit', () {
      final large = _shiftedIntegers(sourceLength: 256, targetLength: 255);
      final small = _shiftedIntegers(sourceLength: 20, targetLength: 20);
      final patch = JsonPatch.diff(
        <String, Object?>{'large': large.source, 'small': small.source},
        <String, Object?>{'large': large.target, 'small': small.target},
      );

      expect(_operationAt(patch, '/large/0'), isA<JsonReplace>());
      expect(_operationAt(patch, '/small/0'), isA<JsonAdd>());
    });

    test('should charge strings and reconstruction checks before accepting matches', () {
      final source = <Object?>[
        for (var index = 0; index < 70; index++) _fixedWidthString(index),
      ];
      final target = <Object?>[
        _fixedWidthString(1000),
        ...source.take(69),
      ];
      final later = _shiftedIntegers(sourceLength: 20, targetLength: 20);
      final patch = JsonPatch.diff(
        <String, Object?>{'expensive': source, 'later': later.source},
        <String, Object?>{'expensive': target, 'later': later.target},
      );

      expect(_operationAt(patch, '/expensive/0'), isA<JsonReplace>());
      expect(_operationAt(patch, '/later/0'), isA<JsonReplace>());
    });

    test('should charge nested comparisons and map-key lookups', () {
      final key = List<String>.filled(100, 'k').join();
      final source = <Object?>[
        for (var index = 0; index < 100; index++) <String, Object?>{key: index},
      ];
      final target = <Object?>[
        <String, Object?>{key: -1},
        ...source.take(99),
      ];

      expect(JsonPatch.diff(source, target).operations.first, isA<JsonReplace>());

      final shortSource = <Object?>[
        for (var index = 0; index < 100; index++) <String, Object?>{'k': index},
      ];
      final shortTarget = <Object?>[
        <String, Object?>{'k': -1},
        ...shortSource.take(99),
      ];
      expect(JsonPatch.diff(shortSource, shortTarget).operations.first, isA<JsonAdd>());
    });

    test('should charge prefix comparisons and disable later speculation on exhaustion', () {
      final repeated = _fixedWidthString(1);
      final expensiveSource = <Object?>[...List<Object?>.filled(5000, repeated), 'source'];
      final expensiveTarget = <Object?>[...List<Object?>.filled(5000, repeated), 'target'];
      final later = _shiftedIntegers(sourceLength: 20, targetLength: 20);
      final patch = JsonPatch.diff(
        <String, Object?>{'expensive': expensiveSource, 'later': later.source},
        <String, Object?>{'expensive': expensiveTarget, 'later': later.target},
      );

      expect(_operationAt(patch, '/later/0'), isA<JsonReplace>());
    });

    test('should charge suffix comparisons and disable later speculation on exhaustion', () {
      final repeated = _fixedWidthString(1);
      final expensiveSource = <Object?>['source', ...List<Object?>.filled(5000, repeated)];
      final expensiveTarget = <Object?>['target', ...List<Object?>.filled(5000, repeated)];
      final later = _shiftedIntegers(sourceLength: 20, targetLength: 20);
      final patch = JsonPatch.diff(
        <String, Object?>{'expensive': expensiveSource, 'later': later.source},
        <String, Object?>{'expensive': expensiveTarget, 'later': later.target},
      );

      expect(_operationAt(patch, '/later/0'), isA<JsonReplace>());
    });

    test('should recursively edit nested gaps around aligned values', () {
      final source = <Object?>[
        <Object?>[1, 2, 3],
        'anchor',
        <String, Object?>{
          'items': <Object?>['a', 'b'],
        },
        true,
      ];
      final target = <Object?>[
        <Object?>[1, 3],
        'anchor',
        <String, Object?>{
          'items': <Object?>['a', 'new', 'b'],
        },
        true,
      ];

      final patch = JsonPatch.diff(source, target);

      expect(patch.toJson(), <Object?>[
        <String, Object?>{'op': 'remove', 'path': '/0/1'},
        <String, Object?>{'op': 'add', 'path': '/2/items/1', 'value': 'new'},
      ]);
      expect(JsonPatch.patch(source, patch), target);
    });
  });
}

({List<Object?> source, List<Object?> target}) _shiftedIntegers({
  required int sourceLength,
  required int targetLength,
}) {
  final source = <Object?>[for (var index = 0; index < sourceLength; index++) index];
  final target = <Object?>[-1, ...source.take(targetLength - 1)];
  return (source: source, target: target);
}

String _fixedWidthString(int value) => '$value'.padLeft(100, 'x');

JsonPatchOperation _operationAt(JsonPatch patch, String path) =>
    patch.operations.firstWhere((operation) => operation.path.toString() == path);

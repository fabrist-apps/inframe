import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 6901 examples', () {
    test('should resolve escaped and empty reference tokens', () {
      final document = <String, Object?>{
        'foo': <Object?>['bar', 'baz'],
        '': 0,
        'a/b': 1,
        'c%d': 2,
        'e^f': 3,
        'g|h': 4,
        r'i\j': 5,
        'k"l': 6,
        ' ': 7,
        'm~n': 8,
      };
      final expectedByPointer = <String, Object?>{
        '/foo': <Object?>['bar', 'baz'],
        '/foo/0': 'bar',
        '/': 0,
        '/a~1b': 1,
        '/c%d': 2,
        '/e^f': 3,
        '/g|h': 4,
        r'/i\j': 5,
        '/k"l': 6,
        '/ ': 7,
        '/m~0n': 8,
      };

      final patch = JsonPatch([
        for (final entry in expectedByPointer.entries)
          JsonTest(JsonPointer.parse(entry.key), entry.value),
      ]);

      expect(JsonPatch.patch(document, patch), document);
    });
  });

  group('RFC 6902 examples', () {
    test('should apply all operation forms sequentially', () {
      final document = <String, Object?>{
        'foo': <Object?>['bar', 'baz'],
        'object': <String, Object?>{'source': 'value'},
      };
      final patch = JsonPatch.fromJson(<Object?>[
        <String, Object?>{'op': 'add', 'path': '/foo/1', 'value': 'qux'},
        <String, Object?>{'op': 'remove', 'path': '/foo/0'},
        <String, Object?>{'op': 'replace', 'path': '/foo/1', 'value': 'boo'},
        <String, Object?>{'op': 'copy', 'from': '/object/source', 'path': '/copied'},
        <String, Object?>{'op': 'move', 'from': '/object/source', 'path': '/moved'},
        <String, Object?>{'op': 'test', 'path': '/moved', 'value': 'value'},
      ]);

      expect(JsonPatch.patch(document, patch), <String, Object?>{
        'foo': <Object?>['qux', 'boo'],
        'object': <String, Object?>{},
        'copied': 'value',
        'moved': 'value',
      });
    });
  });
}

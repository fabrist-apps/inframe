import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('JsonPointer', () {
    test('should distinguish the root from an empty object key', () {
      expect(JsonPointer.parse(''), JsonPointer.root);
      expect(JsonPointer.root.toString(), isEmpty);
      expect(JsonPointer.parse('/').segments, <String>['']);
      expect(JsonPointer.parse('/').toString(), '/');
    });

    test('should decode and encode escaped segments in RFC order', () {
      final pointer = JsonPointer.parse('/a~1b/~0/~01');

      expect(pointer.segments, <String>['a/b', '~', '~1']);
      expect(pointer.toString(), '/a~1b/~0/~01');
    });

    test('should snapshot segments and create children with value equality', () {
      final segments = <String>['a/b'];
      final pointer = JsonPointer.fromSegments(segments);
      segments[0] = 'changed';

      expect(pointer.child('~key'), JsonPointer.parse('/a~1b/~0key'));
      expect(pointer.child('~key').hashCode, JsonPointer.parse('/a~1b/~0key').hashCode);
      expect(() => pointer.segments.add('mutable'), throwsUnsupportedError);
    });

    test('should reject URI fragments and malformed escapes', () {
      for (final pointer in <String>['#', '#/key', '/~', '/~2']) {
        expect(() => JsonPointer.parse(pointer), throwsFormatException, reason: pointer);
      }
    });
  });
}

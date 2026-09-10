import 'package:json_patch/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('JsonPatch', () {
    test('should apply add, replace, test, and remove operations in order', () {
      final document = <String, Object?>{
        'name': 'draft',
        'tags': <Object?>['dart'],
      };
      final patch = JsonPatch([
        JsonAdd(JsonPointer.parse('/tags/-'), 'json'),
        JsonReplace(JsonPointer.parse('/name'), 'published'),
        JsonTest(JsonPointer.parse('/tags/1'), 'json'),
        JsonRemove(JsonPointer.parse('/tags/0')),
      ]);

      expect(JsonPatch.patch(document, patch), <String, Object?>{
        'name': 'published',
        'tags': <Object?>['json'],
      });
      expect(document['name'], 'draft');
    });
  });
}

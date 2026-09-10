import 'dart:convert';

import 'package:json_patch/json_patch.dart';

void main() {
  final before = <String, Object?>{
    'title': 'Draft',
    'tags': <Object?>['dart', 'flutter'],
  };
  final after = <String, Object?>{
    'title': 'Published',
    'tags': <Object?>['dart', 'json', 'flutter'],
  };

  final typed = JsonPatch(<JsonPatchOperation>[
    JsonTest(JsonPointer.parse('/title'), 'Draft'),
  ]);
  final verified = JsonPatch.patch(before, typed);
  final patch = JsonPatch.diff(verified, after);
  final received = JsonPatch.fromJson(jsonDecode(jsonEncode(patch.toJson())));
  final updated = JsonPatch.patch(before, received);

  if (jsonEncode(updated) != jsonEncode(after)) {
    throw StateError('The applied patch did not produce the target document.');
  }

  final removedRoot = JsonPatch.patch(
    before,
    JsonPatch(<JsonPatchOperation>[const JsonRemove(JsonPointer.root)]),
  );
  if (!identical(removedRoot, JsonAbsent.instance)) {
    throw StateError('Removing the root must return JsonAbsent.instance.');
  }
  final recreatedRoot = JsonPatch.patch(
    removedRoot,
    JsonPatch(<JsonPatchOperation>[JsonAdd(JsonPointer.root, 'created')]),
  );
  if (recreatedRoot != 'created') {
    throw StateError('Adding at an absent root must create the document.');
  }

  try {
    JsonPatch.patch(
      before,
      JsonPatch(<JsonPatchOperation>[JsonRemove(JsonPointer.parse('/missing'))]),
    );
    throw StateError('Removing a missing member must fail.');
  } on JsonPatchException catch (error) {
    if (error.operationIndex != 0 ||
        error.path != JsonPointer.parse('/missing') ||
        error.reason != JsonPatchFailure.missingTarget) {
      throw StateError('Unexpected structured patch failure: $error');
    }
  }

  // This command-line example deliberately prints its result for the reader.
  // ignore: avoid_print
  print(jsonEncode(patch.toJson()));
}

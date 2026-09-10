# JSON Patch

`json_patch` computes changes between ordinary Dart JSON values and applies RFC 6902 patches
without changing caller-owned data. It is an internal Inframe package and is not published.

## Use the package

Import the package and call the static methods on `JsonPatch`:

```dart
import 'package:json_patch/json_patch.dart';

final before = <String, Object?>{
  'title': 'Draft',
  'tags': <Object?>['dart', 'flutter'],
};
final after = <String, Object?>{
  'title': 'Published',
  'tags': <Object?>['dart', 'json', 'flutter'],
};

final patch = JsonPatch.diff(before, after);
final updated = JsonPatch.patch(before, patch);
```

`updated` is JSON-equal to `after`. `before` remains unchanged, and mutable containers in the
result do not share mutable state with the input or patch payloads.

Use `fromJson` and `toJson` at a wire boundary:

```dart
final received = JsonPatch.fromJson(decodedMessage);
final result = JsonPatch.patch(document, received);
final encoded = patch.toJson();
```

Malformed patch data and pointer strings throw `FormatException`. Invalid programmatic JSON values
throw a located `ArgumentError`. An operation that cannot be applied throws `JsonPatchException`;
branch on its `reason`, `operationIndex`, and `path` rather than its diagnostic `message`.

## Root absence

`JsonAbsent.instance` represents a missing document root. It differs from JSON `null`, which is a
present value. A root add creates or replaces a document, and a root remove returns the sentinel.
The sentinel cannot occur inside JSON containers or operation values and has no wire encoding.

## Ownership and diff behavior

Operation constructors capture deeply immutable payloads. `JsonPatch.patch` validates and copies
the input once, applies operations to that private tree, and returns detached mutable data only on
success. `toJson` also returns detached mutable data.

Generated diffs use add, remove, and replace. Object output follows input map iteration order. Array
alignment is deterministic and bounded; exceeding its storage or shared work limit uses positional
comparison. The API does not promise a minimal patch or canonical operation order across different
map orderings or package revisions.

Patch application does not retry or deduplicate work. Applying an array insertion twice can insert
the value twice; consumers that need preconditions can include test operations.

Run the example from the repository root:

```sh
dart run packages/json_patch/example/json_patch_example.dart
```

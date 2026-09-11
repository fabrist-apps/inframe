/// JSON diffing and RFC 6902 patch application.
library;

import 'dart:collection';

import 'package:meta/meta.dart';

part 'src/json_patch_apply.dart';
part 'src/json_patch_exception.dart';
part 'src/json_patch_operation.dart';
part 'src/json_diff.dart';
part 'src/json_pointer.dart';
part 'src/json_value.dart';

/// An immutable sequence of JSON Patch operations.
final class JsonPatch {
  /// Captures [operations] in application order.
  new(Iterable<JsonPatchOperation> operations)
    : operations = List<JsonPatchOperation>.unmodifiable(operations);

  /// Parses an RFC 6902 patch document.
  ///
  /// Unknown operation members are ignored. Malformed operations, unknown
  /// operation names, and invalid JSON values throw [FormatException].
  factory fromJson(Object? json) {
    if (json is! List<Object?>) {
      throw const FormatException('A JSON Patch document must be an array.');
    }

    return JsonPatch(<JsonPatchOperation>[
      for (var index = 0; index < json.length; index++) _operationFromJson(json[index], index),
    ]);
  }

  /// The operations in application order.
  final List<JsonPatchOperation> operations;

  /// Whether this patch has no operations.
  bool get isEmpty => operations.isEmpty;

  /// Computes a patch that transforms [before] into [after].
  static JsonPatch diff(Object? before, Object? after) => _JsonDiffer(before, after).run();

  /// Applies [patch] without changing [document].
  ///
  /// Invalid programmatic JSON throws [ArgumentError]. An operation that
  /// cannot be applied throws [JsonPatchException].
  static Object? patch(Object? document, JsonPatch patch) =>
      _PatchApplication(document, patch).run();

  /// Returns a detached, mutable RFC 6902 patch document.
  List<Map<String, Object?>> toJson() => <Map<String, Object?>>[
    for (final operation in operations) _operationToJson(operation),
  ];
}

JsonPatchOperation _operationFromJson(Object? json, int index) {
  if (json is! Map<Object?, Object?>) {
    throw FormatException('Operation $index must be an object.');
  }
  final frozenOperation = _freezeWireJson(
    json,
    location:
        r'$patch'
        '[$index]',
  );
  final operation = frozenOperation! as Map<String, Object?>;

  final operationName = _requiredWireString(operation, 'op', index);
  final path = JsonPointer.parse(_requiredWireString(operation, 'path', index));
  switch (operationName) {
    case 'add':
      return JsonAdd._frozen(path, _requiredWireValue(operation, 'value', index));
    case 'remove':
      return JsonRemove(path);
    case 'replace':
      return JsonReplace._frozen(path, _requiredWireValue(operation, 'value', index));
    case 'test':
      return JsonTest._frozen(path, _requiredWireValue(operation, 'value', index));
    case 'move':
      return JsonMove(
        from: JsonPointer.parse(_requiredWireString(operation, 'from', index)),
        path: path,
      );
    case 'copy':
      return JsonCopy(
        from: JsonPointer.parse(_requiredWireString(operation, 'from', index)),
        path: path,
      );
    default:
      throw FormatException('Operation $index has unknown op "$operationName".');
  }
}

String _requiredWireString(Map<String, Object?> json, String member, int index) {
  final value = json[member];
  if (value is! String) {
    throw FormatException('Operation $index requires a string "$member" member.');
  }
  return value;
}

Object? _requiredWireValue(Map<String, Object?> json, String member, int index) {
  if (!json.containsKey(member)) {
    throw FormatException('Operation $index requires a "$member" member.');
  }
  return json[member];
}

Map<String, Object?> _operationToJson(JsonPatchOperation operation) {
  return switch (operation) {
    JsonAdd(:final path, :final value) => <String, Object?>{
      'op': 'add',
      'path': path.toString(),
      'value': _mutableJsonCopy(value),
    },
    JsonRemove(:final path) => <String, Object?>{'op': 'remove', 'path': path.toString()},
    JsonReplace(:final path, :final value) => <String, Object?>{
      'op': 'replace',
      'path': path.toString(),
      'value': _mutableJsonCopy(value),
    },
    JsonTest(:final path, :final value) => <String, Object?>{
      'op': 'test',
      'path': path.toString(),
      'value': _mutableJsonCopy(value),
    },
    JsonMove(:final from, :final path) => <String, Object?>{
      'op': 'move',
      'from': from.toString(),
      'path': path.toString(),
    },
    JsonCopy(:final from, :final path) => <String, Object?>{
      'op': 'copy',
      'from': from.toString(),
      'path': path.toString(),
    },
  };
}

part of '../json_patch.dart';

/// One operation in a JSON Patch document.
sealed class JsonPatchOperation {
  const new(this.path);

  /// The operation destination.
  final JsonPointer path;
}

/// Adds a value at [path].
final class JsonAdd extends JsonPatchOperation {
  /// Creates an add operation and captures an immutable copy of [value].
  new(super.path, Object? value) : value = _freezeJson(value, location: r'$value');

  // Internal callers have already captured a deeply immutable JSON value.
  const new _frozen(super.path, this.value);

  /// The value to add.
  final Object? value;
}

/// Removes the value at [path].
final class JsonRemove extends JsonPatchOperation {
  /// Creates a remove operation.
  const new(super.path);
}

/// Replaces the value at [path].
final class JsonReplace extends JsonPatchOperation {
  /// Creates a replace operation and captures an immutable copy of [value].
  new(super.path, Object? value) : value = _freezeJson(value, location: r'$value');

  // Internal callers have already captured a deeply immutable JSON value.
  const new _frozen(super.path, this.value);

  /// The replacement value.
  final Object? value;
}

/// Verifies the value at [path].
final class JsonTest extends JsonPatchOperation {
  /// Creates a test operation and captures an immutable copy of [value].
  new(super.path, Object? value) : value = _freezeJson(value, location: r'$value');

  // Internal callers have already captured a deeply immutable JSON value.
  const new _frozen(super.path, this.value);

  /// The expected value.
  final Object? value;
}

/// Moves the value at [from] to [path].
final class JsonMove extends JsonPatchOperation {
  /// Creates a move operation.
  const new({required this.from, required JsonPointer path}) : super(path);

  /// The source pointer.
  final JsonPointer from;
}

/// Copies the value at [from] to [path].
final class JsonCopy extends JsonPatchOperation {
  /// Creates a copy operation.
  const new({required this.from, required JsonPointer path}) : super(path);

  /// The source pointer.
  final JsonPointer from;
}

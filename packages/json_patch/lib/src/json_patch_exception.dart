part of '../json_patch.dart';

/// The structured reason an operation could not be applied.
enum JsonPatchFailure {
  /// The target, parent, or source does not exist.
  missingTarget,

  /// An array segment is malformed, forbidden, or out of range.
  invalidArrayIndex,

  /// Traversal tried to descend through a scalar or null.
  wrongContainerType,

  /// A test operation found a different value.
  testFailed,

  /// A move destination is inside its source.
  invalidMove,
}

/// Describes why a JSON Patch operation failed.
final class JsonPatchException implements Exception {
  /// Creates a structured patch application failure.
  const new({
    required this.operationIndex,
    required this.path,
    required this.reason,
    required this.message,
  });

  /// The zero-based index of the failing operation.
  final int operationIndex;

  /// The failing source or destination pointer.
  final JsonPointer path;

  /// The stable failure category.
  final JsonPatchFailure reason;

  /// A diagnostic description of the failure.
  final String message;

  @override
  String toString() => 'JsonPatchException($operationIndex, $path, $reason): $message';
}

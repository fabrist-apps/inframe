part of '../json_patch.dart';

final class _PatchApplication {
  new(Object? document, this.patch)
    : root = identical(document, JsonAbsent.instance)
          ? JsonAbsent.instance
          : _mutableJsonCopy(document);

  final JsonPatch patch;
  Object? root;

  Object? run() {
    for (var index = 0; index < patch.operations.length; index++) {
      final operation = patch.operations[index];
      switch (operation) {
        case JsonAdd():
          _insert(
            operation.path,
            _mutableJsonCopy(operation.value, location: r'$operationValue'),
            index,
          );
        case JsonRemove():
          _remove(operation.path, index);
        case JsonReplace():
          _replace(operation.path, operation.value, index);
        case JsonTest():
          _test(operation.path, operation.value, index);
        case JsonMove():
          _move(operation.from, operation.path, index);
        case JsonCopy():
          _copy(operation.from, operation.path, index);
      }
    }
    return root;
  }

  // The inserted value is already owned by this application. Add and copy
  // detach their values first; move transfers a subtree removed from this tree.
  void _insert(JsonPointer path, Object? inserted, int operationIndex) {
    if (path.segments.isEmpty) {
      root = inserted;
      return;
    }
    final (:parent, :segment) = _resolveParent(path, operationIndex);
    switch (parent) {
      case Map<String, Object?>():
        parent[segment] = inserted;
      case List<Object?>():
        final index = _arrayIndex(
          segment,
          length: parent.length,
          inserting: true,
          path: path,
          operationIndex: operationIndex,
        );
        parent.insert(index, inserted);
      default:
        _fail(
          operationIndex,
          path,
          JsonPatchFailure.wrongContainerType,
          'Parent is not a container.',
        );
    }
  }

  Object? _remove(JsonPointer path, int operationIndex) {
    if (path.segments.isEmpty) {
      final removed = _existingRoot(path, operationIndex);
      root = JsonAbsent.instance;
      return removed;
    }
    final (:parent, :segment) = _resolveParent(path, operationIndex);
    return switch (parent) {
      Map<String, Object?>() => _removeObjectMember(parent, segment, path, operationIndex),
      List<Object?>() => parent.removeAt(
        _arrayIndex(segment, length: parent.length, path: path, operationIndex: operationIndex),
      ),
      _ => _fail(
        operationIndex,
        path,
        JsonPatchFailure.wrongContainerType,
        'Parent is not a container.',
      ),
    };
  }

  void _replace(JsonPointer path, Object? value, int operationIndex) {
    final replacement = _mutableJsonCopy(value, location: r'$operationValue');
    if (path.segments.isEmpty) {
      _existingRoot(path, operationIndex);
      root = replacement;
      return;
    }
    final (:parent, :segment) = _resolveParent(path, operationIndex);
    switch (parent) {
      case Map<String, Object?>():
        if (!parent.containsKey(segment)) {
          _fail(operationIndex, path, JsonPatchFailure.missingTarget, 'Target does not exist.');
        }
        parent[segment] = replacement;
      case List<Object?>():
        parent[_arrayIndex(
              segment,
              length: parent.length,
              path: path,
              operationIndex: operationIndex,
            )] =
            replacement;
      default:
        _fail(
          operationIndex,
          path,
          JsonPatchFailure.wrongContainerType,
          'Parent is not a container.',
        );
    }
  }

  void _test(JsonPointer path, Object? expected, int operationIndex) {
    final actual = _resolveValue(path, operationIndex);
    if (!_jsonEquals(actual, expected)) {
      _fail(
        operationIndex,
        path,
        JsonPatchFailure.testFailed,
        'Target does not match the expected value.',
      );
    }
  }

  void _move(JsonPointer from, JsonPointer path, int operationIndex) {
    _resolveValue(from, operationIndex);
    if (_isProperPointerPrefix(from, path)) {
      _fail(
        operationIndex,
        path,
        JsonPatchFailure.invalidMove,
        'A value cannot be moved into its own descendant.',
      );
    }
    if (from == path) return;

    final value = _remove(from, operationIndex);
    _insert(path, value, operationIndex);
  }

  void _copy(JsonPointer from, JsonPointer path, int operationIndex) {
    final value = _resolveValue(from, operationIndex);
    _insert(path, _mutableJsonCopy(value, location: r'$operationValue'), operationIndex);
  }

  Object? _existingRoot(JsonPointer path, int operationIndex) {
    if (identical(root, JsonAbsent.instance)) {
      _fail(operationIndex, path, JsonPatchFailure.missingTarget, 'The document root is absent.');
    }
    return root;
  }

  ({Object parent, String segment}) _resolveParent(JsonPointer path, int operationIndex) {
    var current = _existingRoot(path, operationIndex);
    for (final segment in path.segments.take(path.segments.length - 1)) {
      current = switch (current) {
        Map<String, Object?>() => _objectMember(current, segment, path, operationIndex),
        List<Object?>() =>
          current[_arrayIndex(
            segment,
            length: current.length,
            path: path,
            operationIndex: operationIndex,
          )],
        _ => _fail(
          operationIndex,
          path,
          JsonPatchFailure.wrongContainerType,
          'Traversal reached a non-container value.',
        ),
      };
    }
    if (current is! Map<String, Object?> && current is! List<Object?>) {
      _fail(
        operationIndex,
        path,
        JsonPatchFailure.wrongContainerType,
        'Parent is not a container.',
      );
    }
    return (parent: current!, segment: path.segments.last);
  }

  Object? _resolveValue(JsonPointer path, int operationIndex) {
    if (path.segments.isEmpty) {
      return _existingRoot(path, operationIndex);
    }
    final (:parent, :segment) = _resolveParent(path, operationIndex);
    return switch (parent) {
      Map<String, Object?>() => _objectMember(parent, segment, path, operationIndex),
      List<Object?>() =>
        parent[_arrayIndex(
          segment,
          length: parent.length,
          path: path,
          operationIndex: operationIndex,
        )],
      _ => throw StateError('A resolved parent must be a container.'),
    };
  }

  Object? _objectMember(
    Map<String, Object?> object,
    String key,
    JsonPointer path,
    int operationIndex,
  ) {
    if (!object.containsKey(key)) {
      _fail(
        operationIndex,
        path,
        JsonPatchFailure.missingTarget,
        'Object member "$key" is missing.',
      );
    }
    return object[key];
  }

  Object? _removeObjectMember(
    Map<String, Object?> object,
    String key,
    JsonPointer path,
    int operationIndex,
  ) {
    final value = _objectMember(object, key, path, operationIndex);
    object.remove(key);
    return value;
  }

  int _arrayIndex(
    String segment, {
    required int length,
    required JsonPointer path,
    required int operationIndex,
    bool inserting = false,
  }) {
    if (segment == '-') {
      if (inserting) return length;
      _fail(
        operationIndex,
        path,
        JsonPatchFailure.invalidArrayIndex,
        'The append token is not allowed here.',
      );
    }
    if (!_isCanonicalArrayIndex(segment)) {
      _fail(
        operationIndex,
        path,
        JsonPatchFailure.invalidArrayIndex,
        '"$segment" is not a valid array index.',
      );
    }
    final index = int.tryParse(segment);
    final maximum = inserting ? length : length - 1;
    if (index == null || index < 0 || index > maximum) {
      _fail(
        operationIndex,
        path,
        JsonPatchFailure.invalidArrayIndex,
        'Array index "$segment" is out of range.',
      );
    }
    return index;
  }
}

bool _isProperPointerPrefix(JsonPointer prefix, JsonPointer pointer) {
  if (prefix.segments.length >= pointer.segments.length) return false;
  for (var index = 0; index < prefix.segments.length; index++) {
    if (prefix.segments[index] != pointer.segments[index]) return false;
  }
  return true;
}

bool _isCanonicalArrayIndex(String segment) {
  if (segment == '0') return true;
  if (segment.isEmpty || segment.codeUnitAt(0) < 0x31 || segment.codeUnitAt(0) > 0x39) return false;
  for (var index = 1; index < segment.length; index++) {
    final codeUnit = segment.codeUnitAt(index);
    if (codeUnit < 0x30 || codeUnit > 0x39) return false;
  }
  return true;
}

Never _fail(int operationIndex, JsonPointer path, JsonPatchFailure reason, String message) {
  throw JsonPatchException(
    operationIndex: operationIndex,
    path: path,
    reason: reason,
    message: message,
  );
}

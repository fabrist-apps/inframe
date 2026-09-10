part of '../json_patch.dart';

final class _JsonDiffer {
  new(Object? before, Object? after)
    : before = _snapshotDocument(before, location: r'$before'),
      after = _snapshotDocument(after, location: r'$after');

  final Object? before;
  final Object? after;
  final operations = <JsonPatchOperation>[];

  JsonPatch run() {
    if (identical(before, JsonAbsent.instance)) {
      if (!identical(after, JsonAbsent.instance)) {
        operations.add(JsonAdd(JsonPointer.root, after));
      }
      return JsonPatch(operations);
    }
    if (identical(after, JsonAbsent.instance)) {
      operations.add(const JsonRemove(JsonPointer.root));
      return JsonPatch(operations);
    }

    _diffValue(before, after, JsonPointer.root);
    return JsonPatch(operations);
  }

  void _diffValue(Object? source, Object? target, JsonPointer path) {
    if (source is Map<String, Object?> && target is Map<String, Object?>) {
      _diffObject(source, target, path);
      return;
    }
    if (source is List<Object?> && target is List<Object?>) {
      _diffArrayPositionally(source, target, path);
      return;
    }
    if (!_jsonEquals(source, target)) operations.add(JsonReplace(path, target));
  }

  void _diffObject(
    Map<String, Object?> source,
    Map<String, Object?> target,
    JsonPointer path,
  ) {
    for (final entry in source.entries) {
      final childPath = path.child(entry.key);
      if (!target.containsKey(entry.key)) {
        operations.add(JsonRemove(childPath));
      } else {
        _diffValue(entry.value, target[entry.key], childPath);
      }
    }
    for (final entry in target.entries) {
      if (!source.containsKey(entry.key)) {
        operations.add(JsonAdd(path.child(entry.key), entry.value));
      }
    }
  }

  void _diffArrayPositionally(List<Object?> source, List<Object?> target, JsonPointer path) {
    final pairedLength = source.length < target.length ? source.length : target.length;
    for (var index = 0; index < pairedLength; index++) {
      _diffValue(source[index], target[index], path.child('$index'));
    }
    for (var index = pairedLength; index < source.length; index++) {
      operations.add(JsonRemove(path.child('$pairedLength')));
    }
    for (var index = pairedLength; index < target.length; index++) {
      operations.add(JsonAdd(path.child('$index'), target[index]));
    }
  }
}

Object? _snapshotDocument(Object? document, {required String location}) {
  if (identical(document, JsonAbsent.instance)) return JsonAbsent.instance;
  return _freezeJson(document, location: location);
}

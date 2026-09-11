part of '../json_patch.dart';

const _alignmentTableCellLimit = 65536;
const _speculativeWorkLimit = 1000000;

final class _JsonDiffer {
  new(Object? before, Object? after)
    : before = _snapshotDocument(before, location: r'$before'),
      after = _snapshotDocument(after, location: r'$after');

  final Object? before;
  final Object? after;
  final operations = <JsonPatchOperation>[];
  final budget = _SpeculativeBudget(_speculativeWorkLimit);

  JsonPatch run() {
    if (identical(before, JsonAbsent.instance)) {
      if (!identical(after, JsonAbsent.instance)) {
        operations.add(JsonAdd._frozen(JsonPointer.root, after));
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
      _diffArray(source, target, path);
      return;
    }
    if (!_jsonEquals(source, target)) operations.add(JsonReplace._frozen(path, target));
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
        operations.add(JsonAdd._frozen(path.child(entry.key), entry.value));
      }
    }
  }

  void _diffArray(List<Object?> source, List<Object?> target, JsonPointer path) {
    // Prefix and suffix matches remain valid if speculative alignment later
    // exhausts the shared budget.
    var prefixLength = 0;
    while (!budget.exhausted && prefixLength < source.length && prefixLength < target.length) {
      final equality = _speculativeEquals(source[prefixLength], target[prefixLength], budget);
      if (equality != _SpeculativeEquality.equal) break;
      prefixLength++;
    }

    var sourceEnd = source.length;
    var targetEnd = target.length;
    while (!budget.exhausted && sourceEnd > prefixLength && targetEnd > prefixLength) {
      final equality = _speculativeEquals(source[sourceEnd - 1], target[targetEnd - 1], budget);
      if (equality != _SpeculativeEquality.equal) break;
      sourceEnd--;
      targetEnd--;
    }

    final sourceLength = sourceEnd - prefixLength;
    final targetLength = targetEnd - prefixLength;
    List<({int source, int target})>? matches;
    if (!budget.exhausted &&
        sourceLength > 0 &&
        targetLength > 0 &&
        _tableFits(sourceLength, targetLength)) {
      matches = _alignArray(
        source,
        prefixLength,
        sourceEnd,
        target,
        prefixLength,
        targetEnd,
        budget,
      );
    }

    // Without alignment anchors, the remaining range is one positional gap.
    var sourceCursor = prefixLength;
    var targetCursor = prefixLength;
    var liveIndex = prefixLength;
    for (final match in matches ?? const <({int source, int target})>[]) {
      liveIndex = _diffArrayGap(
        source,
        sourceCursor,
        match.source,
        target,
        targetCursor,
        match.target,
        path,
        liveIndex,
      );
      sourceCursor = match.source + 1;
      targetCursor = match.target + 1;
      liveIndex++;
    }
    _diffArrayGap(
      source,
      sourceCursor,
      sourceEnd,
      target,
      targetCursor,
      targetEnd,
      path,
      liveIndex,
    );
  }

  int _diffArrayGap(
    List<Object?> source,
    int sourceStart,
    int sourceEnd,
    List<Object?> target,
    int targetStart,
    int targetEnd,
    JsonPointer path,
    int liveIndex,
  ) {
    var nextIndex = liveIndex;
    final sourceLength = sourceEnd - sourceStart;
    final targetLength = targetEnd - targetStart;
    final pairedLength = sourceLength < targetLength ? sourceLength : targetLength;
    for (var offset = 0; offset < pairedLength; offset++) {
      _diffValue(
        source[sourceStart + offset],
        target[targetStart + offset],
        path.child('$nextIndex'),
      );
      nextIndex++;
    }
    for (var offset = pairedLength; offset < sourceLength; offset++) {
      operations.add(JsonRemove(path.child('$nextIndex')));
    }
    for (var offset = pairedLength; offset < targetLength; offset++) {
      operations.add(JsonAdd._frozen(path.child('$nextIndex'), target[targetStart + offset]));
      nextIndex++;
    }
    return nextIndex;
  }
}

final class _SpeculativeBudget {
  new(this.remaining);

  int remaining;
  bool exhausted = false;

  bool charge(int units) {
    if (exhausted) return false;
    if (units > remaining) {
      remaining = 0;
      exhausted = true;
      return false;
    }
    remaining -= units;
    return true;
  }
}

enum _SpeculativeEquality { equal, different, exhausted }

_SpeculativeEquality _speculativeEquals(Object? left, Object? right, _SpeculativeBudget budget) {
  if (!budget.charge(1)) return _SpeculativeEquality.exhausted;
  if (left is num && right is num) {
    return left == right ? _SpeculativeEquality.equal : _SpeculativeEquality.different;
  }
  if (left is String && right is String) {
    if (!budget.charge(left.length + right.length)) return _SpeculativeEquality.exhausted;
    return left == right ? _SpeculativeEquality.equal : _SpeculativeEquality.different;
  }
  if (left == null || left is bool) {
    return left == right ? _SpeculativeEquality.equal : _SpeculativeEquality.different;
  }
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return _SpeculativeEquality.different;
    for (var index = 0; index < left.length; index++) {
      final equality = _speculativeEquals(left[index], right[index], budget);
      if (equality != _SpeculativeEquality.equal) return equality;
    }
    return _SpeculativeEquality.equal;
  }
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    if (left.length != right.length) return _SpeculativeEquality.different;
    for (final entry in left.entries) {
      if (!budget.charge(entry.key.length)) return _SpeculativeEquality.exhausted;
      if (!right.containsKey(entry.key)) return _SpeculativeEquality.different;
      final equality = _speculativeEquals(entry.value, right[entry.key], budget);
      if (equality != _SpeculativeEquality.equal) return equality;
    }
    return _SpeculativeEquality.equal;
  }
  return identical(left, right) ? _SpeculativeEquality.equal : _SpeculativeEquality.different;
}

bool _tableFits(int sourceLength, int targetLength) {
  final rowLength = targetLength + 1;
  return sourceLength + 1 <= _alignmentTableCellLimit ~/ rowLength;
}

List<({int source, int target})>? _alignArray(
  List<Object?> source,
  int sourceStart,
  int sourceEnd,
  List<Object?> target,
  int targetStart,
  int targetEnd,
  _SpeculativeBudget budget,
) {
  final sourceLength = sourceEnd - sourceStart;
  final targetLength = targetEnd - targetStart;
  final rowLength = targetLength + 1;
  // The table stays local to this function. Only the materialized index pairs
  // survive when recursive gap processing begins.
  final table = List<int>.filled((sourceLength + 1) * rowLength, 0);

  for (var sourceIndex = sourceLength - 1; sourceIndex >= 0; sourceIndex--) {
    for (var targetIndex = targetLength - 1; targetIndex >= 0; targetIndex--) {
      if (!budget.charge(1)) return null;
      final equality = _speculativeEquals(
        source[sourceStart + sourceIndex],
        target[targetStart + targetIndex],
        budget,
      );
      if (equality == _SpeculativeEquality.exhausted) return null;
      final cell = sourceIndex * rowLength + targetIndex;
      if (equality == _SpeculativeEquality.equal) {
        table[cell] = table[(sourceIndex + 1) * rowLength + targetIndex + 1] + 1;
      } else {
        final advanceSource = table[(sourceIndex + 1) * rowLength + targetIndex];
        final advanceTarget = table[cell + 1];
        table[cell] = advanceSource > advanceTarget ? advanceSource : advanceTarget;
      }
    }
  }

  final matches = <({int source, int target})>[];
  var sourceIndex = 0;
  var targetIndex = 0;
  while (sourceIndex < sourceLength && targetIndex < targetLength) {
    final equality = _speculativeEquals(
      source[sourceStart + sourceIndex],
      target[targetStart + targetIndex],
      budget,
    );
    if (equality == _SpeculativeEquality.exhausted) return null;
    if (equality == _SpeculativeEquality.equal) {
      matches.add((source: sourceStart + sourceIndex, target: targetStart + targetIndex));
      sourceIndex++;
      targetIndex++;
      continue;
    }

    final advanceSource = table[(sourceIndex + 1) * rowLength + targetIndex];
    final advanceTarget = table[sourceIndex * rowLength + targetIndex + 1];
    if (advanceSource >= advanceTarget) {
      sourceIndex++;
    } else {
      targetIndex++;
    }
  }
  return matches;
}

Object? _snapshotDocument(Object? document, {required String location}) {
  if (identical(document, JsonAbsent.instance)) return JsonAbsent.instance;
  return _freezeJson(document, location: location);
}

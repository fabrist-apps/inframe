part of '../json_patch.dart';

/// A marker for an absent document root.
final class JsonAbsent {
  const new _();

  /// The absent-root marker.
  static const instance = JsonAbsent._();

  @override
  String toString() => 'JsonAbsent.instance';
}

Object? _freezeJson(Object? value, {required String location}) => _copyJson(
  value,
  location: location,
  mutable: false,
  wire: false,
  active: HashSet<Object>.identity(),
);

Object? _freezeWireJson(Object? value, {required String location}) => _copyJson(
  value,
  location: location,
  mutable: false,
  wire: true,
  active: HashSet<Object>.identity(),
);

Object? _mutableJsonCopy(Object? value, {String location = r'$'}) => _copyJson(
  value,
  location: location,
  mutable: true,
  wire: false,
  active: HashSet<Object>.identity(),
);

Object? _copyJson(
  Object? value, {
  required String location,
  required bool mutable,
  required bool wire,
  required Set<Object> active,
}) {
  if (value == null || value is bool || value is String) return value;
  if (value is num) {
    if (!value.isFinite) _invalidJson(location, 'numbers must be finite', wire: wire);
    return value;
  }
  if (value is JsonAbsent) {
    _invalidJson(location, 'JsonAbsent is allowed only as a document root', wire: wire);
  }
  if (value is List) {
    _enterContainer(value, location, active, wire: wire);
    try {
      final copy = <Object?>[
        for (var index = 0; index < value.length; index++)
          _copyJson(
            value[index],
            location: '$location[$index]',
            mutable: mutable,
            wire: wire,
            active: active,
          ),
      ];
      return mutable ? copy : List<Object?>.unmodifiable(copy);
    } finally {
      active.remove(value);
    }
  }
  if (value is Map) {
    _enterContainer(value, location, active, wire: wire);
    try {
      final copy = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          _invalidJson(location, 'object keys must be strings', wire: wire);
        }
        copy[key] = _copyJson(
          entry.value,
          location: '$location.${_locationKey(key)}',
          mutable: mutable,
          wire: wire,
          active: active,
        );
      }
      return mutable ? copy : Map<String, Object?>.unmodifiable(copy);
    } finally {
      active.remove(value);
    }
  }
  _invalidJson(location, 'unsupported ${value.runtimeType} value', wire: wire);
}

Never _invalidJson(String location, String reason, {required bool wire}) {
  if (wire) throw FormatException('Invalid JSON value at $location: $reason.');
  throw ArgumentError('Invalid JSON value at $location: $reason.');
}

void _enterContainer(Object container, String location, Set<Object> active, {required bool wire}) {
  if (!active.add(container)) {
    _invalidJson(location, 'cycles are not supported', wire: wire);
  }
}

String _locationKey(String key) => key.isEmpty ? '<empty>' : key;

bool _jsonEquals(Object? left, Object? right) {
  if (left is num && right is num) return left == right;
  if (left == null || left is bool || left is String) return left == right;
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || !_jsonEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return identical(left, right);
}

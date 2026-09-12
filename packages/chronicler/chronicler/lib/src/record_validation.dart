import 'dart:collection';
import 'dart:convert';

import 'package:chronicler/src/configuration.dart';

const _maximumPortableInteger = 9007199254740991;

final class RecordValidationException implements Exception {
  const RecordValidationException(this.reason);
  final String reason;
}

final class RecordValidator {
  RecordValidator(this.limits);

  final ChroniclerLimits limits;

  Map<String, Object?> snapshotAttributes(Map<String, Object?> attributes) {
    final activeContainers = HashSet<Object>.identity();
    return _snapshotMap(attributes, 1, activeContainers);
  }

  Map<String, Object?> _snapshotMap(
    Map<Object?, Object?> value,
    int depth,
    Set<Object> activeContainers,
  ) {
    _enterContainer(value, depth, activeContainers);
    try {
      if (value.length > limits.maxMapEntries) {
        throw const RecordValidationException('map entry limit exceeded');
      }
      final result = <String, Object?>{};
      for (final MapEntry(:key, :value) in value.entries) {
        if (key is! String || key.isEmpty) {
          throw const RecordValidationException('map keys must be nonempty strings');
        }
        validateString(key, limits.maxKeyBytes, 'map key');
        result[key] = _snapshotValue(value, depth + 1, activeContainers);
      }
      return Map.unmodifiable(result);
    } finally {
      activeContainers.remove(value);
    }
  }

  List<Object?> _snapshotList(
    List<Object?> value,
    int depth,
    Set<Object> activeContainers,
  ) {
    _enterContainer(value, depth, activeContainers);
    try {
      if (value.length > limits.maxListItems) {
        throw const RecordValidationException('list item limit exceeded');
      }
      return List.unmodifiable(
        value.map((item) => _snapshotValue(item, depth + 1, activeContainers)),
      );
    } finally {
      activeContainers.remove(value);
    }
  }

  Object? _snapshotValue(Object? value, int depth, Set<Object> activeContainers) {
    return switch (value) {
      null || bool() => value,
      String() => validateString(value, limits.maxStringBytes, 'string value'),
      int() when value.abs() <= _maximumPortableInteger => value,
      int() => throw const RecordValidationException('integer is not portable'),
      double() when value.isFinite => value == 0 ? 0.0 : value,
      double() => throw const RecordValidationException('number must be finite'),
      Map<Object?, Object?>() => _snapshotMap(value, depth, activeContainers),
      List<Object?>() => _snapshotList(value, depth, activeContainers),
      _ => throw const RecordValidationException('unsupported attribute value'),
    };
  }

  void _enterContainer(Object value, int depth, Set<Object> activeContainers) {
    if (depth > limits.maxDepth) {
      throw const RecordValidationException('container depth limit exceeded');
    }
    if (!activeContainers.add(value)) {
      throw const RecordValidationException('cyclic attribute value');
    }
  }

  String validateString(String value, int maxBytes, String name) {
    for (var index = 0; index < value.length; index++) {
      final codeUnit = value.codeUnitAt(index);
      if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
        if (index + 1 >= value.length) {
          throw RecordValidationException('$name contains invalid Unicode');
        }
        final low = value.codeUnitAt(++index);
        if (low < 0xdc00 || low > 0xdfff) {
          throw RecordValidationException('$name contains invalid Unicode');
        }
      } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
        throw RecordValidationException('$name contains invalid Unicode');
      }
    }
    if (utf8.encode(value).length > maxBytes) {
      throw RecordValidationException('$name byte limit exceeded');
    }
    return value;
  }
}

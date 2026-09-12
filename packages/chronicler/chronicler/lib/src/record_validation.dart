import 'dart:collection';
import 'dart:convert';

import 'package:chronicler/src/configuration.dart';

const _maximumPortableInteger = 9007199254740991;

final class RecordValidationException implements Exception {
  const RecordValidationException(this.reason);
  final String reason;
}

final class RecordValidator {
  RecordValidator(this.limits, {this.maxSnapshotBytes});

  final ChroniclerLimits limits;
  final int? maxSnapshotBytes;

  Map<String, Object?> snapshotAttributes(Map<String, Object?> attributes) {
    final activeContainers = HashSet<Object>.identity();
    final budget = switch (maxSnapshotBytes) {
      final maximum? => _SnapshotBudget(maximum),
      null => null,
    };
    return _snapshotMap(attributes, 1, activeContainers, budget);
  }

  Map<String, Object?> _snapshotMap(
    Map<Object?, Object?> value,
    int depth,
    Set<Object> activeContainers,
    _SnapshotBudget? budget,
  ) {
    _enterContainer(value, depth, activeContainers);
    try {
      if (value.length > limits.maxMapEntries) {
        throw const RecordValidationException('map entry limit exceeded');
      }
      budget?.add(2);
      final result = <String, Object?>{};
      var first = true;
      for (final MapEntry(:key, :value) in value.entries) {
        if (key is! String || key.isEmpty) {
          throw const RecordValidationException('map keys must be nonempty strings');
        }
        validateString(key, limits.maxKeyBytes, 'map key');
        budget?.add((first ? 0 : 1) + _encodedStringBytes(key) + 1);
        first = false;
        result[key] = _snapshotValue(value, depth + 1, activeContainers, budget);
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
    _SnapshotBudget? budget,
  ) {
    _enterContainer(value, depth, activeContainers);
    try {
      if (value.length > limits.maxListItems) {
        throw const RecordValidationException('list item limit exceeded');
      }
      budget?.add(2);
      final result = <Object?>[];
      for (var index = 0; index < value.length; index++) {
        if (index > 0) budget?.add(1);
        result.add(_snapshotValue(value[index], depth + 1, activeContainers, budget));
      }
      return List.unmodifiable(result);
    } finally {
      activeContainers.remove(value);
    }
  }

  Object? _snapshotValue(
    Object? value,
    int depth,
    Set<Object> activeContainers,
    _SnapshotBudget? budget,
  ) {
    return switch (value) {
      null => _countScalar(value, 4, budget),
      bool() => _countScalar(value, value ? 4 : 5, budget),
      String() => _snapshotString(value, budget),
      int() when value >= -_maximumPortableInteger && value <= _maximumPortableInteger =>
        _countScalar(value, value.toString().length, budget),
      int() => throw const RecordValidationException('integer is not portable'),
      double()
          when value.isFinite &&
              (value != value.truncateToDouble() || value.abs() <= _maximumPortableInteger) =>
        _countScalar(value == 0 ? 0.0 : value, jsonEncode(value == 0 ? 0.0 : value).length, budget),
      double() when value.isFinite => throw const RecordValidationException(
        'integer-valued number is not portable',
      ),
      double() => throw const RecordValidationException('number must be finite'),
      Map<Object?, Object?>() => _snapshotMap(value, depth, activeContainers, budget),
      List<Object?>() => _snapshotList(value, depth, activeContainers, budget),
      _ => throw const RecordValidationException('unsupported attribute value'),
    };
  }

  String _snapshotString(String value, _SnapshotBudget? budget) {
    validateString(value, limits.maxStringBytes, 'string value');
    budget?.add(_encodedStringBytes(value));
    return value;
  }

  T _countScalar<T>(T value, int encodedBytes, _SnapshotBudget? budget) {
    budget?.add(encodedBytes);
    return value;
  }

  int _encodedStringBytes(String value) => utf8.encode(jsonEncode(value)).length;

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

final class _SnapshotBudget {
  _SnapshotBudget(this.maximum);

  final int maximum;
  int used = 0;

  void add(int bytes) {
    used += bytes;
    if (used > maximum) {
      throw const RecordValidationException('encoded attribute limit exceeded');
    }
  }
}

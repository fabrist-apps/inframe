import 'dart:collection';
import 'dart:convert';

import 'package:conflux/val.dart';

const _maxDepth = 5;

/// Bounds caller error conversion work before capture.
const maxErrorCauses = 4;

/// Reports why caller-supplied record data is invalid.
final class RecordValidationException implements Exception {
  /// Creates a validation failure with a payload-free [reason].
  const RecordValidationException(this.reason);

  /// The payload-free validation reason.
  final String reason;
}

/// Validates and snapshots JSON-compatible record attributes.
final class RecordValidator {
  /// Creates a validator with an optional snapshot byte budget.
  RecordValidator({this.maxSnapshotBytes});

  /// Maximum encoded bytes copied during a snapshot, when configured.
  final int? maxSnapshotBytes;

  /// Validates and deeply freezes [attributes].
  Map<String, Object?> snapshotAttributes(Map<String, Object?> attributes) {
    final activeContainers = HashSet<Object>.identity();
    final budget = switch (maxSnapshotBytes) {
      final maximum? => _SnapshotBudget(maximum),
      null => null,
    };
    return _snapshotMap(attributes, 1, activeContainers, budget);
  }

  /// Validates and freezes the scalar dimensions carried by a metric series.
  Map<String, Object?> snapshotMetricAttributes(
    Map<String, Object?> attributes, {
    required int maxAttributes,
  }) {
    if (attributes.length > maxAttributes) {
      throw const RecordValidationException('metric attribute limit exceeded');
    }
    final budget = switch (maxSnapshotBytes) {
      final maximum? => _SnapshotBudget(maximum),
      null => null,
    };
    budget?.add(2);
    final result = <String, Object?>{};
    var first = true;
    for (final MapEntry(:key, :value) in attributes.entries) {
      budget?.add((first ? 0 : 1) + _encodedStringBytes(key) + 1);
      first = false;
      result[key] = switch (value) {
        String() => _snapshotString(value, budget),
        bool() => _countScalar(value, value ? 4 : 5, budget),
        int() => _countScalar(value, value.toString().length, budget),
        double() when value.isFinite => _countScalar(
          value == 0 ? 0.0 : value,
          jsonEncode(value == 0 ? 0.0 : value).length,
          budget,
        ),
        double() => throw const RecordValidationException('number must be finite'),
        _ => throw const RecordValidationException('metric values must be scalar'),
      };
    }
    return Map.unmodifiable(result);
  }

  Map<String, Object?> _snapshotMap(
    Map<Object?, Object?> value,
    int depth,
    Set<Object> activeContainers,
    _SnapshotBudget? budget,
  ) {
    _enterContainer(value, depth, activeContainers);
    try {
      budget?.add(2);
      final result = <String, Object?>{};
      var first = true;
      for (final MapEntry(:key, :value) in value.entries) {
        if (key is! String) {
          throw const RecordValidationException('map keys must be strings');
        }
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
      int() => _countScalar(value, value.toString().length, budget),
      double() when value.isFinite => _countScalar(
        value == 0 ? 0.0 : value,
        jsonEncode(value == 0 ? 0.0 : value).length,
        budget,
      ),
      double() => throw const RecordValidationException('number must be finite'),
      Map<Object?, Object?>() => _snapshotMap(value, depth, activeContainers, budget),
      List<Object?>() => _snapshotList(value, depth, activeContainers, budget),
      _ => throw const RecordValidationException('unsupported attribute value'),
    };
  }

  String _snapshotString(String value, _SnapshotBudget? budget) {
    budget?.add(_encodedStringBytes(value));
    return value;
  }

  T _countScalar<T>(T value, int encodedBytes, _SnapshotBudget? budget) {
    budget?.add(encodedBytes);
    return value;
  }

  int _encodedStringBytes(String value) => utf8.encode(jsonEncode(value)).length;

  void _enterContainer(Object value, int depth, Set<Object> activeContainers) {
    if (depth > _maxDepth) {
      throw const RecordValidationException('container depth limit exceeded');
    }
    if (!activeContainers.add(value)) {
      throw const RecordValidationException('cyclic attribute value');
    }
  }

  /// Validates an attribute dictionary with the snapshot resource safeguards.
  Schema<Map<String, Object?>> attributesSchema({int? maxMetricAttributes}) =>
      Val.object({}).passthrough().refine((value) {
        try {
          if (maxMetricAttributes case final maximum?) {
            snapshotMetricAttributes(value, maxAttributes: maximum);
          } else {
            snapshotAttributes(value);
          }
          return true;
        } on RecordValidationException {
          return false;
        }
      }, message: 'attributes are invalid');
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

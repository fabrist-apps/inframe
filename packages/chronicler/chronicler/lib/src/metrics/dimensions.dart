import 'dart:convert';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/record_validation.dart';

/// Validates, snapshots, sorts, and normalizes metric dimensions.
Map<String, Object?> snapshotMetricDimensions(
  Map<String, Object?> attributes,
  MetricOptions options, {
  required int maxRecordBytes,
}) {
  final snapshot = RecordValidator(
    maxSnapshotBytes: maxRecordBytes,
  ).snapshotMetricAttributes(attributes, maxAttributes: options.maxAttributes);
  final names = snapshot.keys.toList()..sort();
  final result = <String, Object?>{};
  for (final name in names) {
    final value = snapshot[name];
    result[name] = switch (value) {
      String() => value,
      bool() => value,
      int() => value,
      double() when value == 0 => 0,
      double()
          when value >= -9223372036854775808.0 &&
              value < 9223372036854775808.0 &&
              value == value.truncateToDouble() =>
        value.toInt(),
      double() => value,
      _ => throw StateError('validated metric dimension has an unsupported type'),
    };
  }
  return Map.unmodifiable(result);
}

/// Encodes canonical dimensions without collisions between scalar types.
String metricSeriesKey(Map<String, Object?> attributes) => jsonEncode([
  for (final MapEntry(:key, :value) in attributes.entries)
    [
      key,
      switch (value) {
        String() => 'string',
        bool() => 'boolean',
        num() => 'number',
        _ => throw StateError('metric dimension was not canonicalized'),
      },
      value,
    ],
]);

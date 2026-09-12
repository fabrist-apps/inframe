import 'dart:convert';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/record_validation.dart';

/// Validates, snapshots, sorts, and normalizes metric dimensions.
Map<String, Object?> snapshotMetricDimensions(
  Map<String, Object?> attributes,
  ChroniclerLimits limits,
  MetricOptions options,
) {
  final snapshot = RecordValidator(
    limits,
  ).snapshotMetricAttributes(attributes, maxAttributes: options.maxAttributes);
  final names = snapshot.keys.toList()..sort();
  final result = <String, Object?>{};
  for (final name in names) {
    final value = snapshot[name];
    result[name] = switch (value) {
      String() => value,
      bool() => value,
      num() => value.toDouble() == 0 ? 0.0 : value.toDouble(),
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
        double() => 'number',
        _ => throw StateError('metric dimension was not canonicalized'),
      },
      value,
    ],
]);

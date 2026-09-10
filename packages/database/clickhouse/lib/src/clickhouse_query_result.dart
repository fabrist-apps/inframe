import 'dart:collection';

/// Metadata for one column returned by ClickHouse.
final class ClickHouseColumn {
  /// Creates output column metadata.
  const ClickHouseColumn({required this.name, required this.type});

  /// The output column name.
  final String name;

  /// The ClickHouse type description received from the server.
  final String type;
}

/// A completely validated, immutable ClickHouse query result.
final class ClickHouseQueryResult {
  /// Creates an immutable snapshot of [columns] and [rows].
  ClickHouseQueryResult({
    required Iterable<ClickHouseColumn> columns,
    required Iterable<Map<String, Object?>> rows,
  }) : columns = List<ClickHouseColumn>.unmodifiable(columns),
       rows = List<Map<String, Object?>>.unmodifiable(
         rows.map((row) => _freezeMap(row, HashSet<Object>.identity())),
       );

  /// Output column metadata in server order.
  final List<ClickHouseColumn> columns;

  /// Output rows in server order.
  final List<Map<String, Object?>> rows;
}

Object? _freeze(Object? value, Set<Object> activeContainers) {
  if (value == null || value is bool || value is String) {
    return value;
  }
  if (value case final num number when number.isFinite) {
    return number;
  }
  if (value is Map<Object?, Object?>) {
    return _freezeContainer(
      value,
      activeContainers,
      () => _freezeNestedMap(value, activeContainers),
    );
  }
  if (value is Iterable<Object?>) {
    return _freezeContainer(
      value,
      activeContainers,
      () => List<Object?>.unmodifiable(
        value.map((item) => _freeze(item, activeContainers)),
      ),
    );
  }
  throw ArgumentError.value(value, 'rows', 'Rows must contain only JSON-compatible values.');
}

Map<String, Object?> _freezeMap(Map<String, Object?> map, Set<Object> activeContainers) =>
    _freezeContainer(
      map,
      activeContainers,
      () => Map<String, Object?>.unmodifiable(
        map.map(
          (key, value) => MapEntry<String, Object?>(key, _freeze(value, activeContainers)),
        ),
      ),
    );

Map<String, Object?> _freezeNestedMap(
  Map<Object?, Object?> map,
  Set<Object> activeContainers,
) {
  final copy = <String, Object?>{};
  for (final entry in map.entries) {
    final key = entry.key;
    if (key is! String) {
      throw ArgumentError.value(map, 'rows', 'Nested JSON object keys must be strings.');
    }
    copy[key] = _freeze(entry.value, activeContainers);
  }
  return Map<String, Object?>.unmodifiable(copy);
}

T _freezeContainer<T>(
  Object container,
  Set<Object> activeContainers,
  T Function() freezeChildren,
) {
  if (!activeContainers.add(container)) {
    throw ArgumentError.value(container, 'rows', 'Rows must not contain cyclic collections.');
  }
  try {
    return freezeChildren();
  } finally {
    activeContainers.remove(container);
  }
}

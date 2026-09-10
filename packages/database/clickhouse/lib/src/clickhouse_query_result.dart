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
       rows = List<Map<String, Object?>>.unmodifiable(rows.map(_freezeMap));

  /// Output column metadata in server order.
  final List<ClickHouseColumn> columns;

  /// Output rows in server order.
  final List<Map<String, Object?>> rows;
}

Object? _freeze(Object? value) => switch (value) {
  final Map<Object?, Object?> map => _freezeNestedMap(map),
  final Iterable<Object?> values => List<Object?>.unmodifiable(values.map(_freeze)),
  _ => value,
};

Map<String, Object?> _freezeMap(Map<String, Object?> map) => Map<String, Object?>.unmodifiable(
  map.map((key, value) => MapEntry<String, Object?>(key, _freeze(value))),
);

Map<String, Object?> _freezeNestedMap(Map<Object?, Object?> map) {
  final copy = <String, Object?>{};
  for (final entry in map.entries) {
    final key = entry.key;
    if (key is! String) {
      throw ArgumentError.value(map, 'rows', 'Nested JSON object keys must be strings.');
    }
    copy[key] = _freeze(entry.value);
  }
  return Map<String, Object?>.unmodifiable(copy);
}

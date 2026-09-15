import 'dart:collection';
import 'dart:convert';

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
    return _freezeMap(value, activeContainers);
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

Map<String, Object?> _freezeMap(Map<Object?, Object?> map, Set<Object> activeContainers) =>
    _freezeContainer(map, activeContainers, () {
      final copy = <String, Object?>{};
      for (final entry in map.entries) {
        final key = entry.key;
        if (key is! String) {
          throw ArgumentError.value(map, 'rows', 'Nested JSON object keys must be strings.');
        }
        copy[key] = _freeze(entry.value, activeContainers);
      }
      return Map<String, Object?>.unmodifiable(copy);
    });

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

/// Decodes and validates one buffered ClickHouse JSON query response.
ClickHouseQueryResult decodeQueryResult(String responseBody) {
  final decoded = jsonDecode(responseBody);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('The response root must be a JSON object.');
  }
  final metadata = decoded['meta'];
  final data = decoded['data'];
  final rowCount = decoded['rows'];
  if (metadata is! List<Object?> ||
      data is! List<Object?> ||
      rowCount is! int ||
      rowCount != data.length) {
    throw const FormatException('The response must contain matching meta, data, and rows fields.');
  }

  final columns = <ClickHouseColumn>[];
  final columnNames = <String>{};
  for (final value in metadata) {
    if (value is! Map<String, Object?> || value['name'] is! String || value['type'] is! String) {
      throw const FormatException('Each metadata entry must contain string name and type fields.');
    }
    final name = value['name']! as String;
    if (!columnNames.add(name)) {
      throw FormatException('ClickHouse returned duplicate column name "$name".');
    }
    columns.add(ClickHouseColumn(name: name, type: value['type']! as String));
  }

  final rows = <Map<String, Object?>>[];
  for (final value in data) {
    if (value is! Map<String, Object?> ||
        value.length != columnNames.length ||
        !value.keys.every(columnNames.contains)) {
      throw const FormatException('Each data row must match the response metadata.');
    }
    rows.add(value);
  }
  return ClickHouseQueryResult(columns: columns, rows: rows);
}

import 'dart:collection';
import 'dart:typed_data';

/// Metadata for one ordered result column.
final class TursoColumn {
  /// Creates column metadata.
  const TursoColumn({required this.name, this.declaredType});

  /// The engine-provided output name.
  final String name;

  /// The declared SQL type when upstream provides it.
  final String? declaredType;
}

/// One immutable row from a buffered query result.
///
/// SQL values are represented as `null`, [BigInt], [double], [String], or
/// owned [Uint8List] bytes. Duplicate column names remain accessible by index
/// and make name lookup ambiguous.
final class TursoRow {
  /// Creates a row from ordered [columns] and [values].
  TursoRow(List<TursoColumn> columns, List<Object?> values)
    : _columns = List<TursoColumn>.unmodifiable(columns),
      _values = List<Object?>.unmodifiable(values.map(_copyBlob)) {
    if (_columns.length != _values.length) {
      throw ArgumentError.value(values, 'values', 'Must match the column count.');
    }
  }

  final List<TursoColumn> _columns;
  final List<Object?> _values;

  /// Returns the value at [index].
  Object? valueAt(int index) => _copyBlob(_values[index]);

  /// Returns the value for an unambiguous output [name].
  Object? value(String name) {
    final matchingIndices = <int>[
      for (var index = 0; index < _columns.length; index++)
        if (_columns[index].name == name) index,
    ];
    if (matchingIndices.isEmpty) {
      throw ArgumentError.value(name, 'name', 'No result column has this name.');
    }
    if (matchingIndices.length > 1) {
      throw StateError('More than one result column is named "$name".');
    }
    return valueAt(matchingIndices.single);
  }

  /// Returns a SQL INTEGER as [BigInt].
  BigInt getBigInt(String name) => _require<BigInt>(name, 'INTEGER');

  /// Returns a SQL INTEGER within Dart's portable safe-integer range.
  int getInt(String name) {
    final value = getBigInt(name);
    const safeLimit = 9007199254740991;
    if (value < BigInt.from(-safeLimit) || value > BigInt.from(safeLimit)) {
      throw RangeError('Column "$name" is outside the portable safe-integer range: $value.');
    }
    return value.toInt();
  }

  /// Returns a SQL REAL without integer coercion.
  double getDouble(String name) => _require<double>(name, 'REAL');

  /// Returns SQL TEXT.
  String getString(String name) => _require<String>(name, 'TEXT');

  /// Returns a defensive copy of a SQL BLOB.
  Uint8List getBlob(String name) => _require<Uint8List>(name, 'BLOB');

  T _require<T>(String name, String sqlType) {
    final result = value(name);
    if (result is! T) {
      throw StateError('Column "$name" is NULL or is not SQL $sqlType.');
    }
    return result;
  }
}

/// A completely buffered SQL query result.
///
/// Results have no package-level size limit. Callers should bound queries when
/// the complete result may be large.
final class TursoQueryResult {
  /// Creates an immutable result.
  TursoQueryResult({
    required List<TursoColumn> columns,
    required List<TursoRow> rows,
  }) : columns = UnmodifiableListView(List<TursoColumn>.of(columns)),
       rows = UnmodifiableListView(List<TursoRow>.of(rows));

  /// Ordered output columns.
  final List<TursoColumn> columns;

  /// Buffered rows.
  final List<TursoRow> rows;
}

Object? _copyBlob(Object? value) => value is Uint8List ? Uint8List.fromList(value) : value;

/// The result of a SQL command.
final class TursoExecuteResult {
  /// Creates a command result.
  const TursoExecuteResult({required this.rowsAffected});

  /// Rows changed by the command.
  final BigInt rowsAffected;
}

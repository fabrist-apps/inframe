import 'errors.dart';

typedef RivetRowDecoder<Row> = Row Function(
  List<Object?> values,
  List<bool> sqlNulls,
);

/// Runtime metadata emitted by a table generator.
final class RivetTableSchema<Definition, Row> {
  RivetTableSchema({
    required this.schemaName,
    required this.tableName,
    required this.definition,
    required this.columns,
    required List<String> columnNames,
    required this.decode,
    this.formatVersion = 1,
  }) {
    if (columns.length != columnNames.length) {
      throw ArgumentError('Column descriptors and generated names must have equal lengths.');
    }
    for (var index = 0; index < columns.length; index++) {
      columns[index].attach(this, dartName: columnNames[index]);
    }
  }

  final String schemaName;
  final String tableName;
  final Definition definition;
  final List<RivetColumn<Object?>> columns;
  final RivetRowDecoder<Row> decode;
  final int formatVersion;

  String get qualifiedName => '${quoteIdentifier(schemaName)}.${quoteIdentifier(tableName)}';
}

/// Base class used by annotated table declarations.
abstract class RivetTableDefinition<Self> {
  RivetOrderableColumnBuilder<String> text({String? name, String? renamedFrom}) =>
      RivetOrderableColumnBuilder(RivetTextCodec(), name: name, renamedFrom: renamedFrom);
}

/// Builds a generated table schema without retaining a live executor.
abstract class RivetTableAccessor<Definition, Row> {
  const RivetTableAccessor();

  RivetTableSchema<Definition, Row> buildSchema();
}

/// Converts values at the PostgreSQL boundary.
abstract interface class RivetCodec<T> {
  String get cast;
  Object? encode(T value);
  T decode(Object? value, {required bool isSqlNull});
}

final class RivetTextCodec implements RivetCodec<String> {
  @override
  String get cast => 'text';

  @override
  Object encode(String value) => value;

  @override
  String decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String) {
      throw const FormatException('expected a non-null PostgreSQL text value');
    }
    return value;
  }
}

/// A typed SQL expression backed by a table column.
class RivetColumn<T> {
  RivetColumn(this.codec, {this.declaredName, this.renamedFrom});

  final RivetCodec<T> codec;
  final String? declaredName;
  final String? renamedFrom;
  late final String dartName;
  late final RivetTableSchema<Object?, Object?> _table;

  void attach<Definition, Row>(
    RivetTableSchema<Definition, Row> table, {
    String? dartName,
  }) {
    this.dartName =
        dartName ?? declaredName ?? (throw StateError('Missing generated column name.'));
    _table = table as RivetTableSchema<Object?, Object?>;
  }

  String get physicalName => declaredName ?? dartName;
  String get sql => quoteIdentifier(physicalName);

  RivetPredicate equals(T value) {
    final encoded = _convert('encode', () => codec.encode(value));
    return RivetPredicate('$sql = @value', [encoded]);
  }

  T decodeValue(Object? value, {required bool isSqlNull}) =>
      _convert('decode', () => codec.decode(value, isSqlNull: isSqlNull));

  R _convert<R>(String operation, R Function() convert) {
    try {
      return convert();
    } on RivetException {
      rethrow;
    } catch (error) {
      throw RivetConversionException(
        table: '${_table.schemaName}.${_table.tableName}',
        column: physicalName,
        message: 'Failed to $operation value.',
        cause: error,
      );
    }
  }
}

/// A column that supports SQL ordering.
final class RivetOrderableColumn<T> extends RivetColumn<T> {
  RivetOrderableColumn(super.codec, {super.declaredName, super.renamedFrom});

  RivetOrder asc({NullsOrder nulls = NullsOrder.last}) => RivetOrder(this, false, nulls);
  RivetOrder desc({NullsOrder nulls = NullsOrder.last}) => RivetOrder(this, true, nulls);
}

/// Builder used by table declaration fields such as `text()()`.
final class RivetOrderableColumnBuilder<T> {
  RivetOrderableColumnBuilder(this.codec, {this.name, this.renamedFrom});

  final RivetCodec<T> codec;
  final String? name;
  final String? renamedFrom;

  RivetOrderableColumn<T> call() =>
      RivetOrderableColumn(codec, declaredName: name, renamedFrom: renamedFrom);
}

enum NullsOrder { first, last }

final class RivetOrder {
  const RivetOrder(this.column, this.descending, this.nulls);

  final RivetOrderableColumn<Object?> column;
  final bool descending;
  final NullsOrder nulls;
}

/// A parameterized SQL predicate produced by typed expressions.
final class RivetPredicate {
  const RivetPredicate(this.sql, this.parameters);

  final String sql;
  final List<Object?> parameters;
}

String quoteIdentifier(String identifier) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(identifier, 'identifier', 'must be non-empty and contain no NUL');
  }
  return '"${identifier.replaceAll('"', '""')}"';
}

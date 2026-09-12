import 'errors.dart';
import 'relation.dart';

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
    this.indexes = const [],
    this.constraints = const [],
    this.relations = const {},
  }) {
    if (columns.length != columnNames.length) {
      throw ArgumentError('Column descriptors and generated names must have equal lengths.');
    }
    for (var index = 0; index < columns.length; index++) {
      columns[index].attach(this, dartName: columnNames[index]);
    }
    final physicalNames = columns.map((column) => column.physicalName).toSet();
    if (physicalNames.length != columns.length) {
      throw ArgumentError('Table $schemaName.$tableName has duplicate physical column names.');
    }
  }

  final String schemaName;
  final String tableName;
  final Definition definition;
  final List<RivetColumn<Object?>> columns;
  final RivetRowDecoder<Row> decode;
  final int formatVersion;
  final List<RivetIndex> indexes;
  final List<RivetConstraint> constraints;
  final Map<String, RivetRelationDescriptor<Object?>> relations;

  String get qualifiedName => '${quoteIdentifier(schemaName)}.${quoteIdentifier(tableName)}';
}

/// Base class used by annotated table declarations.
abstract class RivetTableDefinition<Self> {
  RivetOrderableColumnBuilder<String> text({String? name, String? renamedFrom}) =>
      RivetOrderableColumnBuilder(RivetTextCodec(), name: name, renamedFrom: renamedFrom);

  RivetRelationBuilder<Target, RivetOneRelation<Target>> one<Target>({
    required List<RivetColumn<dynamic>> fields,
    required List<RivetColumn<dynamic>> Function(Target table) references,
  }) => RivetRelationBuilder(RivetOneRelation(Target));

  RivetRelationBuilder<Target, RivetManyRelation<Target>> many<Target>({
    Object? Function(Target table)? relation,
    Type? through,
  }) => RivetRelationBuilder(RivetManyRelation(Target, through: through));

  RivetIndexBuilder index(String name) => RivetIndexBuilder(name, unique: false);
  RivetIndexBuilder uniqueIndex(String name) => RivetIndexBuilder(name, unique: true);
  RivetConstraint check(String name, RivetPredicate predicate) =>
      RivetConstraint(name: name, kind: RivetConstraintKind.check, expression: predicate.sql);
}

enum RivetReferentialAction { noAction, restrict, cascade, setNull, setDefault }

enum RivetConstraintKind { check, primaryKey, foreignKey }

final class RivetForeignKey {
  const RivetForeignKey({
    required this.targetTable,
    required this.onDelete,
    required this.onUpdate,
  });

  final Type targetTable;
  final RivetReferentialAction onDelete;
  final RivetReferentialAction onUpdate;
}

final class RivetConstraint {
  const RivetConstraint({required this.name, required this.kind, this.expression});

  final String name;
  final RivetConstraintKind kind;
  final String? expression;
}

final class RivetIndex {
  const RivetIndex({required this.name, required this.unique, required this.terms, this.predicate});

  final String name;
  final bool unique;
  final List<RivetIndexTerm> terms;
  final RivetPredicate? predicate;
}

final class RivetIndexTerm {
  const RivetIndexTerm(this.column, {this.descending = false});

  final RivetColumn<dynamic> column;
  final bool descending;
}

final class RivetIndexBuilder {
  const RivetIndexBuilder(this.name, {required this.unique, this.predicate});

  final String name;
  final bool unique;
  final RivetPredicate? predicate;

  RivetIndexBuilder where(RivetPredicate value) =>
      RivetIndexBuilder(name, unique: unique, predicate: value);

  RivetIndex on(List<Object> terms) => RivetIndex(
    name: name,
    unique: unique,
    terms: [
      for (final term in terms)
        switch (term) {
          RivetIndexTerm() => term,
          RivetColumn<dynamic>() => RivetIndexTerm(term),
          _ => throw ArgumentError.value(term, 'terms', 'must be a Rivet column or index term'),
        },
    ],
    predicate: predicate,
  );
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
  bool isPrimaryKey = false;
  RivetForeignKey? foreignKey;
  String? sqlDefault;
  Object? Function()? defaultFn;
  Object? Function()? onUpdateFn;
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
  RivetIndexTerm indexAsc() => RivetIndexTerm(this);
  RivetIndexTerm indexDesc() => RivetIndexTerm(this, descending: true);
}

/// Builder used by table declaration fields such as `text()()`.
class RivetOrderableColumnBuilder<T> {
  RivetOrderableColumnBuilder(this.codec, {this.name, this.renamedFrom});

  final RivetCodec<T> codec;
  final String? name;
  final String? renamedFrom;
  bool _primaryKey = false;
  RivetForeignKey? _foreignKey;
  String? _sqlDefault;
  T Function()? _defaultFn;
  T Function()? _onUpdateFn;

  RivetOrderableColumnBuilder<T> primaryKey() {
    _primaryKey = true;
    return this;
  }

  RivetOrderableColumnBuilder<T> references<Target>(
    RivetColumn<dynamic> Function(Target table) reference, {
    RivetReferentialAction onDelete = RivetReferentialAction.noAction,
    RivetReferentialAction onUpdate = RivetReferentialAction.noAction,
  }) {
    _foreignKey = RivetForeignKey(targetTable: Target, onDelete: onDelete, onUpdate: onUpdate);
    return this;
  }

  RivetOrderableColumnBuilder<T> defaultSql(String sql) {
    _sqlDefault = sql;
    return this;
  }

  RivetOrderableColumnBuilder<T> defaultValue(T Function() value) {
    _defaultFn = value;
    return this;
  }

  RivetOrderableColumnBuilder<T> onUpdate(T Function() value) {
    _onUpdateFn = value;
    return this;
  }

  RivetOrderableColumn<T> call() =>
      RivetOrderableColumn<T>(codec, declaredName: name, renamedFrom: renamedFrom)
        ..isPrimaryKey = _primaryKey
        ..foreignKey = _foreignKey
        ..sqlDefault = _sqlDefault
        ..defaultFn = _defaultFn
        ..onUpdateFn = _onUpdateFn;
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

  RivetPredicate operator &(RivetPredicate other) =>
      RivetPredicate('($sql) AND (${other.sql})', [...parameters, ...other.parameters]);

  RivetPredicate operator |(RivetPredicate other) =>
      RivetPredicate('($sql) OR (${other.sql})', [...parameters, ...other.parameters]);

  RivetPredicate operator ~() => RivetPredicate('NOT ($sql)', parameters);
}

String quoteIdentifier(String identifier) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(identifier, 'identifier', 'must be non-empty and contain no NUL');
  }
  return '"${identifier.replaceAll('"', '""')}"';
}

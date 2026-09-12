import 'dart:convert';

import 'package:chrono_id/chrono_id.dart';

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

  RivetOrderableColumnBuilder<String> chronoID({
    String? prefix,
    int size = 24,
    String? name,
    String? renamedFrom,
  }) => RivetOrderableColumnBuilder(
    RivetChronoIdCodec(prefix: prefix, size: size),
    name: name,
    renamedFrom: renamedFrom,
  )..defaultValue(() => ChronoID.generate(prefix: prefix, size: size));

  RivetOrderableColumnBuilder<int> integer({String? name, String? renamedFrom}) =>
      RivetOrderableColumnBuilder(RivetIntegerCodec(), name: name, renamedFrom: renamedFrom);

  RivetOrderableColumnBuilder<double> real({String? name, String? renamedFrom}) =>
      RivetOrderableColumnBuilder(RivetRealCodec(), name: name, renamedFrom: renamedFrom);

  RivetOrderableColumnBuilder<bool> boolean({String? name, String? renamedFrom}) =>
      RivetOrderableColumnBuilder(RivetBooleanCodec(), name: name, renamedFrom: renamedFrom);

  RivetOrderableColumnBuilder<DateTime> dateTime({String? name, String? renamedFrom}) =>
      RivetOrderableColumnBuilder(RivetDateTimeCodec(), name: name, renamedFrom: renamedFrom);

  RivetColumnBuilder<JsonValue> json({String? name, String? renamedFrom}) =>
      RivetColumnBuilder(RivetJsonCodec(), name: name, renamedFrom: renamedFrom);

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

final class RivetNullableCodec<T> implements RivetCodec<T?> {
  const RivetNullableCodec(this.inner);

  final RivetCodec<T> inner;

  @override
  String get cast => inner.cast;

  @override
  Object? encode(T? value) => value == null ? null : inner.encode(value);

  @override
  T? decode(Object? value, {required bool isSqlNull}) =>
      isSqlNull ? null : inner.decode(value, isSqlNull: false);
}

final class RivetChronoIdCodec implements RivetCodec<String> {
  const RivetChronoIdCodec({this.prefix, this.size = 24});

  final String? prefix;
  final int size;

  @override
  String get cast => 'text';

  @override
  Object encode(String value) {
    _validate(value);
    return value;
  }

  @override
  String decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String) throw const FormatException('expected a Chrono ID string');
    _validate(value);
    return value;
  }

  void _validate(String value) {
    if (!ChronoID.isValid(value, prefix: prefix, size: size)) {
      throw const FormatException('invalid Chrono ID');
    }
  }
}

final class RivetIntegerCodec implements RivetCodec<int> {
  static const min = -2147483648;
  static const max = 2147483647;

  @override
  String get cast => 'int4';

  @override
  Object encode(int value) {
    _validate(value);
    return value;
  }

  @override
  int decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! int) throw const FormatException('expected a PostgreSQL INTEGER');
    _validate(value);
    return value;
  }

  void _validate(int value) {
    if (value < min || value > max) throw RangeError.range(value, min, max, 'integer');
  }
}

final class RivetRealCodec implements RivetCodec<double> {
  @override
  String get cast => 'float8';

  @override
  Object encode(double value) => value;

  @override
  double decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! num)
      throw const FormatException('expected a PostgreSQL DOUBLE PRECISION');
    return value.toDouble();
  }
}

final class RivetBooleanCodec implements RivetCodec<bool> {
  @override
  String get cast => 'bool';

  @override
  Object encode(bool value) => value;

  @override
  bool decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! bool) throw const FormatException('expected a PostgreSQL BOOLEAN');
    return value;
  }
}

final class RivetDateTimeCodec implements RivetCodec<DateTime> {
  @override
  String get cast => 'timestamptz';

  @override
  Object encode(DateTime value) => _milliseconds(value);

  @override
  DateTime decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! DateTime)
      throw const FormatException('expected a PostgreSQL TIMESTAMPTZ');
    return _milliseconds(value);
  }

  DateTime _milliseconds(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(value.toUtc().millisecondsSinceEpoch, isUtc: true);
}

sealed class JsonValue {
  const JsonValue();

  factory JsonValue.from(Object? value) => value == null ? const JsonNull() : JsonData(value);

  Object? toDart();
}

final class JsonNull extends JsonValue {
  const JsonNull();

  @override
  Object? toDart() => null;

  @override
  bool operator ==(Object other) => other is JsonNull;

  @override
  int get hashCode => 0;
}

final class JsonData extends JsonValue {
  JsonData(Object value) : value = _validatedJson(value);

  final Object value;

  @override
  Object toDart() => value;

  @override
  bool operator ==(Object other) =>
      other is JsonData && jsonEncode(other.value) == jsonEncode(value);

  @override
  int get hashCode => jsonEncode(value).hashCode;
}

final class RivetJsonCodec implements RivetCodec<JsonValue> {
  @override
  String get cast => 'jsonb';

  @override
  Object? encode(JsonValue value) => value.toDart();

  @override
  JsonValue decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull) throw const FormatException('expected non-null PostgreSQL JSONB');
    return JsonValue.from(value);
  }
}

Object _validatedJson(Object value) {
  void validate(Object? item) {
    switch (item) {
      case null || bool() || String():
        return;
      case final num number:
        if (!number.isFinite) throw const FormatException('JSON numbers must be finite');
      case final List<Object?> list:
        for (final child in list) validate(child);
      case final Map<Object?, Object?> map:
        for (final entry in map.entries) {
          if (entry.key is! String) throw const FormatException('JSON object keys must be strings');
          validate(entry.value);
        }
      default:
        throw const FormatException('value is not valid JSON');
    }
  }

  validate(value);
  return value;
}

abstract interface class RivetTypeConverter<Domain, Storage> {
  Domain fromSql(Storage value);
  Storage toSql(Domain value);
}

final class RivetMappedCodec<Domain, Storage> implements RivetCodec<Domain> {
  const RivetMappedCodec(this.storage, this.converter);

  final RivetCodec<Storage> storage;
  final RivetTypeConverter<Domain, Storage> converter;

  @override
  String get cast => storage.cast;

  @override
  Object? encode(Domain value) => storage.encode(converter.toSql(value));

  @override
  Domain decode(Object? value, {required bool isSqlNull}) =>
      converter.fromSql(storage.decode(value, isSqlNull: isSqlNull));
}

class RivetColumnBuilder<T> {
  RivetColumnBuilder(this.codec, {this.name, this.renamedFrom});

  final RivetCodec<T> codec;
  final String? name;
  final String? renamedFrom;

  RivetColumn<T> call() => RivetColumn(codec, declaredName: name, renamedFrom: renamedFrom);

  RivetColumnBuilder<T?> nullable() =>
      RivetColumnBuilder(RivetNullableCodec(codec), name: name, renamedFrom: renamedFrom);

  RivetMappedColumnBuilder<Domain, T> map<Domain>(
    RivetTypeConverter<Domain, T> converter,
  ) => RivetMappedColumnBuilder(codec, converter, name: name, renamedFrom: renamedFrom);
}

class RivetMappedColumn<Domain, Storage> extends RivetColumn<Domain> {
  RivetMappedColumn(
    RivetCodec<Domain> codec,
    this.storage, {
    super.declaredName,
    super.renamedFrom,
  }) : super(codec);

  final RivetColumn<Storage> storage;

  @override
  void attach<Definition, Row>(RivetTableSchema<Definition, Row> table, {String? dartName}) {
    super.attach(table, dartName: dartName);
    storage.attach(table, dartName: dartName);
  }
}

final class RivetOrderableMappedColumn<Domain, Storage> extends RivetMappedColumn<Domain, Storage> {
  RivetOrderableMappedColumn(
    super.codec,
    RivetOrderableColumn<Storage> super.storage, {
    super.declaredName,
    super.renamedFrom,
  });

  @override
  RivetOrderableColumn<Storage> get storage => super.storage as RivetOrderableColumn<Storage>;
}

class RivetMappedColumnBuilder<Domain, Storage> {
  RivetMappedColumnBuilder(this.storageCodec, this.converter, {this.name, this.renamedFrom});

  final RivetCodec<Storage> storageCodec;
  final RivetTypeConverter<Domain, Storage> converter;
  final String? name;
  final String? renamedFrom;

  RivetMappedColumnBuilder<Domain?, Storage?> nullable() => RivetMappedColumnBuilder(
    RivetNullableCodec(storageCodec),
    _NullableConverter(converter),
    name: name,
    renamedFrom: renamedFrom,
  );

  RivetMappedColumn<Domain, Storage> call() => RivetMappedColumn(
    RivetMappedCodec(storageCodec, converter),
    RivetColumn(storageCodec, declaredName: name, renamedFrom: renamedFrom),
    declaredName: name,
    renamedFrom: renamedFrom,
  );
}

final class RivetOrderableMappedColumnBuilder<Domain, Storage>
    extends RivetMappedColumnBuilder<Domain, Storage> {
  RivetOrderableMappedColumnBuilder(
    super.storageCodec,
    super.converter, {
    super.name,
    super.renamedFrom,
  });

  @override
  RivetOrderableMappedColumn<Domain, Storage> call() => RivetOrderableMappedColumn(
    RivetMappedCodec(storageCodec, converter),
    RivetOrderableColumn(storageCodec, declaredName: name, renamedFrom: renamedFrom),
    declaredName: name,
    renamedFrom: renamedFrom,
  );

  @override
  RivetOrderableMappedColumnBuilder<Domain?, Storage?> nullable() =>
      RivetOrderableMappedColumnBuilder(
        RivetNullableCodec(storageCodec),
        _NullableConverter(converter),
        name: name,
        renamedFrom: renamedFrom,
      );
}

final class _NullableConverter<Domain, Storage> implements RivetTypeConverter<Domain?, Storage?> {
  const _NullableConverter(this.inner);

  final RivetTypeConverter<Domain, Storage> inner;

  @override
  Domain? fromSql(Storage? value) => value == null ? null : inner.fromSql(value);

  @override
  Storage? toSql(Domain? value) => value == null ? null : inner.toSql(value);
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

  RivetOrderableColumnBuilder<T?> nullable() => RivetOrderableColumnBuilder(
    RivetNullableCodec(codec),
    name: name,
    renamedFrom: renamedFrom,
  );

  RivetOrderableMappedColumnBuilder<Domain, T> map<Domain>(
    RivetTypeConverter<Domain, T> converter,
  ) => RivetOrderableMappedColumnBuilder(
    codec,
    converter,
    name: name,
    renamedFrom: renamedFrom,
  );

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

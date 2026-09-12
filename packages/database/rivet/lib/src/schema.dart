// The README documents the declaration DSL; consequential runtime contracts are documented here.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:chrono_id/chrono_id.dart';
import 'package:meta/meta.dart';
import 'package:postgres/postgres.dart' as pg;

import 'package:rivet/src/errors.dart';
import 'package:rivet/src/relation.dart';

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
    required List<RivetColumn<Object?>> columns,
    required List<String> columnNames,
    required this.decode,
    this.formatVersion = 1,
    List<RivetIndex> indexes = const [],
    List<RivetConstraint> constraints = const [],
    Map<String, RivetRelationDescriptor<Object?>> relations = const {},
  }) : columns = List.unmodifiable(columns),
       indexes = List.unmodifiable(indexes),
       constraints = List.unmodifiable(constraints),
       relations = Map.unmodifiable(relations) {
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
    if (indexes.map((index) => index.name).toSet().length != indexes.length) {
      throw ArgumentError('Table $schemaName.$tableName has duplicate index names.');
    }
    if (constraints.map((constraint) => constraint.name).toSet().length != constraints.length) {
      throw ArgumentError('Table $schemaName.$tableName has duplicate constraint names.');
    }
    for (final index in indexes) {
      if (index.terms.isEmpty || index.terms.any((term) => !columns.contains(term.column))) {
        throw ArgumentError('Index $schemaName.$tableName.${index.name} has invalid terms.');
      }
      if (index.predicate case final predicate?
          when predicate.columns.any((column) => !columns.contains(column))) {
        throw ArgumentError('Index $schemaName.$tableName.${index.name} has an invalid predicate.');
      }
    }
    for (final constraint in constraints) {
      if (constraint.predicate case final predicate?
          when predicate.columns.any((column) => !columns.contains(column))) {
        throw ArgumentError(
          'Constraint $schemaName.$tableName.${constraint.name} has an invalid expression.',
        );
      }
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

  RivetOrderableColumnBuilder<E> enumText<E extends Enum>({
    String? name,
    String? renamedFrom,
  }) => RivetOrderableColumnBuilder(
    RivetUnconfiguredEnumCodec<E>(),
    name: name,
    renamedFrom: renamedFrom,
  );

  RivetColumnBuilder<Float32List> vector({
    required int dimensions,
    String? name,
    String? renamedFrom,
  }) => RivetColumnBuilder(
    RivetVectorCodec(dimensions),
    name: name,
    renamedFrom: renamedFrom,
  );

  RivetRelationBuilder<Target, RivetOneRelation<Target>> one<Target>({
    required List<RivetColumn<dynamic>> fields,
    required List<RivetColumn<dynamic>> Function(Target table) references,
  }) => RivetRelationBuilder(
    RivetOneRelation(Target, fields: List.unmodifiable(fields), references: references),
  );

  RivetRelationBuilder<Target, RivetManyRelation<Target>> many<Target>({
    RivetRelationDescriptor<dynamic> Function(Target table)? relation,
    Type? through,
  }) => RivetRelationBuilder(RivetManyRelation(Target, relation: relation, through: through));

  RivetIndexBuilder index(String name) => RivetIndexBuilder(name, unique: false);
  RivetIndexBuilder uniqueIndex(String name) => RivetIndexBuilder(name, unique: true);
  RivetConstraint check(String name, RivetPredicate predicate) => RivetConstraint(
    name: name,
    kind: RivetConstraintKind.check,
    expression: predicate.sql,
    predicate: predicate,
  );
}

enum RivetReferentialAction { noAction, restrict, cascade, setNull, setDefault }

enum RivetConstraintKind { check, primaryKey, foreignKey }

final class RivetForeignKey {
  RivetForeignKey({
    required this.targetTable,
    required this.reference,
    required this.onDelete,
    required this.onUpdate,
  });

  final Type targetTable;
  final RivetColumn<dynamic> Function(Object table) reference;
  final RivetReferentialAction onDelete;
  final RivetReferentialAction onUpdate;
  RivetColumn<dynamic>? referencedColumn;
}

final class RivetConstraint {
  const RivetConstraint({
    required this.name,
    required this.kind,
    this.expression,
    this.predicate,
  });

  final String name;
  final RivetConstraintKind kind;
  final String? expression;
  final RivetPredicate? predicate;
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
          RivetOrder() => RivetIndexTerm(term.column, descending: term.descending),
          RivetColumn<dynamic>() => RivetIndexTerm(term),
          _ => throw ArgumentError.value(term, 'terms', 'must be a Rivet column or index term'),
        },
    ],
    predicate: predicate,
  );
}

/// Builds a generated table schema without retaining a live executor.
// The accessor is the generated package-composition boundary.
// ignore: one_member_abstracts
abstract class RivetTableAccessor<Definition, Row> {
  const RivetTableAccessor();

  RivetTableSchema<Definition, Row> buildSchema();
}

/// Converts values at the PostgreSQL boundary.
abstract class RivetCodec<T> {
  const RivetCodec();

  String get cast;
  String select(String columnSql) => columnSql;
  Object? encode(T value);
  T decode(Object? value, {required bool isSqlNull});
}

final class RivetTextCodec extends RivetCodec<String> {
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

final class RivetNullableCodec<T> extends RivetCodec<T?> {
  const RivetNullableCodec(this.inner);

  final RivetCodec<T> inner;

  @override
  String get cast => inner.cast;

  @override
  String select(String columnSql) => inner.select(columnSql);

  @override
  Object? encode(T? value) => value == null ? null : inner.encode(value);

  @override
  T? decode(Object? value, {required bool isSqlNull}) =>
      isSqlNull ? null : inner.decode(value, isSqlNull: false);
}

final class RivetChronoIdCodec extends RivetCodec<String> {
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

final class RivetIntegerCodec extends RivetCodec<int> {
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

final class RivetRealCodec extends RivetCodec<double> {
  @override
  String get cast => 'float8';

  @override
  Object encode(double value) => value;

  @override
  double decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! num) {
      throw const FormatException('expected a PostgreSQL DOUBLE PRECISION');
    }
    return value.toDouble();
  }
}

final class RivetBooleanCodec extends RivetCodec<bool> {
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

final class RivetDateTimeCodec extends RivetCodec<DateTime> {
  @override
  String get cast => 'timestamptz';

  @override
  Object encode(DateTime value) => _milliseconds(value);

  @override
  DateTime decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! DateTime) {
      throw const FormatException('expected a PostgreSQL TIMESTAMPTZ');
    }
    return _milliseconds(value);
  }

  DateTime _milliseconds(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(value.toUtc().millisecondsSinceEpoch, isUtc: true);
}

@immutable
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

final class RivetJsonCodec extends RivetCodec<JsonValue> {
  @override
  String get cast => 'jsonb';

  @override
  Object encode(JsonValue value) => pg.TypedValue(pg.Type.jsonb, value.toDart(), isSqlNull: false);

  @override
  JsonValue decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull) throw const FormatException('expected non-null PostgreSQL JSONB');
    return JsonValue.from(value);
  }
}

final class RivetUnconfiguredEnumCodec<E extends Enum> extends RivetCodec<E> {
  @override
  String get cast => 'text';

  @override
  Object encode(E value) => throw StateError('The generated enum codec was not attached.');

  @override
  E decode(Object? value, {required bool isSqlNull}) =>
      throw StateError('The generated enum codec was not attached.');
}

final class RivetEnumCodec<E extends Enum> extends RivetCodec<E> {
  const RivetEnumCodec({
    required this.schemaName,
    required this.typeName,
    required this.values,
    required this.labels,
    this.renamedFrom,
    this.renamedLabels = const {},
  });

  final String schemaName;
  final String typeName;
  final List<E> values;
  final List<String> labels;
  final String? renamedFrom;
  final Map<String, String> renamedLabels;

  @override
  String get cast => '${quoteIdentifier(schemaName)}.${quoteIdentifier(typeName)}';

  @override
  String select(String columnSql) => '$columnSql::text';

  @override
  Object encode(E value) {
    final index = values.indexOf(value);
    if (index < 0) throw ArgumentError.value(value, 'value', 'is not registered');
    return labels[index];
  }

  @override
  E decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String) throw const FormatException('expected a native enum label');
    final index = labels.indexOf(value);
    if (index < 0) throw FormatException('unknown native enum label `$value`');
    return values[index];
  }
}

final class RivetVectorCodec extends RivetCodec<Float32List> {
  RivetVectorCodec(this.dimensions) {
    if (dimensions <= 0 || dimensions > 16000) {
      throw RangeError.range(dimensions, 1, 16000, 'dimensions');
    }
  }

  final int dimensions;

  @override
  String get cast => 'vector';

  @override
  String select(String columnSql) => '$columnSql::text';

  @override
  Object encode(Float32List value) {
    final checked = _validate(value);
    return '[${checked.join(',')}]';
  }

  @override
  Float32List decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String || !value.startsWith('[') || !value.endsWith(']')) {
      throw const FormatException('expected a non-null pgvector text value');
    }
    final body = value.substring(1, value.length - 1);
    final values = body.isEmpty
        ? <double>[]
        : body.split(',').map(double.parse).toList(growable: false);
    return _validate(values);
  }

  Float32List _validate(List<double> value) {
    if (value.length != dimensions) {
      throw FormatException('expected vector dimension $dimensions, received ${value.length}');
    }
    final result = Float32List.fromList(value);
    if (result.any((component) => !component.isFinite)) {
      throw const FormatException('vector components must be finite float32 values');
    }
    return result;
  }
}

Object _validatedJson(Object value) {
  Object? freeze(Object? item) {
    switch (item) {
      case null || bool() || String():
        return item;
      case final num number:
        if (!number.isFinite) throw const FormatException('JSON numbers must be finite');
        return number;
      case final List<Object?> list:
        return List<Object?>.unmodifiable(list.map(freeze));
      case final Map<Object?, Object?> map:
        final result = <String, Object?>{};
        for (final entry in map.entries) {
          final key = entry.key;
          if (key is! String) throw const FormatException('JSON object keys must be strings');
          result[key] = freeze(entry.value);
        }
        return Map<String, Object?>.unmodifiable(result);
      default:
        throw const FormatException('value is not valid JSON');
    }
  }

  return freeze(value)!;
}

abstract interface class RivetTypeConverter<Domain, Storage> {
  Domain fromSql(Storage value);
  Storage toSql(Domain value);
}

final class RivetMappedCodec<Domain, Storage> extends RivetCodec<Domain> {
  const RivetMappedCodec(this.storage, this.converter);

  final RivetCodec<Storage> storage;
  final RivetTypeConverter<Domain, Storage> converter;

  @override
  String get cast => storage.cast;

  @override
  String select(String columnSql) => storage.select(columnSql);

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

  RivetArrayColumnBuilder<T> array() =>
      RivetArrayColumnBuilder(codec, name: name, renamedFrom: renamedFrom);
}

class RivetMappedColumn<Domain, Storage> extends RivetColumn<Domain> {
  RivetMappedColumn(
    super.codec,
    this.storage, {
    super.declaredName,
    super.renamedFrom,
  });

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

  RivetArrayColumnBuilder<Domain> array() => RivetArrayColumnBuilder(
    RivetMappedCodec(storageCodec, converter),
    name: name,
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

  RivetCodec<T> codec;
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
  String get selectionSql => codec.select(sql);
  bool belongsTo(RivetTableSchema<Object?, Object?> table) => identical(_table, table);

  // The generator replaces the placeholder enum codec after constructing a definition.
  // ignore: use_setters_to_change_properties
  void useCodec(RivetCodec<T> value) => codec = value;

  RivetPredicate equals(T value) {
    if (value == null) return RivetPredicate._('$sql IS NULL', const [], [this]);
    final encoded = _convert('encode', () => codec.encode(value));
    return RivetPredicate._('$sql = @value::${codec.cast}', [encoded], [this]);
  }

  T decodeValue(Object? value, {required bool isSqlNull}) =>
      _convert('decode', () => codec.decode(value, isSqlNull: isSqlNull));

  R _convert<R>(String operation, R Function() convert) {
    try {
      return convert();
    } on RivetException {
      rethrow;
    } on Object catch (error) {
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

  RivetOrder asc({NullsOrder nulls = NullsOrder.last}) =>
      RivetOrder(this, descending: false, nulls: nulls);
  RivetOrder desc({NullsOrder nulls = NullsOrder.last}) =>
      RivetOrder(this, descending: true, nulls: nulls);
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

  RivetArrayColumnBuilder<T> array() =>
      RivetArrayColumnBuilder(codec, name: name, renamedFrom: renamedFrom);

  RivetOrderableColumnBuilder<T> primaryKey() {
    _primaryKey = true;
    // Schema modifiers preserve the builder's accumulated metadata.
    // ignore: avoid_returning_this
    return this;
  }

  RivetOrderableColumnBuilder<T> references<Target>(
    RivetColumn<dynamic> Function(Target table) reference, {
    RivetReferentialAction onDelete = RivetReferentialAction.noAction,
    RivetReferentialAction onUpdate = RivetReferentialAction.noAction,
  }) {
    _foreignKey = RivetForeignKey(
      targetTable: Target,
      reference: (table) => reference(table as Target),
      onDelete: onDelete,
      onUpdate: onUpdate,
    );
    // Schema modifiers preserve the builder's accumulated metadata.
    // ignore: avoid_returning_this
    return this;
  }

  RivetOrderableColumnBuilder<T> defaultSql(String sql) {
    _sqlDefault = sql;
    // Schema modifiers preserve the builder's accumulated metadata.
    // ignore: avoid_returning_this
    return this;
  }

  RivetOrderableColumnBuilder<T> defaultValue(T Function() value) {
    _defaultFn = value;
    // Schema modifiers preserve the builder's accumulated metadata.
    // ignore: avoid_returning_this
    return this;
  }

  RivetOrderableColumnBuilder<T> onUpdate(T Function() value) {
    _onUpdateFn = value;
    // Schema modifiers preserve the builder's accumulated metadata.
    // ignore: avoid_returning_this
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

final class RivetArrayColumnBuilder<Element> {
  RivetArrayColumnBuilder(this.elementCodec, {this.name, this.renamedFrom});

  final RivetCodec<Element> elementCodec;
  final String? name;
  final String? renamedFrom;

  RivetColumn<List<Element>> call() => RivetColumn(
    RivetArrayCodec(elementCodec),
    declaredName: name,
    renamedFrom: renamedFrom,
  );

  RivetColumnBuilder<List<Element>?> nullable() => RivetColumnBuilder(
    RivetNullableCodec(RivetArrayCodec(elementCodec)),
    name: name,
    renamedFrom: renamedFrom,
  );
}

final class RivetArrayCodec<Element> extends RivetCodec<List<Element>> {
  const RivetArrayCodec(this.elementCodec);

  final RivetCodec<Element> elementCodec;

  @override
  String get cast => '${elementCodec.cast}[]';

  @override
  String select(String columnSql) {
    final checkedColumn = _checkedArray(columnSql);
    final elementSelection = elementCodec.select('"__rivet_element"');
    if (elementSelection == '"__rivet_element"') return checkedColumn;
    return 'CASE WHEN $checkedColumn IS NULL THEN NULL ELSE ARRAY( '
        'SELECT $elementSelection FROM unnest($checkedColumn) WITH ORDINALITY '
        'AS "__rivet_array"("__rivet_element", "__rivet_order") '
        'ORDER BY "__rivet_order") END';
  }

  @override
  Object encode(List<Element> value) {
    if (value.any((element) => element is List)) {
      throw const FormatException('multidimensional arrays are not supported');
    }
    final encoded = [
      for (final element in value)
        if (element == null && elementCodec.cast == 'jsonb')
          pg.TypedValue(pg.Type.jsonb, null, isSqlNull: true)
        else
          _arrayElement(elementCodec.encode(element)),
    ];
    if (elementCodec.cast == 'jsonb') {
      return pg.TypedValue(pg.Type.jsonbArray, encoded);
    }
    if (elementCodec.select('"e"') != '"e"') {
      return _arrayText(encoded);
    }
    return encoded;
  }

  @override
  List<Element> decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! List) {
      throw const FormatException('expected a one-dimensional array');
    }
    return [
      for (var index = 0; index < value.length; index++)
        elementCodec.decode(
          value[index],
          isSqlNull: value is pg.JsonbListView ? value.isSqlNull(index) : value[index] == null,
        ),
    ];
  }

  String _arrayText(List<Object?> values) =>
      '{${values.map((value) => value == null ? 'NULL' : '"${value.toString().replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"').join(',')}}';

  Object? _arrayElement(Object? value) => switch (value) {
    pg.TypedValue() when value.isSqlNull => value,
    pg.TypedValue() => value.value,
    _ => value,
  };

  String _checkedArray(String columnSql) {
    final dimensions = 'array_ndims($columnSql)';
    final lowerBound = 'array_lower($columnSql, 1)';
    return 'CASE WHEN $columnSql IS NULL OR $dimensions IS NULL OR '
        '($dimensions = 1 AND $lowerBound = 1) THEN $columnSql '
        'ELSE ARRAY[$columnSql[1 / ($lowerBound - $lowerBound)]] END';
  }
}

enum NullsOrder { first, last }

final class RivetOrder {
  const RivetOrder(this.column, {required this.descending, required this.nulls});

  final RivetOrderableColumn<Object?> column;
  final bool descending;
  final NullsOrder nulls;
}

/// A parameterized SQL predicate produced by typed expressions.
final class RivetPredicate {
  RivetPredicate._(
    this.sql,
    List<Object?> parameters,
    List<RivetColumn<dynamic>> columns,
  ) : parameters = List.unmodifiable(parameters),
      columns = List.unmodifiable(columns);

  final String sql;
  final List<Object?> parameters;
  final List<RivetColumn<dynamic>> columns;

  RivetPredicate operator &(RivetPredicate other) => RivetPredicate._(
    '($sql) AND (${other.sql})',
    [...parameters, ...other.parameters],
    [...columns, ...other.columns],
  );

  RivetPredicate operator |(RivetPredicate other) => RivetPredicate._(
    '($sql) OR (${other.sql})',
    [...parameters, ...other.parameters],
    [...columns, ...other.columns],
  );

  RivetPredicate operator ~() => RivetPredicate._('NOT ($sql)', parameters, columns);
}

String quoteIdentifier(String identifier) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(identifier, 'identifier', 'must be non-empty and contain no NUL');
  }
  return '"${identifier.replaceAll('"', '""')}"';
}

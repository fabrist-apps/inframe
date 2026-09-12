// The README documents the declaration DSL; consequential runtime contracts are documented here.
// ignore_for_file: avoid_returning_this, library_private_types_in_public_api, public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:chrono_id/chrono_id.dart';
import 'package:meta/meta.dart';

import 'package:voxel/src/errors.dart';
import 'package:voxel/src/relation.dart';

typedef VoxelRowDecoder<Row> = Row Function(
  List<Object?> values,
  List<bool> sqlNulls,
);

/// Runtime metadata emitted by a table generator.
final class VoxelTableSchema<Definition, Row> {
  VoxelTableSchema({
    required this.schemaName,
    required this.tableName,
    required this.definition,
    required List<VoxelColumn<Object?>> columns,
    required List<String> columnNames,
    required this.decode,
    this.definitionType = Object,
    this.rowType = Object,
    this.createDefinition,
    this.columnsFor,
    this.renamedFrom,
    this.formatVersion = 1,
    List<VoxelIndex> Function()? indexes,
    List<VoxelConstraint> Function()? constraints,
    Map<String, VoxelRelationDescriptor<Object?>> relations = const {},
  }) : columns = List.unmodifiable(columns),
       relations = Map.unmodifiable(relations) {
    if (columns.length != columnNames.length) {
      throw ArgumentError('Column descriptors and generated names must have equal lengths.');
    }
    for (var index = 0; index < columns.length; index++) {
      columns[index].attach(this, dartName: columnNames[index]);
    }
    this.indexes = List.unmodifiable(indexes?.call() ?? const []);
    this.constraints = List.unmodifiable(constraints?.call() ?? const []);
    final physicalNames = columns.map((column) => column.physicalName).toSet();
    if (physicalNames.length != columns.length) {
      throw ArgumentError('Table $schemaName.$tableName has duplicate physical column names.');
    }
    if (this.indexes.map((index) => index.name).toSet().length != this.indexes.length) {
      throw ArgumentError('Table $schemaName.$tableName has duplicate index names.');
    }
    if (this.constraints.map((constraint) => constraint.name).toSet().length !=
        this.constraints.length) {
      throw ArgumentError('Table $schemaName.$tableName has duplicate constraint names.');
    }
    for (final index in this.indexes) {
      if (index.terms.isEmpty || index.terms.any((term) => !columns.contains(term.column))) {
        throw ArgumentError('Index $schemaName.$tableName.${index.name} has invalid terms.');
      }
      if (index.predicate case final predicate?
          when predicate.columns.any((column) => !columns.contains(column))) {
        throw ArgumentError('Index $schemaName.$tableName.${index.name} has an invalid predicate.');
      }
    }
    for (final constraint in this.constraints) {
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
  final String? renamedFrom;
  final Definition definition;
  final List<VoxelColumn<Object?>> columns;
  final Definition Function()? createDefinition;
  final List<VoxelColumn<Object?>> Function(Definition definition)? columnsFor;
  final VoxelRowDecoder<Row> decode;
  final Type definitionType;
  final Type rowType;
  final int formatVersion;
  late final List<VoxelIndex> indexes;
  late final List<VoxelConstraint> constraints;
  final Map<String, VoxelRelationDescriptor<Object?>> relations;

  String get qualifiedName => '${quoteIdentifier(schemaName)}.${quoteIdentifier(tableName)}';

  Definition scopedDefinition(String qualifier) {
    final buildDefinition = createDefinition;
    final selectColumns = columnsFor;
    if (buildDefinition == null || selectColumns == null) {
      throw StateError(
        'Generated table metadata is required for conflict update expressions.',
      );
    }
    final scoped = buildDefinition();
    final scopedColumns = selectColumns(scoped);
    if (scopedColumns.length != columns.length) {
      throw StateError('Generated scoped columns do not match the table schema.');
    }
    for (var index = 0; index < scopedColumns.length; index++) {
      scopedColumns[index].attach(
        this,
        dartName: columns[index].dartName,
        qualifier: qualifier,
      );
    }
    return scoped;
  }
}

/// Connection-free metadata for one generated application database.
final class VoxelDatabaseSchema {
  VoxelDatabaseSchema({
    required this.name,
    required List<VoxelTableSchema<Object?, Object?>> tables,
  }) : tables = List.unmodifiable(tables) {
    if (name.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    _validateVoxelSchemas(this.tables);
  }

  final String name;
  final List<VoxelTableSchema<Object?, Object?>> tables;
  final int formatVersion = 1;
}

const _reservedVoxelTables = {
  '_voxel_identity',
  '_voxel_files',
  '_voxel_migrations',
  '_voxel_phases',
};

void _validateVoxelSchemas(List<VoxelTableSchema<Object?, Object?>> tables) {
  final physicalNames = <String>{};
  final registered = <Type, VoxelTableSchema<Object?, Object?>>{};
  for (final table in tables) {
    final definition = table.definition;
    if (definition == null) {
      throw ArgumentError(
        'Voxel table ${table.schemaName}.${table.tableName} has a null definition.',
      );
    }
    if (_reservedVoxelTables.contains(table.tableName)) {
      throw ArgumentError('Voxel table name ${table.tableName} is reserved for migration state.');
    }
    if (!physicalNames.add('${table.schemaName}.${table.tableName}')) {
      throw ArgumentError(
        'Duplicate Voxel table registration: ${table.schemaName}.${table.tableName}.',
      );
    }
    if (registered[definition.runtimeType] != null) {
      throw ArgumentError('Duplicate Voxel table type registration: ${definition.runtimeType}.');
    }
    registered[definition.runtimeType] = table;
  }
  for (final table in tables) {
    for (final column in table.columns) {
      final foreignKey = column.foreignKey;
      if (foreignKey == null) continue;
      final target = registered[foreignKey.targetTable];
      if (target == null) {
        throw ArgumentError(
          'Foreign key ${table.schemaName}.${table.tableName}.${column.physicalName} targets '
          '${foreignKey.targetTable}, which is not registered.',
        );
      }
      if (table.schemaName != target.schemaName) {
        throw ArgumentError(
          'Voxel foreign keys cannot cross schemas: ${table.schemaName} to ${target.schemaName}.',
        );
      }
      final referenced = foreignKey.reference(target.definition!);
      if (!target.columns.contains(referenced)) {
        throw ArgumentError(
          'Foreign key ${table.tableName}.${column.physicalName} selects a foreign column.',
        );
      }
      if (column.codec.cast != referenced.codec.cast) {
        throw ArgumentError(
          'Foreign key ${table.tableName}.${column.physicalName} maps ${column.codec.cast} '
          'to incompatible ${referenced.codec.cast}.',
        );
      }
      foreignKey.referencedColumn = referenced;
    }
    for (final entry in table.relations.entries) {
      final relation = entry.value;
      final target = registered[relation.targetTable];
      if (target == null) {
        throw ArgumentError(
          'Relation ${table.tableName}.${entry.key} targets an unregistered table.',
        );
      }
      relation.resolve(target.definition);
      if (relation.kind == VoxelRelationKind.manyThrough) {
        final through = registered[relation.through];
        if (through == null) {
          throw ArgumentError(
            'Relation ${table.tableName}.${entry.key} uses an unregistered through table.',
          );
        }
        final source = relation.source?.call(through.definition!);
        final destination = relation.target?.call(through.definition!);
        if (source == null ||
            destination == null ||
            source.kind != VoxelRelationKind.one ||
            destination.kind != VoxelRelationKind.one ||
            source.targetTable != table.definition.runtimeType ||
            destination.targetTable != target.definition.runtimeType) {
          throw ArgumentError(
            'Relation ${table.tableName}.${entry.key} has incompatible through selectors.',
          );
        }
        continue;
      }
      if (relation.kind == VoxelRelationKind.many && relation.inverseRelation == null) {
        final candidates = target.relations.values
            .where(
              (candidate) =>
                  candidate.kind == VoxelRelationKind.one &&
                  candidate.targetTable == table.definition.runtimeType,
            )
            .toList(growable: false);
        if (candidates.length != 1) {
          throw ArgumentError(
            'Relation ${table.tableName}.${entry.key} requires exactly one inverse relation; '
            'found ${candidates.length}.',
          );
        }
        relation.inverseRelation = candidates.single;
      }
      if (relation.kind == VoxelRelationKind.one) {
        if (relation.fields.isEmpty ||
            relation.fields.length != relation.references.length ||
            relation.fields.any((column) => !table.columns.contains(column)) ||
            relation.references.any((column) => !target.columns.contains(column))) {
          throw ArgumentError(
            'Relation ${table.tableName}.${entry.key} has an invalid column mapping.',
          );
        }
        for (var index = 0; index < relation.fields.length; index++) {
          if (relation.fields[index].codec.cast != relation.references[index].codec.cast) {
            throw ArgumentError(
              'Relation ${table.tableName}.${entry.key} maps incompatible storage types.',
            );
          }
        }
      }
      final inverse = relation.inverseRelation;
      if (inverse != null &&
          (!target.relations.values.contains(inverse) ||
              inverse.targetTable != table.definition.runtimeType)) {
        throw ArgumentError(
          'Relation ${table.tableName}.${entry.key} selects an invalid inverse relation.',
        );
      }
    }
  }
}

/// Base class used by annotated table declarations.
abstract class VoxelTableDefinition<Self> {
  VoxelOrderableColumnBuilder<String> text({String? name, String? renamedFrom}) =>
      VoxelOrderableColumnBuilder(VoxelTextCodec(), name: name, renamedFrom: renamedFrom);

  VoxelOrderableColumnBuilder<String> chronoID({
    String? prefix,
    int size = 24,
    String? name,
    String? renamedFrom,
  }) => VoxelOrderableColumnBuilder(
    VoxelChronoIdCodec(prefix: prefix, size: size),
    name: name,
    renamedFrom: renamedFrom,
  )..defaultValue(() => ChronoID.generate(prefix: prefix, size: size));

  VoxelOrderableColumnBuilder<int> integer({String? name, String? renamedFrom}) =>
      VoxelOrderableColumnBuilder(VoxelIntegerCodec(), name: name, renamedFrom: renamedFrom);

  VoxelOrderableColumnBuilder<double> real({String? name, String? renamedFrom}) =>
      VoxelOrderableColumnBuilder(VoxelRealCodec(), name: name, renamedFrom: renamedFrom);

  VoxelOrderableColumnBuilder<bool> boolean({String? name, String? renamedFrom}) =>
      VoxelOrderableColumnBuilder(VoxelBooleanCodec(), name: name, renamedFrom: renamedFrom);

  VoxelOrderableColumnBuilder<DateTime> dateTime({String? name, String? renamedFrom}) =>
      VoxelOrderableColumnBuilder(VoxelDateTimeCodec(), name: name, renamedFrom: renamedFrom);

  VoxelColumnBuilder<JsonValue> json({String? name, String? renamedFrom}) =>
      VoxelColumnBuilder(VoxelJsonCodec(), name: name, renamedFrom: renamedFrom);

  VoxelOrderableColumnBuilder<E> enumText<E extends Enum>({
    String? name,
    String? renamedFrom,
  }) => VoxelOrderableColumnBuilder(
    VoxelUnconfiguredEnumCodec<E>(),
    name: name,
    renamedFrom: renamedFrom,
  );

  VoxelColumnBuilder<Float32List> vector({
    required int dimensions,
    String? name,
    String? renamedFrom,
  }) => VoxelColumnBuilder(
    VoxelVectorCodec(dimensions),
    name: name,
    renamedFrom: renamedFrom,
  );

  VoxelRelationBuilder<Target, VoxelOneRelation<Target>> one<Target>({
    required List<VoxelColumn<dynamic>> fields,
    required List<VoxelColumn<dynamic>> Function(Target table) references,
  }) => VoxelRelationBuilder(
    VoxelOneRelation(Target, fields: List.unmodifiable(fields), references: references),
  );

  VoxelManyRelationBuilder<Target> many<Target>({
    VoxelRelationDescriptor<dynamic> Function(Target table)? relation,
  }) => VoxelManyRelationBuilder(VoxelManyRelation(Target, relation: relation));

  VoxelIndexBuilder index(String name) => VoxelIndexBuilder(name, unique: false);
  VoxelIndexBuilder uniqueIndex(String name) => VoxelIndexBuilder(name, unique: true);
  VoxelConstraint check(String name, VoxelPredicate predicate) => VoxelConstraint(
    name: name,
    kind: VoxelConstraintKind.check,
    expression: predicate.sql,
    predicate: predicate,
  );
}

enum VoxelReferentialAction { noAction, restrict, cascade, setNull, setDefault }

enum VoxelConstraintKind { check, primaryKey, foreignKey }

final class VoxelForeignKey {
  VoxelForeignKey({
    required this.targetTable,
    required this.reference,
    required this.onDelete,
    required this.onUpdate,
  });

  final Type targetTable;
  final VoxelColumn<dynamic> Function(Object table) reference;
  final VoxelReferentialAction onDelete;
  final VoxelReferentialAction onUpdate;
  VoxelColumn<dynamic>? referencedColumn;
}

final class VoxelConstraint {
  const VoxelConstraint({
    required this.name,
    required this.kind,
    this.expression,
    this.predicate,
  });

  final String name;
  final VoxelConstraintKind kind;
  final String? expression;
  final VoxelPredicate? predicate;
}

final class VoxelIndex {
  const VoxelIndex({required this.name, required this.unique, required this.terms, this.predicate});

  final String name;
  final bool unique;
  final List<VoxelIndexTerm> terms;
  final VoxelPredicate? predicate;
}

final class VoxelIndexTerm {
  const VoxelIndexTerm(this.column, {this.descending = false});

  final VoxelColumn<dynamic> column;
  final bool descending;
}

final class VoxelIndexBuilder {
  const VoxelIndexBuilder(this.name, {required this.unique, this.predicate});

  final String name;
  final bool unique;
  final VoxelPredicate? predicate;

  VoxelIndexBuilder where(VoxelPredicate value) =>
      VoxelIndexBuilder(name, unique: unique, predicate: value);

  VoxelIndex on(List<Object> terms) => VoxelIndex(
    name: name,
    unique: unique,
    terms: [
      for (final term in terms)
        switch (term) {
          VoxelIndexTerm() => term,
          VoxelOrder() => VoxelIndexTerm(term.column, descending: term.descending),
          VoxelColumn<dynamic>() => VoxelIndexTerm(term),
          _ => throw ArgumentError.value(term, 'terms', 'must be a Voxel column or index term'),
        },
    ],
    predicate: predicate,
  );
}

/// Builds a generated table schema without retaining a live executor.
// The accessor is the generated package-composition boundary.
// ignore: one_member_abstracts
abstract class VoxelTableAccessor<Definition, Row> {
  const VoxelTableAccessor();

  VoxelTableSchema<Definition, Row> buildSchema();
}

/// Converts values at the Turso boundary.
abstract class VoxelCodec<T> {
  const VoxelCodec();

  String get cast;
  bool get acceptsNull => false;
  bool get encodesJsonValue => false;
  String select(String columnSql) => columnSql;
  Object? encode(T value);
  T decode(Object? value, {required bool isSqlNull});

  VoxelCodec<T> configureEnum<E extends Enum>(VoxelEnumCodec<E> enumCodec) => this;
}

final class VoxelTextCodec extends VoxelCodec<String> {
  @override
  String get cast => 'text';

  @override
  Object encode(String value) => value;

  @override
  String decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String) {
      throw const FormatException('expected a non-null Turso text value');
    }
    return value;
  }
}

final class VoxelNullableCodec<T> extends VoxelCodec<T?> {
  const VoxelNullableCodec(this.inner);

  final VoxelCodec<T> inner;

  @override
  String get cast => inner.cast;

  @override
  bool get acceptsNull => true;

  @override
  bool get encodesJsonValue => inner.encodesJsonValue;

  @override
  String select(String columnSql) => inner.select(columnSql);

  @override
  Object? encode(T? value) => value == null ? null : inner.encode(value);

  @override
  T? decode(Object? value, {required bool isSqlNull}) =>
      isSqlNull ? null : inner.decode(value, isSqlNull: false);

  @override
  VoxelCodec<T?> configureEnum<E extends Enum>(VoxelEnumCodec<E> enumCodec) =>
      VoxelNullableCodec(inner.configureEnum(enumCodec));
}

final class VoxelChronoIdCodec extends VoxelCodec<String> {
  const VoxelChronoIdCodec({this.prefix, this.size = 24});

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

final class VoxelIntegerCodec extends VoxelCodec<int> {
  static const min = -2147483648;
  static const max = 2147483647;

  @override
  String get cast => 'integer';

  @override
  Object encode(int value) {
    _validate(value);
    return BigInt.from(value);
  }

  @override
  int decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! BigInt) throw const FormatException('expected a Turso INTEGER');
    if (value < BigInt.from(min) || value > BigInt.from(max)) {
      throw RangeError('integer must fit a signed 32-bit integer');
    }
    return value.toInt();
  }

  void _validate(int value) {
    if (value < min || value > max) throw RangeError.range(value, min, max, 'integer');
  }
}

final class VoxelRealCodec extends VoxelCodec<double> {
  @override
  String get cast => 'real';

  @override
  Object encode(double value) {
    if (!value.isFinite) throw const FormatException('real values must be finite');
    return value;
  }

  @override
  double decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! num) {
      throw const FormatException('expected a Turso DOUBLE PRECISION');
    }
    final decoded = value.toDouble();
    if (!decoded.isFinite) throw const FormatException('real values must be finite');
    return decoded;
  }
}

final class VoxelBooleanCodec extends VoxelCodec<bool> {
  @override
  String get cast => 'integer';

  @override
  Object encode(bool value) => value ? BigInt.one : BigInt.zero;

  @override
  bool decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! BigInt || (value != BigInt.zero && value != BigInt.one)) {
      throw const FormatException('expected a Turso INTEGER boolean (0 or 1)');
    }
    return value == BigInt.one;
  }
}

final class VoxelDateTimeCodec extends VoxelCodec<DateTime> {
  @override
  String get cast => 'integer';

  @override
  Object encode(DateTime value) => BigInt.from(_milliseconds(value).millisecondsSinceEpoch);

  @override
  DateTime decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! BigInt) {
      throw const FormatException('expected a Turso epoch-millisecond INTEGER');
    }
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
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
  bool operator ==(Object other) => other is JsonData && _jsonEquals(other.value, value);

  @override
  int get hashCode => _jsonHash(value);
}

final class VoxelJsonCodec extends VoxelCodec<JsonValue> {
  @override
  String get cast => 'text';

  @override
  bool get encodesJsonValue => true;

  @override
  Object encode(JsonValue value) => jsonEncode(value.toDart());

  @override
  JsonValue decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String) {
      throw const FormatException('expected non-null Turso JSON text');
    }
    try {
      return JsonValue.from(jsonDecode(value));
    } on Object catch (error) {
      throw FormatException('invalid JSON text', error);
    }
  }
}

final class VoxelUnconfiguredEnumCodec<E extends Enum> extends VoxelCodec<E> {
  @override
  String get cast => 'text';

  @override
  Object encode(E value) => throw StateError('The generated enum codec was not attached.');

  @override
  E decode(Object? value, {required bool isSqlNull}) =>
      throw StateError('The generated enum codec was not attached.');

  @override
  VoxelCodec<E> configureEnum<Configured extends Enum>(
    VoxelEnumCodec<Configured> enumCodec,
  ) {
    if (Configured != E) return this;
    return enumCodec as VoxelCodec<E>;
  }
}

final class VoxelEnumCodec<E extends Enum> extends VoxelCodec<E> {
  const VoxelEnumCodec({
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
  String get cast => 'text';

  @override
  Object encode(E value) {
    final index = values.indexOf(value);
    if (index < 0) throw ArgumentError.value(value, 'value', 'is not registered');
    return labels[index];
  }

  @override
  E decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String) throw const FormatException('expected an enum TEXT label');
    final index = labels.indexOf(value);
    if (index < 0) throw FormatException('unknown native enum label `$value`');
    return values[index];
  }
}

final class VoxelVectorCodec extends VoxelCodec<Float32List> {
  VoxelVectorCodec(this.dimensions) {
    if (dimensions <= 0 || dimensions > 16000) {
      throw RangeError.range(dimensions, 1, 16000, 'dimensions');
    }
  }

  final int dimensions;

  @override
  String get cast => 'f32_blob';

  @override
  Object encode(Float32List value) {
    final checked = _validate(value);
    return '[${checked.join(',')}]';
  }

  @override
  Float32List decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String || !value.startsWith('[') || !value.endsWith(']')) {
      throw const FormatException('expected a non-null Turso vector text value');
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

bool _jsonEquals(Object? left, Object? right) {
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || !_jsonEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) => switch (value) {
  final List<Object?> list => Object.hashAll(list.map(_jsonHash)),
  final Map<String, Object?> map => Object.hashAllUnordered(
    map.entries.map((entry) => Object.hash(entry.key, _jsonHash(entry.value))),
  ),
  _ => value.hashCode,
};

abstract interface class VoxelTypeConverter<Domain, Storage> {
  Domain fromSql(Storage value);
  Storage toSql(Domain value);
}

final class VoxelMappedCodec<Domain, Storage> extends VoxelCodec<Domain> {
  const VoxelMappedCodec(this.storage, this.converter);

  final VoxelCodec<Storage> storage;
  final VoxelTypeConverter<Domain, Storage> converter;

  @override
  String get cast => storage.cast;

  @override
  bool get acceptsNull => storage.acceptsNull;

  @override
  bool get encodesJsonValue => storage.encodesJsonValue;

  @override
  String select(String columnSql) => storage.select(columnSql);

  @override
  Object? encode(Domain value) => storage.encode(converter.toSql(value));

  @override
  Domain decode(Object? value, {required bool isSqlNull}) =>
      converter.fromSql(storage.decode(value, isSqlNull: isSqlNull));

  @override
  VoxelCodec<Domain> configureEnum<E extends Enum>(VoxelEnumCodec<E> enumCodec) =>
      VoxelMappedCodec(storage.configureEnum(enumCodec), converter);
}

final class _VoxelColumnMetadata {
  _VoxelColumnMetadata({
    this.isPrimaryKey = false,
    this.foreignKey,
    this.sqlDefault,
    this.defaultFn,
    this.onUpdateFn,
  });

  bool isPrimaryKey;
  VoxelForeignKey? foreignKey;
  String? sqlDefault;
  Object? Function()? defaultFn;
  Object? Function()? onUpdateFn;

  _VoxelColumnMetadata copy() => _VoxelColumnMetadata(
    isPrimaryKey: isPrimaryKey,
    foreignKey: foreignKey,
    sqlDefault: sqlDefault,
    defaultFn: defaultFn,
    onUpdateFn: onUpdateFn,
  );

  _VoxelColumnMetadata mapped<Domain, Storage>(
    VoxelTypeConverter<Domain, Storage> converter,
  ) => _VoxelColumnMetadata(
    isPrimaryKey: isPrimaryKey,
    foreignKey: foreignKey,
    sqlDefault: sqlDefault,
    defaultFn: defaultFn == null ? null : () => converter.fromSql(defaultFn!() as Storage),
    onUpdateFn: onUpdateFn == null ? null : () => converter.fromSql(onUpdateFn!() as Storage),
  );

  Column apply<Column extends VoxelColumn<dynamic>>(Column column) {
    column
      ..isPrimaryKey = isPrimaryKey
      ..foreignKey = foreignKey
      ..sqlDefault = sqlDefault
      ..defaultFn = defaultFn
      ..onUpdateFn = onUpdateFn;
    return column;
  }
}

VoxelForeignKey _foreignKey<Target>(
  VoxelColumn<dynamic> Function(Target table) reference,
  VoxelReferentialAction onDelete,
  VoxelReferentialAction onUpdate,
) => VoxelForeignKey(
  targetTable: Target,
  reference: (table) => reference(table as Target),
  onDelete: onDelete,
  onUpdate: onUpdate,
);

class VoxelColumnBuilder<T> {
  VoxelColumnBuilder(
    this.codec, {
    this.name,
    this.renamedFrom,
    _VoxelColumnMetadata? metadata,
  }) : _metadata = metadata ?? _VoxelColumnMetadata();

  final VoxelCodec<T> codec;
  final String? name;
  final String? renamedFrom;
  final _VoxelColumnMetadata _metadata;

  VoxelColumn<T> call() => _metadata.apply(
    VoxelColumn(codec, declaredName: name, renamedFrom: renamedFrom),
  );

  VoxelColumnBuilder<T?> nullable() => VoxelColumnBuilder(
    VoxelNullableCodec(codec),
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.copy(),
  );

  VoxelMappedColumnBuilder<Domain, T> map<Domain>(
    VoxelTypeConverter<Domain, T> converter,
  ) => VoxelMappedColumnBuilder(
    codec,
    converter,
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.mapped(converter),
  );

  VoxelArrayColumnBuilder<T> array() => VoxelArrayColumnBuilder(
    codec,
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.copy(),
  );

  VoxelColumnBuilder<T> primaryKey() {
    _metadata.isPrimaryKey = true;
    return this;
  }

  VoxelColumnBuilder<T> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    _metadata.foreignKey = _foreignKey(reference, onDelete, onUpdate);
    return this;
  }

  VoxelColumnBuilder<T> defaultSql(String sql) {
    _metadata.sqlDefault = sql;
    return this;
  }

  VoxelColumnBuilder<T> defaultValue(T Function() value) {
    _metadata.defaultFn = value;
    return this;
  }

  VoxelColumnBuilder<T> onUpdate(T Function() value) {
    _metadata.onUpdateFn = value;
    return this;
  }
}

class VoxelMappedColumn<Domain, Storage> extends VoxelColumn<Domain> {
  VoxelMappedColumn(
    super.codec,
    this.storage, {
    super.declaredName,
    super.renamedFrom,
  });

  final VoxelColumn<Storage> storage;

  @override
  void attach<Definition, Row>(
    VoxelTableSchema<Definition, Row> table, {
    String? dartName,
    String? qualifier,
  }) {
    super.attach(table, dartName: dartName, qualifier: qualifier);
    storage.attach(table, dartName: dartName, qualifier: qualifier);
  }

  @override
  void configureEnum<E extends Enum>(VoxelEnumCodec<E> enumCodec) {
    super.configureEnum(enumCodec);
    storage.configureEnum(enumCodec);
  }
}

final class VoxelOrderableMappedColumn<Domain, Storage> extends VoxelMappedColumn<Domain, Storage> {
  VoxelOrderableMappedColumn(
    super.codec,
    VoxelOrderableColumn<Storage> super.storage, {
    super.declaredName,
    super.renamedFrom,
  });

  @override
  VoxelOrderableColumn<Storage> get storage => super.storage as VoxelOrderableColumn<Storage>;
}

class VoxelMappedColumnBuilder<Domain, Storage> {
  VoxelMappedColumnBuilder(
    this.storageCodec,
    this.converter, {
    this.name,
    this.renamedFrom,
    _VoxelColumnMetadata? metadata,
  }) : _metadata = metadata ?? _VoxelColumnMetadata();

  final VoxelCodec<Storage> storageCodec;
  final VoxelTypeConverter<Domain, Storage> converter;
  final String? name;
  final String? renamedFrom;
  final _VoxelColumnMetadata _metadata;

  VoxelMappedColumnBuilder<Domain?, Storage?> nullable() => VoxelMappedColumnBuilder(
    VoxelNullableCodec(storageCodec),
    _NullableConverter(converter),
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.copy(),
  );

  VoxelMappedColumn<Domain, Storage> call() => _metadata.apply(
    VoxelMappedColumn(
      VoxelMappedCodec(storageCodec, converter),
      VoxelColumn(storageCodec, declaredName: name, renamedFrom: renamedFrom),
      declaredName: name,
      renamedFrom: renamedFrom,
    ),
  );

  VoxelMappedArrayColumnBuilder<Domain, Storage> array() => VoxelMappedArrayColumnBuilder(
    storageCodec,
    converter,
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.copy(),
  );

  VoxelMappedColumnBuilder<Domain, Storage> primaryKey() {
    _metadata.isPrimaryKey = true;
    return this;
  }

  VoxelMappedColumnBuilder<Domain, Storage> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    _metadata.foreignKey = _foreignKey(reference, onDelete, onUpdate);
    return this;
  }

  VoxelMappedColumnBuilder<Domain, Storage> defaultSql(String sql) {
    _metadata.sqlDefault = sql;
    return this;
  }

  VoxelMappedColumnBuilder<Domain, Storage> defaultValue(Domain Function() value) {
    _metadata.defaultFn = value;
    return this;
  }

  VoxelMappedColumnBuilder<Domain, Storage> onUpdate(Domain Function() value) {
    _metadata.onUpdateFn = value;
    return this;
  }
}

final class VoxelOrderableMappedColumnBuilder<Domain, Storage>
    extends VoxelMappedColumnBuilder<Domain, Storage> {
  VoxelOrderableMappedColumnBuilder(
    super.storageCodec,
    super.converter, {
    super.name,
    super.renamedFrom,
    super.metadata,
  });

  @override
  VoxelOrderableMappedColumn<Domain, Storage> call() => _metadata.apply(
    VoxelOrderableMappedColumn(
      VoxelMappedCodec(storageCodec, converter),
      VoxelOrderableColumn(storageCodec, declaredName: name, renamedFrom: renamedFrom),
      declaredName: name,
      renamedFrom: renamedFrom,
    ),
  );

  @override
  VoxelOrderableMappedColumnBuilder<Domain?, Storage?> nullable() =>
      VoxelOrderableMappedColumnBuilder(
        VoxelNullableCodec(storageCodec),
        _NullableConverter(converter),
        name: name,
        renamedFrom: renamedFrom,
        metadata: _metadata.copy(),
      );

  @override
  VoxelOrderableMappedColumnBuilder<Domain, Storage> primaryKey() {
    super.primaryKey();
    return this;
  }

  @override
  VoxelOrderableMappedColumnBuilder<Domain, Storage> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    super.references(reference, onDelete: onDelete, onUpdate: onUpdate);
    return this;
  }

  @override
  VoxelOrderableMappedColumnBuilder<Domain, Storage> defaultSql(String sql) {
    super.defaultSql(sql);
    return this;
  }

  @override
  VoxelOrderableMappedColumnBuilder<Domain, Storage> defaultValue(
    Domain Function() value,
  ) {
    super.defaultValue(value);
    return this;
  }

  @override
  VoxelOrderableMappedColumnBuilder<Domain, Storage> onUpdate(
    Domain Function() value,
  ) {
    super.onUpdate(value);
    return this;
  }
}

final class _NullableConverter<Domain, Storage> implements VoxelTypeConverter<Domain?, Storage?> {
  const _NullableConverter(this.inner);

  final VoxelTypeConverter<Domain, Storage> inner;

  @override
  Domain? fromSql(Storage? value) => value == null ? null : inner.fromSql(value);

  @override
  Storage? toSql(Domain? value) => value == null ? null : inner.toSql(value);
}

final class _ListConverter<Domain, Storage>
    implements VoxelTypeConverter<List<Domain>, List<Storage>> {
  const _ListConverter(this.inner);

  final VoxelTypeConverter<Domain, Storage> inner;

  @override
  List<Domain> fromSql(List<Storage> value) => [
    for (final element in value) inner.fromSql(element),
  ];

  @override
  List<Storage> toSql(List<Domain> value) => [
    for (final element in value) inner.toSql(element),
  ];
}

final class VoxelMappedArrayColumnBuilder<Domain, Storage> {
  VoxelMappedArrayColumnBuilder(
    this.elementStorageCodec,
    this.elementConverter, {
    this.name,
    this.renamedFrom,
    _VoxelColumnMetadata? metadata,
  }) : _metadata = metadata ?? _VoxelColumnMetadata();

  final VoxelCodec<Storage> elementStorageCodec;
  final VoxelTypeConverter<Domain, Storage> elementConverter;
  final String? name;
  final String? renamedFrom;
  final _VoxelColumnMetadata _metadata;

  VoxelMappedColumn<List<Domain>, List<Storage>> call() {
    final storageCodec = VoxelArrayCodec(elementStorageCodec);
    return _metadata.apply(
      VoxelMappedColumn(
        VoxelMappedCodec(storageCodec, _ListConverter(elementConverter)),
        VoxelColumn(storageCodec, declaredName: name, renamedFrom: renamedFrom),
        declaredName: name,
        renamedFrom: renamedFrom,
      ),
    );
  }

  VoxelNullableMappedArrayColumnBuilder<Domain, Storage> nullable() =>
      VoxelNullableMappedArrayColumnBuilder(
        elementStorageCodec,
        elementConverter,
        name: name,
        renamedFrom: renamedFrom,
        metadata: _metadata.copy(),
      );

  VoxelMappedArrayColumnBuilder<Domain, Storage> primaryKey() {
    _metadata.isPrimaryKey = true;
    return this;
  }

  VoxelMappedArrayColumnBuilder<Domain, Storage> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    _metadata.foreignKey = _foreignKey(reference, onDelete, onUpdate);
    return this;
  }

  VoxelMappedArrayColumnBuilder<Domain, Storage> defaultSql(String sql) {
    _metadata.sqlDefault = sql;
    return this;
  }

  VoxelMappedArrayColumnBuilder<Domain, Storage> defaultValue(
    List<Domain> Function() value,
  ) {
    _metadata.defaultFn = value;
    return this;
  }

  VoxelMappedArrayColumnBuilder<Domain, Storage> onUpdate(
    List<Domain> Function() value,
  ) {
    _metadata.onUpdateFn = value;
    return this;
  }
}

final class VoxelNullableMappedArrayColumnBuilder<Domain, Storage> {
  VoxelNullableMappedArrayColumnBuilder(
    this.elementStorageCodec,
    this.elementConverter, {
    this.name,
    this.renamedFrom,
    _VoxelColumnMetadata? metadata,
  }) : _metadata = metadata ?? _VoxelColumnMetadata();

  final VoxelCodec<Storage> elementStorageCodec;
  final VoxelTypeConverter<Domain, Storage> elementConverter;
  final String? name;
  final String? renamedFrom;
  final _VoxelColumnMetadata _metadata;

  VoxelMappedColumn<List<Domain>?, List<Storage>?> call() {
    final storageCodec = VoxelArrayCodec(elementStorageCodec);
    return _metadata.apply(
      VoxelMappedColumn(
        VoxelMappedCodec(
          VoxelNullableCodec(storageCodec),
          _NullableConverter(_ListConverter(elementConverter)),
        ),
        VoxelColumn(
          VoxelNullableCodec(storageCodec),
          declaredName: name,
          renamedFrom: renamedFrom,
        ),
        declaredName: name,
        renamedFrom: renamedFrom,
      ),
    );
  }

  VoxelNullableMappedArrayColumnBuilder<Domain, Storage> primaryKey() {
    _metadata.isPrimaryKey = true;
    return this;
  }

  VoxelNullableMappedArrayColumnBuilder<Domain, Storage> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    _metadata.foreignKey = _foreignKey(reference, onDelete, onUpdate);
    return this;
  }

  VoxelNullableMappedArrayColumnBuilder<Domain, Storage> defaultSql(String sql) {
    _metadata.sqlDefault = sql;
    return this;
  }

  VoxelNullableMappedArrayColumnBuilder<Domain, Storage> defaultValue(
    List<Domain>? Function() value,
  ) {
    _metadata.defaultFn = value;
    return this;
  }

  VoxelNullableMappedArrayColumnBuilder<Domain, Storage> onUpdate(
    List<Domain>? Function() value,
  ) {
    _metadata.onUpdateFn = value;
    return this;
  }
}

/// A typed SQL expression that can be rendered with bound Turso values.
abstract interface class VoxelExpression<T> {
  String get sql;
  List<Object?> get parameters;
  List<VoxelColumn<dynamic>> get columns;
  VoxelCodec<T> get codec;
  bool get referencesRows;

  String renderPlaceholders(String Function(int index) placeholder);
  String renderParameters({int startAt = 1});
}

final class _VoxelBoundExpression<T> implements VoxelExpression<T> {
  _VoxelBoundExpression(this.source, T value) : parameters = [source.encodeValue(value)];

  final VoxelColumn<T> source;

  @override
  VoxelCodec<T> get codec => source.codec;

  @override
  List<VoxelColumn<dynamic>> get columns => [source];

  @override
  final List<Object?> parameters;

  @override
  bool get referencesRows => false;

  @override
  String get sql => renderPlaceholders((_) => '@value');

  @override
  String renderPlaceholders(String Function(int index) placeholder) =>
      '${placeholder(0)}::${codec.cast}';

  @override
  String renderParameters({int startAt = 1}) =>
      renderPlaceholders((index) => '\$${startAt + index}');
}

final class _VoxelBinaryExpression<T> implements VoxelExpression<T> {
  _VoxelBinaryExpression(this.left, this.operator, T right)
    : _right = left.columns.first.encodeValue(right);

  final VoxelExpression<T> left;
  final String operator;
  final Object? _right;

  @override
  VoxelCodec<T> get codec => left.codec;

  @override
  List<VoxelColumn<dynamic>> get columns => left.columns;

  @override
  List<Object?> get parameters => [...left.parameters, _right];

  @override
  bool get referencesRows => left.referencesRows;

  @override
  String get sql => renderPlaceholders((_) => '@value');

  @override
  String renderPlaceholders(String Function(int index) placeholder) =>
      '(${left.renderPlaceholders(placeholder)} $operator '
      '${placeholder(left.parameters.length)}::${codec.cast})';

  @override
  String renderParameters({int startAt = 1}) =>
      renderPlaceholders((index) => '\$${startAt + index}');
}

/// A typed SQL expression backed by a table column.
class VoxelColumn<T> implements VoxelExpression<T> {
  VoxelColumn(this.codec, {this.declaredName, this.renamedFrom});

  @override
  VoxelCodec<T> codec;
  final String? declaredName;
  final String? renamedFrom;
  bool isPrimaryKey = false;
  VoxelForeignKey? foreignKey;
  String? sqlDefault;
  Object? Function()? defaultFn;
  Object? Function()? onUpdateFn;
  late final String dartName;
  late final VoxelTableSchema<Object?, Object?> _table;
  String? _qualifier;

  void attach<Definition, Row>(
    VoxelTableSchema<Definition, Row> table, {
    String? dartName,
    String? qualifier,
  }) {
    this.dartName =
        dartName ?? declaredName ?? (throw StateError('Missing generated column name.'));
    _table = table as VoxelTableSchema<Object?, Object?>;
    _qualifier = qualifier;
  }

  String get physicalName => declaredName ?? dartName;
  @override
  String get sql => [
    if (_qualifier case final qualifier?) quoteIdentifier(qualifier),
    quoteIdentifier(physicalName),
  ].join('.');
  String get selectionSql => codec.select(sql);
  bool belongsTo(VoxelTableSchema<Object?, Object?> table) => identical(_table, table);

  @override
  List<Object?> get parameters => const [];

  @override
  List<VoxelColumn<dynamic>> get columns => [this];

  @override
  bool get referencesRows => true;

  @override
  String renderPlaceholders(String Function(int index) placeholder) => sql;

  @override
  String renderParameters({int startAt = 1}) => sql;

  void configureEnum<E extends Enum>(VoxelEnumCodec<E> enumCodec) {
    codec = codec.configureEnum(enumCodec);
  }

  VoxelPredicate equals(T value) {
    if (value == null) return VoxelPredicate._raw('$sql IS NULL', [this]);
    final encoded = _convert('encode', () => codec.encode(value));
    return VoxelPredicate._value('$sql = ', '::${codec.cast}', encoded, [this]);
  }

  T decodeValue(Object? value, {required bool isSqlNull}) =>
      _convert('decode', () => codec.decode(value, isSqlNull: isSqlNull));

  Object? encodeValue(Object? value) => _convert(
    'encode',
    () => (codec as VoxelCodec<Object?>).encode(value),
  );

  VoxelExpression<T> value(T value) => _VoxelBoundExpression(this, value);

  R _convert<R>(String operation, R Function() convert) {
    try {
      return convert();
    } on VoxelException {
      rethrow;
    } on Object catch (error) {
      throw VoxelConversionException(
        table: '${_table.schemaName}.${_table.tableName}',
        column: physicalName,
        message: 'Failed to $operation value.',
        cause: error,
      );
    }
  }
}

/// A column that supports SQL ordering.
final class VoxelOrderableColumn<T> extends VoxelColumn<T> {
  VoxelOrderableColumn(super.codec, {super.declaredName, super.renamedFrom});

  VoxelOrder asc({NullsOrder nulls = NullsOrder.last}) =>
      VoxelOrder(this, descending: false, nulls: nulls);
  VoxelOrder desc({NullsOrder nulls = NullsOrder.last}) =>
      VoxelOrder(this, descending: true, nulls: nulls);
}

extension VoxelIntegerExpression on VoxelExpression<int> {
  VoxelExpression<int> operator +(int value) {
    return _VoxelBinaryExpression(this, '+', value);
  }
}

extension VoxelExpressionComparison<T> on VoxelExpression<T> {
  VoxelPredicate lessThanExpression(VoxelExpression<T> other) =>
      VoxelPredicate._comparison(this, '<', other);
}

/// Builder used by table declaration fields such as `text()()`.
class VoxelOrderableColumnBuilder<T> {
  VoxelOrderableColumnBuilder(
    this.codec, {
    this.name,
    this.renamedFrom,
    _VoxelColumnMetadata? metadata,
  }) : _metadata = metadata ?? _VoxelColumnMetadata();

  final VoxelCodec<T> codec;
  final String? name;
  final String? renamedFrom;
  final _VoxelColumnMetadata _metadata;

  VoxelOrderableColumnBuilder<T?> nullable() => VoxelOrderableColumnBuilder(
    VoxelNullableCodec(codec),
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.copy(),
  );

  VoxelOrderableMappedColumnBuilder<Domain, T> map<Domain>(
    VoxelTypeConverter<Domain, T> converter,
  ) => VoxelOrderableMappedColumnBuilder(
    codec,
    converter,
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.mapped(converter),
  );

  VoxelArrayColumnBuilder<T> array() => VoxelArrayColumnBuilder(
    codec,
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.copy(),
  );

  VoxelOrderableColumnBuilder<T> primaryKey() {
    _metadata.isPrimaryKey = true;
    // Schema modifiers preserve the builder's accumulated metadata.
    return this;
  }

  VoxelOrderableColumnBuilder<T> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    _metadata.foreignKey = _foreignKey(reference, onDelete, onUpdate);
    // Schema modifiers preserve the builder's accumulated metadata.
    return this;
  }

  VoxelOrderableColumnBuilder<T> defaultSql(String sql) {
    _metadata.sqlDefault = sql;
    // Schema modifiers preserve the builder's accumulated metadata.
    return this;
  }

  VoxelOrderableColumnBuilder<T> defaultValue(T Function() value) {
    _metadata.defaultFn = value;
    // Schema modifiers preserve the builder's accumulated metadata.
    return this;
  }

  VoxelOrderableColumnBuilder<T> onUpdate(T Function() value) {
    _metadata.onUpdateFn = value;
    // Schema modifiers preserve the builder's accumulated metadata.
    return this;
  }

  VoxelOrderableColumn<T> call() => _metadata.apply(
    VoxelOrderableColumn<T>(codec, declaredName: name, renamedFrom: renamedFrom),
  );
}

final class VoxelArrayColumnBuilder<Element> {
  VoxelArrayColumnBuilder(
    this.elementCodec, {
    this.name,
    this.renamedFrom,
    _VoxelColumnMetadata? metadata,
  }) : _metadata = metadata ?? _VoxelColumnMetadata();

  final VoxelCodec<Element> elementCodec;
  final String? name;
  final String? renamedFrom;
  final _VoxelColumnMetadata _metadata;

  VoxelColumn<List<Element>> call() => _metadata.apply(
    VoxelColumn(
      VoxelArrayCodec(elementCodec),
      declaredName: name,
      renamedFrom: renamedFrom,
    ),
  );

  VoxelNullableArrayColumnBuilder<Element> nullable() => VoxelNullableArrayColumnBuilder(
    VoxelNullableCodec(VoxelArrayCodec(elementCodec)),
    name: name,
    renamedFrom: renamedFrom,
    metadata: _metadata.copy(),
  );

  VoxelArrayColumnBuilder<Element> primaryKey() {
    _metadata.isPrimaryKey = true;
    return this;
  }

  VoxelArrayColumnBuilder<Element> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    _metadata.foreignKey = _foreignKey(reference, onDelete, onUpdate);
    return this;
  }

  VoxelArrayColumnBuilder<Element> defaultSql(String sql) {
    _metadata.sqlDefault = sql;
    return this;
  }

  VoxelArrayColumnBuilder<Element> defaultValue(List<Element> Function() value) {
    _metadata.defaultFn = value;
    return this;
  }

  VoxelArrayColumnBuilder<Element> onUpdate(List<Element> Function() value) {
    _metadata.onUpdateFn = value;
    return this;
  }
}

final class VoxelNullableArrayColumnBuilder<Element> {
  VoxelNullableArrayColumnBuilder(
    this.codec, {
    this.name,
    this.renamedFrom,
    _VoxelColumnMetadata? metadata,
  }) : _metadata = metadata ?? _VoxelColumnMetadata();

  final VoxelCodec<List<Element>?> codec;
  final String? name;
  final String? renamedFrom;
  final _VoxelColumnMetadata _metadata;

  VoxelColumn<List<Element>?> call() => _metadata.apply(
    VoxelColumn(codec, declaredName: name, renamedFrom: renamedFrom),
  );

  VoxelNullableArrayColumnBuilder<Element> primaryKey() {
    _metadata.isPrimaryKey = true;
    return this;
  }

  VoxelNullableArrayColumnBuilder<Element> references<Target>(
    VoxelColumn<dynamic> Function(Target table) reference, {
    VoxelReferentialAction onDelete = VoxelReferentialAction.noAction,
    VoxelReferentialAction onUpdate = VoxelReferentialAction.noAction,
  }) {
    _metadata.foreignKey = _foreignKey(reference, onDelete, onUpdate);
    return this;
  }

  VoxelNullableArrayColumnBuilder<Element> defaultSql(String sql) {
    _metadata.sqlDefault = sql;
    return this;
  }

  VoxelNullableArrayColumnBuilder<Element> defaultValue(
    List<Element>? Function() value,
  ) {
    _metadata.defaultFn = value;
    return this;
  }

  VoxelNullableArrayColumnBuilder<Element> onUpdate(
    List<Element>? Function() value,
  ) {
    _metadata.onUpdateFn = value;
    return this;
  }
}

final class VoxelArrayCodec<Element> extends VoxelCodec<List<Element>> {
  VoxelArrayCodec(this.elementCodec) {
    if (elementCodec is VoxelArrayCodec<dynamic>) {
      throw const FormatException('multidimensional arrays are not supported');
    }
  }

  final VoxelCodec<Element> elementCodec;

  @override
  String get cast => 'text';

  @override
  Object encode(List<Element> value) {
    final encoded = <Object?>[];
    for (final element in value) {
      if (element == null) {
        if (!elementCodec.acceptsNull) {
          throw const FormatException('array element must not be null');
        }
        encoded.add(null);
        continue;
      }
      final stored = elementCodec.encode(element);
      encoded.add(elementCodec.encodesJsonValue ? [jsonDecode(stored! as String)] : stored);
    }
    return jsonEncode(encoded);
  }

  @override
  VoxelCodec<List<Element>> configureEnum<E extends Enum>(VoxelEnumCodec<E> enumCodec) =>
      VoxelArrayCodec(elementCodec.configureEnum(enumCodec));

  @override
  List<Element> decode(Object? value, {required bool isSqlNull}) {
    if (isSqlNull || value is! String) {
      throw const FormatException('expected a one-dimensional JSON array in TEXT');
    }
    final Object? parsed;
    try {
      parsed = jsonDecode(value);
    } on Object catch (error) {
      throw FormatException('invalid array JSON text', error);
    }
    if (parsed is! List<Object?>) throw const FormatException('expected a JSON array');
    return [
      for (final stored in parsed) _decodeElement(stored),
    ];
  }

  Element _decodeElement(Object? stored) {
    if (stored == null) return elementCodec.decode(null, isSqlNull: true);
    if (elementCodec.encodesJsonValue) {
      if (stored is! List<Object?> || stored.length != 1) {
        throw const FormatException('expected a version 1 JSON element envelope');
      }
      return elementCodec.decode(jsonEncode(stored.single), isSqlNull: false);
    }
    final driverValue = switch (elementCodec.cast) {
      'integer' when stored is num && stored == stored.truncate() => BigInt.from(stored),
      'real' when stored is num => stored.toDouble(),
      _ => stored,
    };
    return elementCodec.decode(driverValue, isSqlNull: false);
  }
}

enum NullsOrder { first, last }

final class VoxelOrder {
  const VoxelOrder(this.column, {required this.descending, required this.nulls});

  final VoxelOrderableColumn<Object?> column;
  final bool descending;
  final NullsOrder nulls;
}

/// A parameterized SQL predicate produced by typed expressions.
final class VoxelPredicate {
  VoxelPredicate._(
    this._renderSql,
    List<Object?> parameters,
    List<VoxelColumn<dynamic>> columns,
  ) : parameters = List.unmodifiable(parameters),
      columns = List.unmodifiable(columns);

  VoxelPredicate._raw(String sql, List<VoxelColumn<dynamic>> columns)
    : this._((_) => sql, const [], columns);

  VoxelPredicate._value(
    String before,
    String after,
    Object? parameter,
    List<VoxelColumn<dynamic>> columns,
  ) : this._((placeholder) => '$before${placeholder(0)}$after', [parameter], columns);

  VoxelPredicate._comparison(
    VoxelExpression<dynamic> left,
    String operator,
    VoxelExpression<dynamic> right,
  ) : this._(
        (placeholder) =>
            '${left.renderPlaceholders(placeholder)} $operator '
            '${right.renderPlaceholders((index) => placeholder(left.parameters.length + index))}',
        [...left.parameters, ...right.parameters],
        [...left.columns, ...right.columns],
      );

  final String Function(String Function(int index) placeholder) _renderSql;
  final List<Object?> parameters;
  final List<VoxelColumn<dynamic>> columns;

  String get sql => _render((_) => '@value');

  String renderParameters({int startAt = 1}) => _render(
    (index) => '\$${startAt + index}',
  );

  String renderLiterals() => _render(
    (index) => _tursoLiteral(parameters[index]),
  );

  VoxelPredicate operator &(VoxelPredicate other) => VoxelPredicate._(
    (placeholder) =>
        '(${_renderSql(placeholder)}) AND '
        '(${other._renderSql((index) => placeholder(parameters.length + index))})',
    [...parameters, ...other.parameters],
    [...columns, ...other.columns],
  );

  VoxelPredicate operator |(VoxelPredicate other) => VoxelPredicate._(
    (placeholder) =>
        '(${_renderSql(placeholder)}) OR '
        '(${other._renderSql((index) => placeholder(parameters.length + index))})',
    [...parameters, ...other.parameters],
    [...columns, ...other.columns],
  );

  VoxelPredicate operator ~() => VoxelPredicate._(
    (placeholder) => 'NOT (${_renderSql(placeholder)})',
    parameters,
    columns,
  );

  String _render(String Function(int index) placeholder) => _renderSql(placeholder);
}

String _tursoLiteral(Object? value) => switch (value) {
  null => 'NULL',
  final bool boolean => boolean ? 'TRUE' : 'FALSE',
  final BigInt integer => integer.toString(),
  final double number when !number.isFinite => _quotedLiteral(number.toString()),
  final num number => number.toString(),
  final DateTime timestamp => _quotedLiteral(timestamp.toIso8601String()),
  final String string => _quotedLiteral(string),
  _ => throw VoxelUnsupportedQueryException(
    'Cannot render ${value.runtimeType} as a Turso literal.',
  ),
};

String _quotedLiteral(String value) => "'${value.replaceAll("'", "''")}'";

String quoteIdentifier(String identifier) {
  if (identifier.isEmpty || identifier.contains('\u0000')) {
    throw ArgumentError.value(identifier, 'identifier', 'must be non-empty and contain no NUL');
  }
  return '"${identifier.replaceAll('"', '""')}"';
}

// The fields below mirror the documented migration descriptor keys.
// ignore_for_file: public_member_api_docs, use_null_aware_elements

import 'package:voxel/src/schema.dart';

/// Serializes composed Voxel metadata for offline migration tooling.
Map<String, Object?> voxelMigrationSchemaToJson(VoxelDatabaseSchema schema) =>
    schema.toMigrationJson();

/// Connection-free physical schema metadata consumed by Voxel's migration
/// generator.
extension VoxelMigrationSchemaSerialization on VoxelDatabaseSchema {
  Map<String, Object?> toMigrationJson() {
    final tablesByType = <Type, VoxelTableSchema<Object?, Object?>>{};
    for (final table in tables) {
      final type = table.definition.runtimeType;
      if (tablesByType[type] != null) {
        throw ArgumentError('Voxel table type $type is registered more than once.');
      }
      tablesByType[type] = table;
    }

    final enumCodecs = <String, VoxelEnumCodec<Enum>>{};
    final encodedTables = <Map<String, Object?>>[];
    for (final table in tables) {
      final encodedColumns = <Map<String, Object?>>[];
      final encodedForeignKeys = <Map<String, Object?>>[];
      for (final column in table.columns) {
        final storage = _storage(column.codec);
        final enumCodec = _enumCodec(storage);
        if (enumCodec != null) {
          final key = '${enumCodec.schemaName}.${enumCodec.typeName}';
          final existing = enumCodecs[key];
          if (existing != null &&
              (existing.labels.length != enumCodec.labels.length ||
                  !existing.labels.indexed.every(
                    (entry) => entry.$2 == enumCodec.labels[entry.$1],
                  ))) {
            throw ArgumentError('Conflicting Voxel enum declarations for $key.');
          }
          enumCodecs[key] = enumCodec;
        }

        final foreignKey = column.foreignKey;
        Map<String, Object?>? encodedForeignKey;
        if (foreignKey != null) {
          final target = tablesByType[foreignKey.targetTable];
          if (target == null) {
            throw ArgumentError(
              'Foreign key ${table.schemaName}.${table.tableName}.${column.physicalName} '
              'references unregistered table ${foreignKey.targetTable}.',
            );
          }
          final referenced = foreignKey.reference(target.definition!);
          if (!target.columns.contains(referenced)) {
            throw ArgumentError('A Voxel foreign key references an unregistered column.');
          }
          encodedForeignKey = {
            'name': '${table.tableName}_${column.physicalName}_fkey',
            'kind': 'foreignKey',
            'columns': [column.physicalName],
            'references': {
              'schema': target.schemaName,
              'table': target.tableName,
              'columns': [referenced.physicalName],
            },
            'onDelete': foreignKey.onDelete.name,
            'onUpdate': foreignKey.onUpdate.name,
          };
        }

        encodedColumns.add({
          'name': column.physicalName,
          if (column.renamedFrom case final renamedFrom?) 'renamedFrom': renamedFrom,
          'storage': storage.toJson(),
          'primaryKey': column.isPrimaryKey,
          if (column.sqlDefault case final sqlDefault?)
            'default': {'formatVersion': 1, 'kind': 'sql', 'sql': sqlDefault},
        });
        if (encodedForeignKey != null) encodedForeignKeys.add(encodedForeignKey);
      }

      encodedTables.add({
        'schema': table.schemaName,
        'name': table.tableName,
        if (table.renamedFrom case final renamedFrom?) 'renamedFrom': renamedFrom,
        'columns': encodedColumns,
        'indexes': [
          for (final index in table.indexes)
            {
              'name': index.name,
              'unique': index.unique,
              'terms': [
                for (final term in index.terms)
                  {'column': term.column.physicalName, 'descending': term.descending},
              ],
              if (index.predicate case final predicate?) 'predicate': predicate.schemaExpression(),
              'options': <String, Object?>{},
              'platforms': ['native', 'browser'],
            },
        ],
        'constraints': [
          for (final constraint in table.constraints) _constraintToJson(constraint, tablesByType),
          ...encodedForeignKeys,
        ],
      });
    }

    return {
      'formatVersion': 1,
      'dialect': 'voxel',
      'name': name,
      'tables': encodedTables,
      'enums': [
        for (final entry
            in enumCodecs.entries.toList()..sort((left, right) => left.key.compareTo(right.key)))
          {
            'schema': entry.value.schemaName,
            'name': entry.value.typeName,
            if (entry.value.renamedFrom case final renamedFrom?) 'renamedFrom': renamedFrom,
            'values': [
              for (final (index, label) in entry.value.labels.indexed)
                {
                  'dartName': entry.value.values[index].name,
                  'label': label,
                  if (entry.value.renamedLabels[label] case final renamedFrom?)
                    'renamedFrom': renamedFrom,
                },
            ],
          },
      ],
      'requirements': <Object?>[],
    };
  }
}

Map<String, Object?> _constraintToJson(
  VoxelConstraint constraint,
  Map<Type, VoxelTableSchema<Object?, Object?>> tablesByType,
) {
  final result = <String, Object?>{
    'name': constraint.name,
    'kind': constraint.kind.name,
    'columns': [for (final column in constraint.columns) column.physicalName],
    if (constraint.predicate case final predicate?)
      'expression': predicate.schemaExpression()
    else if (constraint.expression case final expression?)
      'expression': {
        'formatVersion': 1,
        'kind': 'sql',
        'sql': expression,
      },
  };
  if (constraint.kind != VoxelConstraintKind.foreignKey) return result;
  final target = tablesByType[constraint.targetTable];
  if (target == null || constraint.referencedColumns.length != constraint.columns.length) {
    throw ArgumentError('Voxel foreign key ${constraint.name} is not resolved.');
  }
  return {
    ...result,
    'references': {
      'schema': target.schemaName,
      'table': target.tableName,
      'columns': [
        for (final column in constraint.referencedColumns) column.physicalName,
      ],
    },
    'onDelete': constraint.onDelete.name,
    'onUpdate': constraint.onUpdate.name,
  };
}

final class _StorageDescriptor {
  const _StorageDescriptor({
    required this.kind,
    required this.nullable,
    this.element,
    this.enumCodec,
    this.dimensions,
  });

  final String kind;
  final bool nullable;
  final _StorageDescriptor? element;
  final VoxelEnumCodec<Enum>? enumCodec;
  final int? dimensions;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'nullable': nullable,
    'codecVersion': 1,
    if (element != null) 'element': element!.toJson(),
    if (enumCodec case final codec?) 'enum': {'schema': codec.schemaName, 'name': codec.typeName},
    if (dimensions != null) 'dimensions': dimensions,
  };
}

VoxelEnumCodec<Enum>? _enumCodec(_StorageDescriptor storage) =>
    storage.enumCodec ?? (storage.element == null ? null : _enumCodec(storage.element!));

_StorageDescriptor _storage(VoxelCodec<dynamic> codec, {bool nullable = false}) {
  if (codec is VoxelMappedCodec<dynamic, dynamic>) {
    return _storage(codec.storage, nullable: nullable);
  }
  if (codec is VoxelNullableCodec<dynamic>) {
    return _storage(codec.inner, nullable: true);
  }
  if (codec is VoxelArrayCodec<dynamic>) {
    return _StorageDescriptor(
      kind: 'array',
      nullable: nullable,
      element: _storage(codec.elementCodec),
    );
  }
  if (codec is VoxelEnumCodec<Enum>) {
    return _StorageDescriptor(kind: 'enum', nullable: nullable, enumCodec: codec);
  }
  if (codec is VoxelVectorCodec) {
    return _StorageDescriptor(
      kind: 'vector',
      nullable: nullable,
      dimensions: codec.dimensions,
    );
  }
  final kind = switch (codec) {
    VoxelChronoIdCodec() || VoxelTextCodec() => 'text',
    VoxelIntegerCodec() => 'integer',
    VoxelRealCodec() => 'real',
    VoxelBooleanCodec() => 'boolean',
    VoxelDateTimeCodec() => 'dateTime',
    VoxelJsonCodec() => 'json',
    _ => throw UnsupportedError(
      'Voxel migrations do not support codec ${codec.runtimeType}.',
    ),
  };
  return _StorageDescriptor(kind: kind, nullable: nullable);
}

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'authors.dart';

// **************************************************************************
// VoxelTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'content.authors'.
final class AuthorsRow {
  /// Creates a row from decoded column and relation values.
  const AuthorsRow({required this.id, required this.name});

  /// Value read from `id`.
  final String id;

  /// Value read from `name`.
  final String name;
}

/// Generated values accepted by mutations of 'content.authors'.
final class AuthorsCompanion implements VoxelCompanion<Authors> {
  const AuthorsCompanion._({required this.id, required this.name});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory AuthorsCompanion.insert({
    required VoxelValue<Authors, String, String> id,
    required VoxelValue<Authors, String, String> name,
  }) => AuthorsCompanion._(id: id, name: name);

  /// Creates values for an update, leaving untouched columns absent.
  factory AuthorsCompanion.update({
    VoxelValue<Authors, String, String> id = const VoxelValue.absent(),
    VoxelValue<Authors, String, String> name = const VoxelValue.absent(),
  }) => AuthorsCompanion._(id: id, name: name);

  /// Mutation value for `id`.
  final VoxelValue<Authors, String, String> id;

  /// Mutation value for `name`.
  final VoxelValue<Authors, String, String> name;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<Authors>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
    VoxelAssignment('name', name),
  ];
}

final class _$AuthorsDB extends VoxelTableAccessor<Authors, AuthorsRow> {
  const _$AuthorsDB();

  @override
  VoxelTableSchema<Authors, AuthorsRow> buildSchema() {
    Authors createDefinition() {
      final definition = Authors();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<Authors, AuthorsRow>(
      schemaName: 'content',
      tableName: 'authors',
      definition: definition,
      definitionType: Authors,
      rowType: AuthorsRow,
      columns: [
        definition.id as VoxelColumn<Object?>,
        definition.name as VoxelColumn<Object?>,
      ],
      columnNames: ['id', 'name'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as VoxelColumn<Object?>,
        definition.name as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => AuthorsRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        name: definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      ),
      indexes: () => definition._indexes,
      constraints: () => definition._constraints,
    );
  }
}

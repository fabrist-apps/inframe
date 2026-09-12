// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'generated_consumer.dart';

// **************************************************************************
// VoxelTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'main.users'.
final class User {
  /// Creates a row from decoded column and relation values.
  const User({
    required this.id,
    required this.displayName,
    required this.nickname,
  });

  /// Value read from `id`.
  final String id;

  /// Value read from `displayName`.
  final String displayName;

  /// Value read from `nickname`.
  final String? nickname;
}

/// Generated values accepted by mutations of 'main.users'.
final class UsersCompanion implements VoxelCompanion<Users> {
  const UsersCompanion._({
    required this.id,
    required this.displayName,
    required this.nickname,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory UsersCompanion.insert({
    required VoxelValue<Users, String, String> displayName,
    VoxelValue<Users, String, String> id = const VoxelValue.absent(),
    VoxelValue<Users, String?, String?> nickname = const VoxelValue.absent(),
  }) => UsersCompanion._(id: id, displayName: displayName, nickname: nickname);

  /// Creates values for an update, leaving untouched columns absent.
  factory UsersCompanion.update({
    VoxelValue<Users, String, String> id = const VoxelValue.absent(),
    VoxelValue<Users, String, String> displayName = const VoxelValue.absent(),
    VoxelValue<Users, String?, String?> nickname = const VoxelValue.absent(),
  }) => UsersCompanion._(id: id, displayName: displayName, nickname: nickname);

  /// Mutation value for `id`.
  final VoxelValue<Users, String, String> id;

  /// Mutation value for `displayName`.
  final VoxelValue<Users, String, String> displayName;

  /// Mutation value for `nickname`.
  final VoxelValue<Users, String?, String?> nickname;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<Users>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
    VoxelAssignment('displayName', displayName),
    VoxelAssignment('nickname', nickname),
  ];
}

final class _$UsersDB extends VoxelTableAccessor<Users, User> {
  const _$UsersDB();

  @override
  VoxelTableSchema<Users, User> buildSchema() {
    Users createDefinition() {
      final definition = Users();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<Users, User>(
      schemaName: 'main',
      tableName: 'users',
      renamedFrom: 'people',
      definition: definition,
      definitionType: Users,
      rowType: User,
      columns: [
        definition.id as VoxelColumn<Object?>,
        definition.displayName as VoxelColumn<Object?>,
        definition.nickname as VoxelColumn<Object?>,
      ],
      columnNames: ['id', 'displayName', 'nickname'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as VoxelColumn<Object?>,
        definition.displayName as VoxelColumn<Object?>,
        definition.nickname as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => User(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        displayName: definition.displayName.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        nickname: definition.nickname.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
      ),
    );
  }
}

/// Generated row returned by reads from 'other.externalTargets'.
final class ExternalTargetsRow {
  /// Creates a row from decoded column and relation values.
  const ExternalTargetsRow({required this.id});

  /// Value read from `id`.
  final String id;
}

/// Generated values accepted by mutations of 'other.externalTargets'.
final class ExternalTargetsCompanion
    implements VoxelCompanion<ExternalTargets> {
  const ExternalTargetsCompanion._({required this.id});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ExternalTargetsCompanion.insert({
    required VoxelValue<ExternalTargets, String, String> id,
  }) => ExternalTargetsCompanion._(id: id);

  /// Creates values for an update, leaving untouched columns absent.
  factory ExternalTargetsCompanion.update({
    VoxelValue<ExternalTargets, String, String> id = const VoxelValue.absent(),
  }) => ExternalTargetsCompanion._(id: id);

  /// Mutation value for `id`.
  final VoxelValue<ExternalTargets, String, String> id;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<ExternalTargets>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
  ];
}

final class _$ExternalTargetsDB
    extends VoxelTableAccessor<ExternalTargets, ExternalTargetsRow> {
  const _$ExternalTargetsDB();

  @override
  VoxelTableSchema<ExternalTargets, ExternalTargetsRow> buildSchema() {
    ExternalTargets createDefinition() {
      final definition = ExternalTargets();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<ExternalTargets, ExternalTargetsRow>(
      schemaName: 'other',
      tableName: 'externalTargets',
      definition: definition,
      definitionType: ExternalTargets,
      rowType: ExternalTargetsRow,
      columns: [definition.id as VoxelColumn<Object?>],
      columnNames: ['id'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.id as VoxelColumn<Object?>],
      decode: (values, sqlNulls) => ExternalTargetsRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }
}

/// Generated row returned by reads from 'main.crossSchemaSources'.
final class CrossSchemaSourcesRow {
  /// Creates a row from decoded column and relation values.
  const CrossSchemaSourcesRow({required this.targetID});

  /// Value read from `targetID`.
  final String targetID;
}

/// Generated values accepted by mutations of 'main.crossSchemaSources'.
final class CrossSchemaSourcesCompanion
    implements VoxelCompanion<CrossSchemaSources> {
  const CrossSchemaSourcesCompanion._({required this.targetID});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory CrossSchemaSourcesCompanion.insert({
    required VoxelValue<CrossSchemaSources, String, String> targetID,
  }) => CrossSchemaSourcesCompanion._(targetID: targetID);

  /// Creates values for an update, leaving untouched columns absent.
  factory CrossSchemaSourcesCompanion.update({
    VoxelValue<CrossSchemaSources, String, String> targetID =
        const VoxelValue.absent(),
  }) => CrossSchemaSourcesCompanion._(targetID: targetID);

  /// Mutation value for `targetID`.
  final VoxelValue<CrossSchemaSources, String, String> targetID;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<CrossSchemaSources>> operator [](
    VoxelCompanionKey key,
  ) => [VoxelAssignment('targetID', targetID)];
}

final class _$CrossSchemaSourcesDB
    extends VoxelTableAccessor<CrossSchemaSources, CrossSchemaSourcesRow> {
  const _$CrossSchemaSourcesDB();

  @override
  VoxelTableSchema<CrossSchemaSources, CrossSchemaSourcesRow> buildSchema() {
    CrossSchemaSources createDefinition() {
      final definition = CrossSchemaSources();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<CrossSchemaSources, CrossSchemaSourcesRow>(
      schemaName: 'main',
      tableName: 'crossSchemaSources',
      definition: definition,
      definitionType: CrossSchemaSources,
      rowType: CrossSchemaSourcesRow,
      columns: [definition.targetID as VoxelColumn<Object?>],
      columnNames: ['targetID'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.targetID as VoxelColumn<Object?>],
      decode: (values, sqlNulls) => CrossSchemaSourcesRow(
        targetID: definition.targetID.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
      ),
    );
  }
}

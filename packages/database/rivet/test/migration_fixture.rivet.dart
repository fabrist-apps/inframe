// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'migration_fixture.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'auth.users'.
final class MigrationUsersRow {
  /// Creates a row from decoded column and relation values.
  const MigrationUsersRow({required this.id, required this.name});

  /// Value read from `id`.
  final int id;

  /// Value read from `name`.
  final String name;
}

/// Generated values accepted by mutations of 'auth.users'.
final class MigrationUsersCompanion implements RivetCompanion<MigrationUsers> {
  const MigrationUsersCompanion._({required this.id, required this.name});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MigrationUsersCompanion.insert({
    required RivetValue<MigrationUsers, int, int> id,
    required RivetValue<MigrationUsers, String, String> name,
  }) => MigrationUsersCompanion._(id: id, name: name);

  /// Creates values for an update, leaving untouched columns absent.
  factory MigrationUsersCompanion.update({
    RivetValue<MigrationUsers, int, int> id = const RivetValue.absent(),
    RivetValue<MigrationUsers, String, String> name = const RivetValue.absent(),
  }) => MigrationUsersCompanion._(id: id, name: name);

  /// Mutation value for `id`.
  final RivetValue<MigrationUsers, int, int> id;

  /// Mutation value for `name`.
  final RivetValue<MigrationUsers, String, String> name;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MigrationUsers>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('name', name),
  ];
}

final class _$MigrationUsersDB
    extends RivetTableAccessor<MigrationUsers, MigrationUsersRow> {
  const _$MigrationUsersDB();

  @override
  RivetTableSchema<MigrationUsers, MigrationUsersRow> buildSchema() {
    MigrationUsers createDefinition() {
      final definition = MigrationUsers();

      return definition;
    }

    final definition = createDefinition();
    MigrationUsersRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MigrationUsersRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
    );

    return RivetTableSchema<MigrationUsers, MigrationUsersRow>(
      schemaName: 'auth',
      tableName: 'users',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'name'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MigrationUsers, MigrationUsersRow> insert(
    MigrationUsersCompanion companion, {
    RivetOnConflict<MigrationUsers>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MigrationUsers, MigrationUsersRow> insertMany(
    Iterable<MigrationUsersCompanion> companions, {
    RivetOnConflict<MigrationUsers>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MigrationUsers, MigrationUsersRow> update(
    MigrationUsersCompanion companion, {
    RivetWhere<MigrationUsers>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MigrationUsers, MigrationUsersRow> delete({
    RivetWhere<MigrationUsers>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Generated row returned by reads from 'auth.members'.
final class MigratedUsersRow {
  /// Creates a row from decoded column and relation values.
  const MigratedUsersRow({
    required this.id,
    required this.fullName,
    required this.active,
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `fullName`.
  final String fullName;

  /// Value read from `active`.
  final bool active;
}

/// Generated values accepted by mutations of 'auth.members'.
final class MigratedUsersCompanion implements RivetCompanion<MigratedUsers> {
  const MigratedUsersCompanion._({
    required this.id,
    required this.fullName,
    required this.active,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MigratedUsersCompanion.insert({
    required RivetValue<MigratedUsers, int, int> id,
    required RivetValue<MigratedUsers, String, String> fullName,
    RivetValue<MigratedUsers, bool, bool> active = const RivetValue.absent(),
  }) => MigratedUsersCompanion._(id: id, fullName: fullName, active: active);

  /// Creates values for an update, leaving untouched columns absent.
  factory MigratedUsersCompanion.update({
    RivetValue<MigratedUsers, int, int> id = const RivetValue.absent(),
    RivetValue<MigratedUsers, String, String> fullName =
        const RivetValue.absent(),
    RivetValue<MigratedUsers, bool, bool> active = const RivetValue.absent(),
  }) => MigratedUsersCompanion._(id: id, fullName: fullName, active: active);

  /// Mutation value for `id`.
  final RivetValue<MigratedUsers, int, int> id;

  /// Mutation value for `fullName`.
  final RivetValue<MigratedUsers, String, String> fullName;

  /// Mutation value for `active`.
  final RivetValue<MigratedUsers, bool, bool> active;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MigratedUsers>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('fullName', fullName),
    RivetAssignment('active', active),
  ];
}

final class _$MigratedUsersDB
    extends RivetTableAccessor<MigratedUsers, MigratedUsersRow> {
  const _$MigratedUsersDB();

  @override
  RivetTableSchema<MigratedUsers, MigratedUsersRow> buildSchema() {
    MigratedUsers createDefinition() {
      final definition = MigratedUsers();

      return definition;
    }

    final definition = createDefinition();
    MigratedUsersRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MigratedUsersRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      fullName: transport
          ? definition.fullName.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.fullName.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      active: transport
          ? definition.active.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.active.decodeValue(values[2], isSqlNull: sqlNulls[2]),
    );

    return RivetTableSchema<MigratedUsers, MigratedUsersRow>(
      schemaName: 'auth',
      tableName: 'members',
      renamedFrom: 'users',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.fullName as RivetColumn<Object?>,
        definition.active as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'fullName', 'active'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.fullName as RivetColumn<Object?>,
        definition.active as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MigratedUsers, MigratedUsersRow> insert(
    MigratedUsersCompanion companion, {
    RivetOnConflict<MigratedUsers>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MigratedUsers, MigratedUsersRow> insertMany(
    Iterable<MigratedUsersCompanion> companions, {
    RivetOnConflict<MigratedUsers>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MigratedUsers, MigratedUsersRow> update(
    MigratedUsersCompanion companion, {
    RivetWhere<MigratedUsers>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MigratedUsers, MigratedUsersRow> delete({
    RivetWhere<MigratedUsers>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

// **************************************************************************
// RivetDatabaseGenerator
// **************************************************************************

/// Connection-free physical schema metadata for [MigrationFixtureDatabase].
abstract final class MigrationFixtureDatabaseRivetSchema {
  /// Builds the composed schema used by offline migration tooling.
  static RivetDatabaseSchema build() => RivetDatabaseSchema(
    name: 'migration_fixture',
    tables: [
      MigrationUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

abstract class _$MigrationFixtureDatabase {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) {
    final schema = MigrationFixtureDatabaseRivetSchema.build();
    return RivetDb.open(
      name: schema.name,
      connection: connection,
      pool: pool,
      tables: schema.tables,
    );
  }
}

/// Connection-free physical schema metadata for [MigratedFixtureDatabase].
abstract final class MigratedFixtureDatabaseRivetSchema {
  /// Builds the composed schema used by offline migration tooling.
  static RivetDatabaseSchema build() => RivetDatabaseSchema(
    name: 'migration_fixture',
    tables: [
      MigratedUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

abstract class _$MigratedFixtureDatabase {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) {
    final schema = MigratedFixtureDatabaseRivetSchema.build();
    return RivetDb.open(
      name: schema.name,
      connection: connection,
      pool: pool,
      tables: schema.tables,
    );
  }
}

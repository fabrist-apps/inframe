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

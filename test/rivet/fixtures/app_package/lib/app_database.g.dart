// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from `fixture.appUsers`.
final class AppUsersRow {
  /// Creates a row from decoded column and relation values.
  const AppUsersRow({required this.access});

  /// Value read from `access`.
  final AccessLevel access;
}

final class _$AppUsersDB extends RivetTableAccessor<AppUsers, AppUsersRow> {
  const _$AppUsersDB();

  @override
  RivetTableSchema<AppUsers, AppUsersRow> buildSchema() {
    final definition = AppUsers();
    definition.access.useCodec(AccessLevelRivetEnum.codec);
    return RivetTableSchema<AppUsers, AppUsersRow>(
      schemaName: 'fixture',
      tableName: 'appUsers',
      definition: definition,
      columns: [definition.access as RivetColumn<Object?>],
      columnNames: ['access'],
      decode: (values, sqlNulls) => AppUsersRow(
        access: definition.access.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
      ),
    );
  }
}

// **************************************************************************
// RivetDatabaseGenerator
// **************************************************************************

abstract class _$FixtureAppDatabase {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) => RivetDb.open(
    connection: connection,
    pool: pool,
    tables: [
      PackageUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      AppUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

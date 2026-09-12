// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'app_database.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'fixture.appUsers'.
final class AppUsersRow {
  /// Creates a row from decoded column and relation values.
  const AppUsersRow({
    required this.packageName,
    required this.access,
    this.package = const Relation.unloaded(),
  });

  /// Value read from `packageName`.
  final String packageName;

  /// Value read from `access`.
  final schema.AccessLevel access;

  /// Loaded or unloaded `package` relation.
  final Relation<schema.PackageUsersRow?> package;
}

final class _$AppUsersDB extends RivetTableAccessor<AppUsers, AppUsersRow> {
  const _$AppUsersDB();

  @override
  RivetTableSchema<AppUsers, AppUsersRow> buildSchema() {
    final definition = AppUsers();
    definition.access.configureEnum(schema.AccessLevelRivetEnum.codec);
    return RivetTableSchema<AppUsers, AppUsersRow>(
      schemaName: 'fixture',
      tableName: 'appUsers',
      definition: definition,
      columns: [
        definition.packageName as RivetColumn<Object?>,
        definition.access as RivetColumn<Object?>,
      ],
      columnNames: ['packageName', 'access'],
      decode: (values, sqlNulls) => AppUsersRow(
        packageName: definition.packageName.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
        access: definition.access.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
      ),
      relations: {
        'package': definition.package as RivetRelationDescriptor<Object?>,
      },
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
    name: 'fixture_app',
    connection: connection,
    pool: pool,
    tables: [
      schema.PackageUsers.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      AppUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

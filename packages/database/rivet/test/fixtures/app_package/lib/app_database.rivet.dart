// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'app_database.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'fixture.appUsers'.
final class PackageUsersRow {
  /// Creates a row from decoded column and relation values.
  const PackageUsersRow({
    required this.packageName,
    required this.access,
    required this.accessRecord,
    required this.accessCallback,
    required this.packageAccess,
    this.package = const Relation.unloaded(),
  });

  /// Value read from `packageName`.
  final String packageName;

  /// Value read from `access`.
  final schema.AccessLevel access;

  /// Value read from `accessRecord`.
  final (schema.AccessLevel, {schema.PackageUsers user}) accessRecord;

  /// Value read from `accessCallback`.
  final schema.AccessLevel Function(schema.PackageUsers) accessCallback;

  /// Value read from `packageAccess`.
  final (schema.AccessLevel, schema.PackageUsers) packageAccess;

  /// Loaded or unloaded `package` relation.
  final Relation<schema.PackageUsersRow?> package;
}

final class _$PackageUsersDB
    extends RivetTableAccessor<PackageUsers, PackageUsersRow> {
  const _$PackageUsersDB();

  @override
  RivetTableSchema<PackageUsers, PackageUsersRow> buildSchema() {
    final definition = PackageUsers();
    definition.access.configureEnum(schema.AccessLevelRivetEnum.codec);
    return RivetTableSchema<PackageUsers, PackageUsersRow>(
      schemaName: 'fixture',
      tableName: 'appUsers',
      definition: definition,
      columns: [
        definition.packageName as RivetColumn<Object?>,
        definition.access as RivetColumn<Object?>,
        definition.accessRecord as RivetColumn<Object?>,
        definition.accessCallback as RivetColumn<Object?>,
        definition.packageAccess as RivetColumn<Object?>,
      ],
      columnNames: [
        'packageName',
        'access',
        'accessRecord',
        'accessCallback',
        'packageAccess',
      ],
      decode: (values, sqlNulls) => PackageUsersRow(
        packageName: definition.packageName.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
        access: definition.access.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        accessRecord: definition.accessRecord.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
        accessCallback: definition.accessCallback.decodeValue(
          values[3],
          isSqlNull: sqlNulls[3],
        ),
        packageAccess: definition.packageAccess.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
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
      PackageUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

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

/// Generated values accepted by mutations of 'fixture.appUsers'.
final class PackageUsersCompanion implements RivetCompanion<PackageUsers> {
  const PackageUsersCompanion._({
    required this.packageName,
    required this.access,
    required this.accessRecord,
    required this.accessCallback,
    required this.packageAccess,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory PackageUsersCompanion.insert({
    required RivetValue<PackageUsers, String, String> packageName,
    required RivetValue<PackageUsers, schema.AccessLevel, schema.AccessLevel>
    access,
    required RivetValue<
      PackageUsers,
      (schema.AccessLevel, {schema.PackageUsers user}),
      String
    >
    accessRecord,
    required RivetValue<
      PackageUsers,
      schema.AccessLevel Function(schema.PackageUsers),
      String
    >
    accessCallback,
    required RivetValue<
      PackageUsers,
      (schema.AccessLevel, schema.PackageUsers),
      String
    >
    packageAccess,
  }) => PackageUsersCompanion._(
    packageName: packageName,
    access: access,
    accessRecord: accessRecord,
    accessCallback: accessCallback,
    packageAccess: packageAccess,
  );

  /// Mutation value for `packageName`.
  final RivetValue<PackageUsers, String, String> packageName;

  /// Mutation value for `access`.
  final RivetValue<PackageUsers, schema.AccessLevel, schema.AccessLevel> access;

  /// Mutation value for `accessRecord`.
  final RivetValue<
    PackageUsers,
    (schema.AccessLevel, {schema.PackageUsers user}),
    String
  >
  accessRecord;

  /// Mutation value for `accessCallback`.
  final RivetValue<
    PackageUsers,
    schema.AccessLevel Function(schema.PackageUsers),
    String
  >
  accessCallback;

  /// Mutation value for `packageAccess`.
  final RivetValue<
    PackageUsers,
    (schema.AccessLevel, schema.PackageUsers),
    String
  >
  packageAccess;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<PackageUsers>> get assignments => [
    RivetAssignment('packageName', packageName),
    RivetAssignment('access', access),
    RivetAssignment('accessRecord', accessRecord),
    RivetAssignment('accessCallback', accessCallback),
    RivetAssignment('packageAccess', packageAccess),
  ];
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

  /// Creates a reusable insert plan.
  RivetInsert<PackageUsers, PackageUsersRow> insert(
    PackageUsersCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
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

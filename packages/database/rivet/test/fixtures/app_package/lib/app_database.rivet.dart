// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'app_database.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Typed relation include scope for [PackageUsers].
final class PackageUsersInclude {
  /// Creates the generated include scope.
  const PackageUsersInclude(this._schema, {this.path = ''});

  final RivetTableSchema<PackageUsers, PackageUsersRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [package] relation.
  RivetInclude<schema.PackageUsers, schema.PackageUsersRow> package({
    RivetWhere<schema.PackageUsers>? where,
  }) {
    final target = schema.PackageUsers.db.buildSchema();
    final relationPath = path.isEmpty ? 'package' : '$path.package';
    return RivetInclude<schema.PackageUsers, schema.PackageUsersRow>(
      name: 'package',
      path: relationPath,
      relation: _schema.relations['package']!,
      targetSchema: target,
      where: where,
    );
  }

  /// Includes the [projects] relation.
  RivetInclude<AppProjects, AppProjectsRow> projects({
    RivetWhere<AppProjects>? where,
    RivetOrderBy<AppProjects>? orderBy,
    int? limit,

    RivetIncludes<AppProjectsInclude>? include,
  }) {
    final target = AppProjects.db.buildSchema();
    final relationPath = path.isEmpty ? 'projects' : '$path.projects';
    return RivetInclude<AppProjects, AppProjectsRow>(
      name: 'projects',
      path: relationPath,
      relation: _schema.relations['projects']!,
      targetSchema: target,
      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(AppProjectsInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

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
    this.projects = const Relation.unloaded(),
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

  /// Loaded or unloaded `projects` relation.
  final Relation<List<AppProjectsRow>> projects;
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

  /// Creates values for an update, leaving untouched columns absent.
  factory PackageUsersCompanion.update({
    RivetValue<PackageUsers, String, String> packageName =
        const RivetValue.absent(),
    RivetValue<PackageUsers, schema.AccessLevel, schema.AccessLevel> access =
        const RivetValue.absent(),
    RivetValue<
          PackageUsers,
          (schema.AccessLevel, {schema.PackageUsers user}),
          String
        >
        accessRecord =
        const RivetValue.absent(),
    RivetValue<
          PackageUsers,
          schema.AccessLevel Function(schema.PackageUsers),
          String
        >
        accessCallback =
        const RivetValue.absent(),
    RivetValue<PackageUsers, (schema.AccessLevel, schema.PackageUsers), String>
        packageAccess =
        const RivetValue.absent(),
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
  List<RivetAssignment<PackageUsers>> operator [](RivetCompanionKey key) => [
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
    PackageUsers createDefinition() {
      final definition = PackageUsers();
      definition.access.configureEnum(schema.AccessLevelRivetEnum.codec);
      return definition;
    }

    final definition = createDefinition();
    PackageUsersRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => PackageUsersRow(
      packageName: transport
          ? definition.packageName.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.packageName.decodeValue(
              values[0],
              isSqlNull: sqlNulls[0],
            ),
      access: transport
          ? definition.access.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.access.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      accessRecord: transport
          ? definition.accessRecord.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.accessRecord.decodeValue(
              values[2],
              isSqlNull: sqlNulls[2],
            ),
      accessCallback: transport
          ? definition.accessCallback.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.accessCallback.decodeValue(
              values[3],
              isSqlNull: sqlNulls[3],
            ),
      packageAccess: transport
          ? definition.packageAccess.decodeTransportValue(
              values[4],
              isSqlNull: sqlNulls[4],
            )
          : definition.packageAccess.decodeValue(
              values[4],
              isSqlNull: sqlNulls[4],
            ),
      package: relations.read('package'),
      projects: relations.read('projects'),
    );

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
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.packageName as RivetColumn<Object?>,
        definition.access as RivetColumn<Object?>,
        definition.accessRecord as RivetColumn<Object?>,
        definition.accessCallback as RivetColumn<Object?>,
        definition.packageAccess as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'package': definition.package as RivetRelationDescriptor<Object?>,
        'projects': definition.projects as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<PackageUsers, PackageUsersRow> find({
    RivetWhere<PackageUsers>? where,
    RivetOrderBy<PackageUsers>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<PackageUsersInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(PackageUsersInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<PackageUsers, PackageUsersRow> insert(
    PackageUsersCompanion companion, {
    RivetOnConflict<PackageUsers>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<PackageUsers, PackageUsersRow> insertMany(
    Iterable<PackageUsersCompanion> companions, {
    RivetOnConflict<PackageUsers>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<PackageUsers, PackageUsersRow> update(
    PackageUsersCompanion companion, {
    RivetWhere<PackageUsers>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<PackageUsers, PackageUsersRow> delete({
    RivetWhere<PackageUsers>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [AppProjects].
final class AppProjectsInclude {
  /// Creates the generated include scope.
  const AppProjectsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<AppProjects, AppProjectsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [owner] relation.
  RivetInclude<PackageUsers, PackageUsersRow> owner({
    RivetWhere<PackageUsers>? where,

    RivetIncludes<PackageUsersInclude>? include,
  }) {
    final target = PackageUsers.db.buildSchema();
    final relationPath = path.isEmpty ? 'owner' : '$path.owner';
    return RivetInclude<PackageUsers, PackageUsersRow>(
      name: 'owner',
      path: relationPath,
      relation: _schema.relations['owner']!,
      targetSchema: target,
      where: where,

      includes:
          include?.call(PackageUsersInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [packageOwner] relation.
  RivetInclude<schema.PackageUsers, schema.PackageUsersRow> packageOwner({
    RivetWhere<schema.PackageUsers>? where,
  }) {
    final target = schema.PackageUsers.db.buildSchema();
    final relationPath = path.isEmpty ? 'packageOwner' : '$path.packageOwner';
    return RivetInclude<schema.PackageUsers, schema.PackageUsersRow>(
      name: 'packageOwner',
      path: relationPath,
      relation: _schema.relations['packageOwner']!,
      targetSchema: target,
      where: where,
    );
  }
}

/// Generated row returned by reads from 'fixture.appProjects'.
final class AppProjectsRow {
  /// Creates a row from decoded column and relation values.
  const AppProjectsRow({
    required this.id,
    required this.ownerName,
    required this.packageOwnerName,
    this.owner = const Relation.unloaded(),
    this.packageOwner = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `ownerName`.
  final String ownerName;

  /// Value read from `packageOwnerName`.
  final String packageOwnerName;

  /// Loaded or unloaded `owner` relation.
  final Relation<PackageUsersRow?> owner;

  /// Loaded or unloaded `packageOwner` relation.
  final Relation<schema.PackageUsersRow?> packageOwner;
}

/// Generated values accepted by mutations of 'fixture.appProjects'.
final class AppProjectsCompanion implements RivetCompanion<AppProjects> {
  const AppProjectsCompanion._({
    required this.id,
    required this.ownerName,
    required this.packageOwnerName,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory AppProjectsCompanion.insert({
    required RivetValue<AppProjects, int, int> id,
    required RivetValue<AppProjects, String, String> ownerName,
    required RivetValue<AppProjects, String, String> packageOwnerName,
  }) => AppProjectsCompanion._(
    id: id,
    ownerName: ownerName,
    packageOwnerName: packageOwnerName,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory AppProjectsCompanion.update({
    RivetValue<AppProjects, int, int> id = const RivetValue.absent(),
    RivetValue<AppProjects, String, String> ownerName =
        const RivetValue.absent(),
    RivetValue<AppProjects, String, String> packageOwnerName =
        const RivetValue.absent(),
  }) => AppProjectsCompanion._(
    id: id,
    ownerName: ownerName,
    packageOwnerName: packageOwnerName,
  );

  /// Mutation value for `id`.
  final RivetValue<AppProjects, int, int> id;

  /// Mutation value for `ownerName`.
  final RivetValue<AppProjects, String, String> ownerName;

  /// Mutation value for `packageOwnerName`.
  final RivetValue<AppProjects, String, String> packageOwnerName;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<AppProjects>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('ownerName', ownerName),
    RivetAssignment('packageOwnerName', packageOwnerName),
  ];
}

final class _$AppProjectsDB
    extends RivetTableAccessor<AppProjects, AppProjectsRow> {
  const _$AppProjectsDB();

  @override
  RivetTableSchema<AppProjects, AppProjectsRow> buildSchema() {
    AppProjects createDefinition() {
      final definition = AppProjects();

      return definition;
    }

    final definition = createDefinition();
    AppProjectsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => AppProjectsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ownerName: transport
          ? definition.ownerName.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.ownerName.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      packageOwnerName: transport
          ? definition.packageOwnerName.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.packageOwnerName.decodeValue(
              values[2],
              isSqlNull: sqlNulls[2],
            ),
      owner: relations.read('owner'),
      packageOwner: relations.read('packageOwner'),
    );

    return RivetTableSchema<AppProjects, AppProjectsRow>(
      schemaName: 'fixture',
      tableName: 'appProjects',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.ownerName as RivetColumn<Object?>,
        definition.packageOwnerName as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'ownerName', 'packageOwnerName'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.ownerName as RivetColumn<Object?>,
        definition.packageOwnerName as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'owner': definition.owner as RivetRelationDescriptor<Object?>,
        'packageOwner':
            definition.packageOwner as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<AppProjects, AppProjectsRow> find({
    RivetWhere<AppProjects>? where,
    RivetOrderBy<AppProjects>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<AppProjectsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(AppProjectsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<AppProjects, AppProjectsRow> insert(
    AppProjectsCompanion companion, {
    RivetOnConflict<AppProjects>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<AppProjects, AppProjectsRow> insertMany(
    Iterable<AppProjectsCompanion> companions, {
    RivetOnConflict<AppProjects>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<AppProjects, AppProjectsRow> update(
    AppProjectsCompanion companion, {
    RivetWhere<AppProjects>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<AppProjects, AppProjectsRow> delete({
    RivetWhere<AppProjects>? where,
  }) => RivetDelete(buildSchema(), where: where);
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
      AppProjects.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

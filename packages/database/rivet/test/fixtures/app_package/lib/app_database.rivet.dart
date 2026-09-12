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

    final builtSchema = RivetTableSchema<PackageUsers, PackageUsersRow>(
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
    definition.package.bind(
      name: 'package',
      ownerSchema: builtSchema,
      targetSchema: () => schema.PackageUsers.db.buildSchema(),
    );
    definition.projects.bind(
      name: 'projects',
      ownerSchema: builtSchema,
      targetSchema: () => AppProjects.db.buildSchema(),
    );
    return builtSchema;
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

  /// Includes the [labels] relation.
  RivetInclude<schema.PackageLabels, schema.PackageLabelRecord> labels({
    RivetWhere<schema.PackageLabels>? where,
    RivetOrderBy<schema.PackageLabels>? orderBy,
    int? limit,

    RivetIncludes<schema.PackageLabelsInclude>? include,
  }) {
    final target = schema.PackageLabels.db.buildSchema();
    final through = AppProjectLabels.db.buildSchema();

    final relationPath = path.isEmpty ? 'labels' : '$path.labels';
    return RivetInclude<schema.PackageLabels, schema.PackageLabelRecord>(
      name: 'labels',
      path: relationPath,
      relation: _schema.relations['labels']!,
      targetSchema: target,
      throughSchema: through,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(
            schema.PackageLabelsInclude(target, path: relationPath),
          ) ??
          const [],
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
    this.labels = const Relation.unloaded(),
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

  /// Loaded or unloaded `labels` relation.
  final Relation<List<schema.PackageLabelRecord>> labels;
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
      labels: relations.read('labels'),
    );

    final builtSchema = RivetTableSchema<AppProjects, AppProjectsRow>(
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
        'labels': definition.labels as RivetRelationDescriptor<Object?>,
      },
    );
    definition.owner.bind(
      name: 'owner',
      ownerSchema: builtSchema,
      targetSchema: () => PackageUsers.db.buildSchema(),
    );
    definition.packageOwner.bind(
      name: 'packageOwner',
      ownerSchema: builtSchema,
      targetSchema: () => schema.PackageUsers.db.buildSchema(),
    );
    definition.labels.bind(
      name: 'labels',
      ownerSchema: builtSchema,
      targetSchema: () => schema.PackageLabels.db.buildSchema(),
      throughSchema: () => AppProjectLabels.db.buildSchema(),
    );
    return builtSchema;
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

/// Typed relation include scope for [AppProjectLabels].
final class AppProjectLabelsInclude {
  /// Creates the generated include scope.
  const AppProjectLabelsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<AppProjectLabels, AppProjectLabelsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [project] relation.
  RivetInclude<AppProjects, AppProjectsRow> project({
    RivetWhere<AppProjects>? where,

    RivetIncludes<AppProjectsInclude>? include,
  }) {
    final target = AppProjects.db.buildSchema();

    final relationPath = path.isEmpty ? 'project' : '$path.project';
    return RivetInclude<AppProjects, AppProjectsRow>(
      name: 'project',
      path: relationPath,
      relation: _schema.relations['project']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(AppProjectsInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [label] relation.
  RivetInclude<schema.PackageLabels, schema.PackageLabelRecord> label({
    RivetWhere<schema.PackageLabels>? where,

    RivetIncludes<schema.PackageLabelsInclude>? include,
  }) {
    final target = schema.PackageLabels.db.buildSchema();

    final relationPath = path.isEmpty ? 'label' : '$path.label';
    return RivetInclude<schema.PackageLabels, schema.PackageLabelRecord>(
      name: 'label',
      path: relationPath,
      relation: _schema.relations['label']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(
            schema.PackageLabelsInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fixture.appProjectLabels'.
final class AppProjectLabelsRow {
  /// Creates a row from decoded column and relation values.
  const AppProjectLabelsRow({
    required this.projectId,
    required this.labelCode,
    this.project = const Relation.unloaded(),
    this.label = const Relation.unloaded(),
  });

  /// Value read from `projectId`.
  final int projectId;

  /// Value read from `labelCode`.
  final String labelCode;

  /// Loaded or unloaded `project` relation.
  final Relation<AppProjectsRow?> project;

  /// Loaded or unloaded `label` relation.
  final Relation<schema.PackageLabelRecord?> label;
}

/// Generated values accepted by mutations of 'fixture.appProjectLabels'.
final class AppProjectLabelsCompanion
    implements RivetCompanion<AppProjectLabels> {
  const AppProjectLabelsCompanion._({
    required this.projectId,
    required this.labelCode,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory AppProjectLabelsCompanion.insert({
    required RivetValue<AppProjectLabels, int, int> projectId,
    required RivetValue<AppProjectLabels, String, String> labelCode,
  }) => AppProjectLabelsCompanion._(projectId: projectId, labelCode: labelCode);

  /// Creates values for an update, leaving untouched columns absent.
  factory AppProjectLabelsCompanion.update({
    RivetValue<AppProjectLabels, int, int> projectId =
        const RivetValue.absent(),
    RivetValue<AppProjectLabels, String, String> labelCode =
        const RivetValue.absent(),
  }) => AppProjectLabelsCompanion._(projectId: projectId, labelCode: labelCode);

  /// Mutation value for `projectId`.
  final RivetValue<AppProjectLabels, int, int> projectId;

  /// Mutation value for `labelCode`.
  final RivetValue<AppProjectLabels, String, String> labelCode;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<AppProjectLabels>> operator [](RivetCompanionKey key) =>
      [
        RivetAssignment('projectId', projectId),
        RivetAssignment('labelCode', labelCode),
      ];
}

final class _$AppProjectLabelsDB
    extends RivetTableAccessor<AppProjectLabels, AppProjectLabelsRow> {
  const _$AppProjectLabelsDB();

  @override
  RivetTableSchema<AppProjectLabels, AppProjectLabelsRow> buildSchema() {
    AppProjectLabels createDefinition() {
      final definition = AppProjectLabels();

      return definition;
    }

    final definition = createDefinition();
    AppProjectLabelsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => AppProjectLabelsRow(
      projectId: transport
          ? definition.projectId.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.projectId.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      labelCode: transport
          ? definition.labelCode.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.labelCode.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      project: relations.read('project'),
      label: relations.read('label'),
    );

    final builtSchema = RivetTableSchema<AppProjectLabels, AppProjectLabelsRow>(
      schemaName: 'fixture',
      tableName: 'appProjectLabels',
      definition: definition,
      columns: [
        definition.projectId as RivetColumn<Object?>,
        definition.labelCode as RivetColumn<Object?>,
      ],
      columnNames: ['projectId', 'labelCode'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.projectId as RivetColumn<Object?>,
        definition.labelCode as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'project': definition.project as RivetRelationDescriptor<Object?>,
        'label': definition.label as RivetRelationDescriptor<Object?>,
      },
    );
    definition.project.bind(
      name: 'project',
      ownerSchema: builtSchema,
      targetSchema: () => AppProjects.db.buildSchema(),
    );
    definition.label.bind(
      name: 'label',
      ownerSchema: builtSchema,
      targetSchema: () => schema.PackageLabels.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<AppProjectLabels, AppProjectLabelsRow> find({
    RivetWhere<AppProjectLabels>? where,
    RivetOrderBy<AppProjectLabels>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<AppProjectLabelsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(AppProjectLabelsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<AppProjectLabels, AppProjectLabelsRow> insert(
    AppProjectLabelsCompanion companion, {
    RivetOnConflict<AppProjectLabels>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<AppProjectLabels, AppProjectLabelsRow> insertMany(
    Iterable<AppProjectLabelsCompanion> companions, {
    RivetOnConflict<AppProjectLabels>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<AppProjectLabels, AppProjectLabelsRow> update(
    AppProjectLabelsCompanion companion, {
    RivetWhere<AppProjectLabels>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<AppProjectLabels, AppProjectLabelsRow> delete({
    RivetWhere<AppProjectLabels>? where,
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
      schema.PackageLabels.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      schema.PackageLabelNotes.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      PackageUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      AppProjects.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      AppProjectLabels.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

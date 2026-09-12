// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'package_users.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'fixture.packageUsers'.
final class PackageUsersRow {
  /// Creates a row from decoded column and relation values.
  const PackageUsersRow({required this.name, required this.access});

  /// Value read from `name`.
  final String name;

  /// Value read from `access`.
  final AccessLevel access;
}

/// Generated values accepted by mutations of 'fixture.packageUsers'.
final class PackageUsersCompanion implements RivetCompanion<PackageUsers> {
  const PackageUsersCompanion._({required this.name, required this.access});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory PackageUsersCompanion.insert({
    required RivetValue<PackageUsers, String, String> name,
    required RivetValue<PackageUsers, AccessLevel, AccessLevel> access,
  }) => PackageUsersCompanion._(name: name, access: access);

  /// Creates values for an update, leaving untouched columns absent.
  factory PackageUsersCompanion.update({
    RivetValue<PackageUsers, String, String> name = const RivetValue.absent(),
    RivetValue<PackageUsers, AccessLevel, AccessLevel> access =
        const RivetValue.absent(),
  }) => PackageUsersCompanion._(name: name, access: access);

  /// Mutation value for `name`.
  final RivetValue<PackageUsers, String, String> name;

  /// Mutation value for `access`.
  final RivetValue<PackageUsers, AccessLevel, AccessLevel> access;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<PackageUsers>> operator [](RivetCompanionKey key) => [
    RivetAssignment('name', name),
    RivetAssignment('access', access),
  ];
}

final class _$PackageUsersDB
    extends RivetTableAccessor<PackageUsers, PackageUsersRow> {
  const _$PackageUsersDB();

  @override
  RivetTableSchema<PackageUsers, PackageUsersRow> buildSchema() {
    PackageUsers createDefinition() {
      final definition = PackageUsers();
      definition.access.configureEnum(AccessLevelRivetEnum.codec);
      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<PackageUsers, PackageUsersRow>(
      schemaName: 'fixture',
      tableName: 'packageUsers',
      definition: definition,
      columns: [
        definition.name as RivetColumn<Object?>,
        definition.access as RivetColumn<Object?>,
      ],
      columnNames: ['name', 'access'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.name as RivetColumn<Object?>,
        definition.access as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => PackageUsersRow(
        name: definition.name.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        access: definition.access.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
      ),
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

/// Typed relation include scope for [PackageLabels].
final class PackageLabelsInclude {
  /// Creates the generated include scope.
  const PackageLabelsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<PackageLabels, PackageLabelsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [notes] relation.
  RivetInclude<PackageLabelNotes, PackageLabelNotesRow> notes({
    RivetWhere<PackageLabelNotes>? where,
    RivetOrderBy<PackageLabelNotes>? orderBy,
    int? limit,

    RivetIncludes<PackageLabelNotesInclude>? include,
  }) {
    final target = PackageLabelNotes.db.buildSchema();

    final relationPath = path.isEmpty ? 'notes' : '$path.notes';
    return RivetInclude<PackageLabelNotes, PackageLabelNotesRow>(
      name: 'notes',
      path: relationPath,
      relation: _schema.relations['notes']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(PackageLabelNotesInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fixture.packageLabels'.
final class PackageLabelsRow {
  /// Creates a row from decoded column and relation values.
  const PackageLabelsRow({
    required this.code,
    required this.name,
    this.notes = const Relation.unloaded(),
  });

  /// Value read from `code`.
  final String code;

  /// Value read from `name`.
  final String name;

  /// Loaded or unloaded `notes` relation.
  final Relation<List<PackageLabelNotesRow>> notes;
}

/// Generated values accepted by mutations of 'fixture.packageLabels'.
final class PackageLabelsCompanion implements RivetCompanion<PackageLabels> {
  const PackageLabelsCompanion._({required this.code, required this.name});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory PackageLabelsCompanion.insert({
    required RivetValue<PackageLabels, String, String> code,
    required RivetValue<PackageLabels, String, String> name,
  }) => PackageLabelsCompanion._(code: code, name: name);

  /// Creates values for an update, leaving untouched columns absent.
  factory PackageLabelsCompanion.update({
    RivetValue<PackageLabels, String, String> code = const RivetValue.absent(),
    RivetValue<PackageLabels, String, String> name = const RivetValue.absent(),
  }) => PackageLabelsCompanion._(code: code, name: name);

  /// Mutation value for `code`.
  final RivetValue<PackageLabels, String, String> code;

  /// Mutation value for `name`.
  final RivetValue<PackageLabels, String, String> name;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<PackageLabels>> operator [](RivetCompanionKey key) => [
    RivetAssignment('code', code),
    RivetAssignment('name', name),
  ];
}

final class _$PackageLabelsDB
    extends RivetTableAccessor<PackageLabels, PackageLabelsRow> {
  const _$PackageLabelsDB();

  @override
  RivetTableSchema<PackageLabels, PackageLabelsRow> buildSchema() {
    PackageLabels createDefinition() {
      final definition = PackageLabels();

      return definition;
    }

    final definition = createDefinition();
    PackageLabelsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => PackageLabelsRow(
      code: transport
          ? definition.code.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.code.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      notes: relations.read('notes'),
    );

    return RivetTableSchema<PackageLabels, PackageLabelsRow>(
      schemaName: 'fixture',
      tableName: 'packageLabels',
      definition: definition,
      columns: [
        definition.code as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      columnNames: ['code', 'name'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.code as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'notes': definition.notes as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<PackageLabels, PackageLabelsRow> find({
    RivetWhere<PackageLabels>? where,
    RivetOrderBy<PackageLabels>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<PackageLabelsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(PackageLabelsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<PackageLabels, PackageLabelsRow> insert(
    PackageLabelsCompanion companion, {
    RivetOnConflict<PackageLabels>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<PackageLabels, PackageLabelsRow> insertMany(
    Iterable<PackageLabelsCompanion> companions, {
    RivetOnConflict<PackageLabels>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<PackageLabels, PackageLabelsRow> update(
    PackageLabelsCompanion companion, {
    RivetWhere<PackageLabels>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<PackageLabels, PackageLabelsRow> delete({
    RivetWhere<PackageLabels>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [PackageLabelNotes].
final class PackageLabelNotesInclude {
  /// Creates the generated include scope.
  const PackageLabelNotesInclude(this._schema, {this.path = ''});

  final RivetTableSchema<PackageLabelNotes, PackageLabelNotesRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [label] relation.
  RivetInclude<PackageLabels, PackageLabelsRow> label({
    RivetWhere<PackageLabels>? where,

    RivetIncludes<PackageLabelsInclude>? include,
  }) {
    final target = PackageLabels.db.buildSchema();

    final relationPath = path.isEmpty ? 'label' : '$path.label';
    return RivetInclude<PackageLabels, PackageLabelsRow>(
      name: 'label',
      path: relationPath,
      relation: _schema.relations['label']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(PackageLabelsInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fixture.packageLabelNotes'.
final class PackageLabelNotesRow {
  /// Creates a row from decoded column and relation values.
  const PackageLabelNotesRow({
    required this.id,
    required this.labelCode,
    required this.body,
    this.label = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `labelCode`.
  final String labelCode;

  /// Value read from `body`.
  final String body;

  /// Loaded or unloaded `label` relation.
  final Relation<PackageLabelsRow?> label;
}

/// Generated values accepted by mutations of 'fixture.packageLabelNotes'.
final class PackageLabelNotesCompanion
    implements RivetCompanion<PackageLabelNotes> {
  const PackageLabelNotesCompanion._({
    required this.id,
    required this.labelCode,
    required this.body,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory PackageLabelNotesCompanion.insert({
    required RivetValue<PackageLabelNotes, int, int> id,
    required RivetValue<PackageLabelNotes, String, String> labelCode,
    required RivetValue<PackageLabelNotes, String, String> body,
  }) => PackageLabelNotesCompanion._(id: id, labelCode: labelCode, body: body);

  /// Creates values for an update, leaving untouched columns absent.
  factory PackageLabelNotesCompanion.update({
    RivetValue<PackageLabelNotes, int, int> id = const RivetValue.absent(),
    RivetValue<PackageLabelNotes, String, String> labelCode =
        const RivetValue.absent(),
    RivetValue<PackageLabelNotes, String, String> body =
        const RivetValue.absent(),
  }) => PackageLabelNotesCompanion._(id: id, labelCode: labelCode, body: body);

  /// Mutation value for `id`.
  final RivetValue<PackageLabelNotes, int, int> id;

  /// Mutation value for `labelCode`.
  final RivetValue<PackageLabelNotes, String, String> labelCode;

  /// Mutation value for `body`.
  final RivetValue<PackageLabelNotes, String, String> body;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<PackageLabelNotes>> operator [](RivetCompanionKey key) =>
      [
        RivetAssignment('id', id),
        RivetAssignment('labelCode', labelCode),
        RivetAssignment('body', body),
      ];
}

final class _$PackageLabelNotesDB
    extends RivetTableAccessor<PackageLabelNotes, PackageLabelNotesRow> {
  const _$PackageLabelNotesDB();

  @override
  RivetTableSchema<PackageLabelNotes, PackageLabelNotesRow> buildSchema() {
    PackageLabelNotes createDefinition() {
      final definition = PackageLabelNotes();

      return definition;
    }

    final definition = createDefinition();
    PackageLabelNotesRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => PackageLabelNotesRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      labelCode: transport
          ? definition.labelCode.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.labelCode.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      body: transport
          ? definition.body.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.body.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      label: relations.read('label'),
    );

    return RivetTableSchema<PackageLabelNotes, PackageLabelNotesRow>(
      schemaName: 'fixture',
      tableName: 'packageLabelNotes',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.labelCode as RivetColumn<Object?>,
        definition.body as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'labelCode', 'body'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.labelCode as RivetColumn<Object?>,
        definition.body as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'label': definition.label as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<PackageLabelNotes, PackageLabelNotesRow> find({
    RivetWhere<PackageLabelNotes>? where,
    RivetOrderBy<PackageLabelNotes>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<PackageLabelNotesInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(PackageLabelNotesInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<PackageLabelNotes, PackageLabelNotesRow> insert(
    PackageLabelNotesCompanion companion, {
    RivetOnConflict<PackageLabelNotes>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<PackageLabelNotes, PackageLabelNotesRow> insertMany(
    Iterable<PackageLabelNotesCompanion> companions, {
    RivetOnConflict<PackageLabelNotes>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<PackageLabelNotes, PackageLabelNotesRow> update(
    PackageLabelNotesCompanion companion, {
    RivetWhere<PackageLabelNotes>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<PackageLabelNotes, PackageLabelNotesRow> delete({
    RivetWhere<PackageLabelNotes>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

// **************************************************************************
// RivetEnumGenerator
// **************************************************************************

/// Generated PostgreSQL metadata and codec for [AccessLevel].
abstract final class AccessLevelRivetEnum {
  /// Converts [AccessLevel] values to and from their stored labels.
  static const codec = RivetEnumCodec<AccessLevel>(
    schemaName: 'fixture',
    typeName: 'accessLevel',
    renamedFrom: 'role',
    values: [AccessLevel.viewer, AccessLevel.owner],
    labels: ['viewer', 'owner-label'],
    renamedLabels: {'owner-label': 'admin-label'},
  );
}

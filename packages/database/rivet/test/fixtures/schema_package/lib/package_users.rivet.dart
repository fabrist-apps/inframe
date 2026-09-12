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
  List<RivetAssignment<PackageUsers>> get assignments => [
    RivetAssignment('name', name),
    RivetAssignment('access', access),
  ];
}

final class _$PackageUsersDB
    extends RivetTableAccessor<PackageUsers, PackageUsersRow> {
  const _$PackageUsersDB();

  @override
  RivetTableSchema<PackageUsers, PackageUsersRow> buildSchema() {
    final definition = PackageUsers();
    definition.access.configureEnum(AccessLevelRivetEnum.codec);
    return RivetTableSchema<PackageUsers, PackageUsersRow>(
      schemaName: 'fixture',
      tableName: 'packageUsers',
      definition: definition,
      columns: [
        definition.name as RivetColumn<Object?>,
        definition.access as RivetColumn<Object?>,
      ],
      columnNames: ['name', 'access'],
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
    PackageUsersCompanion companion,
  ) => RivetInsert(buildSchema(), companion);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<PackageUsers, PackageUsersRow> insertMany(
    Iterable<PackageUsersCompanion> companions,
  ) => RivetInsertMany(buildSchema(), companions);

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

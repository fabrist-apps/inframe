// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'package_users.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from `fixture.packageUsers`.
final class PackageUsersRow {
  /// Creates a row from decoded column and relation values.
  const PackageUsersRow({required this.name, required this.access});

  /// Value read from `name`.
  final String name;

  /// Value read from `access`.
  final AccessLevel access;
}

final class _$PackageUsersDB extends RivetTableAccessor<PackageUsers, PackageUsersRow> {
  const _$PackageUsersDB();

  @override
  RivetTableSchema<PackageUsers, PackageUsersRow> buildSchema() {
    final definition = PackageUsers();
    definition.access.useCodec(AccessLevelRivetEnum.codec);
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

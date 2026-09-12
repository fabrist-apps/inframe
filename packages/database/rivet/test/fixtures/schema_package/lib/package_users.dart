// The declaration DSL relies on inferred field types for generated output.
// Test fixture declarations intentionally omit public API prose.
// ignore_for_file: public_member_api_docs, specify_nonobvious_property_types

import 'package:rivet/rivet.dart';

part 'package_users.rivet.dart';

@RivetEnum(schema: 'fixture', name: 'accessLevel', renamedFrom: 'role')
enum AccessLevel {
  viewer,

  @RivetEnumValue(name: 'owner-label', renamedFrom: 'admin-label')
  owner,
}

typedef PackageAccess = (AccessLevel, PackageUsers);

final class PackageAccessConverter implements RivetTypeConverter<PackageAccess, String> {
  const PackageAccessConverter();

  @override
  PackageAccess fromSql(String value) => (AccessLevel.viewer, PackageUsers());

  @override
  String toSql(PackageAccess value) => value.$1.name;
}

@RivetTable(schema: 'fixture', name: 'packageUsers')
final class PackageUsers extends RivetTableDefinition<PackageUsers> {
  static const db = _$PackageUsersDB();

  late final name = text()();
  late final access = enumText<AccessLevel>()();
}

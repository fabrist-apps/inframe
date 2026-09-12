// The declaration DSL relies on inferred field types for generated output.
// Test fixture declarations intentionally omit public API prose.
// ignore_for_file: public_member_api_docs, specify_nonobvious_property_types

import 'package:rivet/rivet.dart';

part 'package_users.g.dart';

@RivetEnum(schema: 'fixture', name: 'accessLevel', renamedFrom: 'role')
enum AccessLevel {
  viewer,

  @RivetEnumValue(name: 'owner-label', renamedFrom: 'admin-label')
  owner,
}

@RivetTable(schema: 'fixture', name: 'packageUsers')
final class PackageUsers extends RivetTableDefinition<PackageUsers> {
  static const db = _$PackageUsersDB();

  late final name = text()();
  late final access = enumText<AccessLevel>()();
}

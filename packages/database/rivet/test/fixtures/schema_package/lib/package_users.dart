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

@RivetTable(schema: 'fixture', name: 'packageLabels')
final class PackageLabels extends RivetTableDefinition<PackageLabels> {
  static const db = _$PackageLabelsDB();

  late final code = text()();
  late final name = text()();
  late final notes = many<PackageLabelNotes>()();
}

@RivetTable(schema: 'fixture', name: 'packageLabelNotes')
final class PackageLabelNotes extends RivetTableDefinition<PackageLabelNotes> {
  static const db = _$PackageLabelNotesDB();

  late final id = integer()();
  late final labelCode = text()();
  late final body = text()();
  late final label = one<PackageLabels>(
    fields: [labelCode],
    references: (label) => [label.code],
  )();
}

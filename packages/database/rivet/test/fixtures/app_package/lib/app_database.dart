// This generated-consumer fixture intentionally omits public API prose and explicit DSL types.
// ignore_for_file: public_member_api_docs, specify_nonobvious_property_types

import 'package:rivet/rivet.dart';
import 'package:rivet_fixture_schema/package_users.dart' as schema hide PackageAccess;

part 'app_database.rivet.dart';

final class AccessRecordConverter
    implements RivetTypeConverter<(schema.AccessLevel, {schema.PackageUsers user}), String> {
  const AccessRecordConverter();

  @override
  (schema.AccessLevel, {schema.PackageUsers user}) fromSql(String value) =>
      (schema.AccessLevel.viewer, user: schema.PackageUsers());

  @override
  String toSql((schema.AccessLevel, {schema.PackageUsers user}) value) => value.$1.name;
}

final class AccessCallbackConverter
    implements RivetTypeConverter<schema.AccessLevel Function(schema.PackageUsers), String> {
  const AccessCallbackConverter();

  @override
  schema.AccessLevel Function(schema.PackageUsers) fromSql(String value) =>
      (_) => schema.AccessLevel.viewer;

  @override
  String toSql(schema.AccessLevel Function(schema.PackageUsers) value) =>
      value(schema.PackageUsers()).name;
}

@RivetTable(schema: 'fixture', name: 'appUsers')
final class PackageUsers extends RivetTableDefinition<PackageUsers> {
  static const db = _$PackageUsersDB();

  late final packageName = text().references<schema.PackageUsers>((users) => users.name)();
  late final access = enumText<schema.AccessLevel>()();
  late final accessRecord = text().map(const AccessRecordConverter())();
  late final accessCallback = text().map(const AccessCallbackConverter())();
  late final packageAccess = text().map(const schema.PackageAccessConverter())();
  late final package = one<schema.PackageUsers>(
    fields: [packageName],
    references: (users) => [users.name],
  )();
  late final projects = many<AppProjects>(relation: (project) => project.owner)();
}

@RivetTable(schema: 'fixture', name: 'appProjects')
final class AppProjects extends RivetTableDefinition<AppProjects> {
  static const db = _$AppProjectsDB();

  late final id = integer().primaryKey()();
  late final ownerName = text()();
  late final packageOwnerName = text()();
  late final owner = one<PackageUsers>(
    fields: [ownerName],
    references: (users) => [users.packageName],
  )();
  late final packageOwner = one<schema.PackageUsers>(
    fields: [packageOwnerName],
    references: (users) => [users.name],
  )();
  late final labels = many<schema.PackageLabels>().through<AppProjectLabels>(
    source: (link) => link.project,
    target: (link) => link.label,
  )();
}

@RivetTable(schema: 'fixture', name: 'appProjectLabels')
final class AppProjectLabels extends RivetTableDefinition<AppProjectLabels> {
  static const db = _$AppProjectLabelsDB();

  late final projectId = integer()();
  late final labelCode = text()();
  late final project = one<AppProjects>(
    fields: [projectId],
    references: (project) => [project.id],
  )();
  late final label = one<schema.PackageLabels>(
    fields: [labelCode],
    references: (label) => [label.code],
  )();
}

const schemaTables = <Type>[
  schema.PackageUsers,
  schema.PackageLabels,
  schema.PackageLabelNotes,
];
const fixtureTables = <Type>[
  ...schemaTables,
  PackageUsers,
  AppProjects,
  AppProjectLabels,
];

@RivetDatabase(name: 'fixture_app', tables: fixtureTables)
final class FixtureAppDatabase extends _$FixtureAppDatabase {}

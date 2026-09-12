// This generated-consumer fixture intentionally omits public API prose and explicit DSL types.
// ignore_for_file: public_member_api_docs, specify_nonobvious_property_types

import 'package:rivet/rivet.dart';
import 'package:rivet_fixture_schema/package_users.dart' as schema;

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
  late final package = one<schema.PackageUsers>(
    fields: [packageName],
    references: (users) => [users.name],
  )();
}

const schemaTables = <Type>[schema.PackageUsers];
const fixtureTables = <Type>[...schemaTables, PackageUsers];

@RivetDatabase(name: 'fixture_app', tables: fixtureTables)
final class FixtureAppDatabase extends _$FixtureAppDatabase {}

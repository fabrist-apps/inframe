// This generated-consumer fixture intentionally omits public API prose and explicit DSL types.
// ignore_for_file: public_member_api_docs, specify_nonobvious_property_types

import 'package:rivet/rivet.dart';
import 'package:rivet_fixture_schema/package_users.dart';

part 'app_database.rivet.dart';

@RivetTable(schema: 'fixture', name: 'appUsers')
final class AppUsers extends RivetTableDefinition<AppUsers> {
  static const db = _$AppUsersDB();

  late final access = enumText<AccessLevel>()();
}

@RivetDatabase(name: 'fixture_app', tables: [PackageUsers, AppUsers])
final class FixtureAppDatabase extends _$FixtureAppDatabase {}

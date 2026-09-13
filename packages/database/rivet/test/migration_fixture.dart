import 'package:rivet/rivet.dart';

part 'migration_fixture.rivet.dart';

@RivetTable(schema: 'auth', name: 'users')
final class MigrationUsers extends RivetTableDefinition<MigrationUsers> {
  static const db = _$MigrationUsersDB();

  late final RivetOrderableColumn<int> id = integer().primaryKey()();
  late final RivetOrderableColumn<String> name = text()();
}

@RivetDatabase(name: 'migration_fixture', tables: [MigrationUsers])
final class MigrationFixtureDatabase extends _$MigrationFixtureDatabase {}

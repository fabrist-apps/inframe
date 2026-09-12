import 'package:rivet/rivet.dart';
import 'package:rivet_fixture_app/app_database.dart';
import 'package:rivet_fixture_schema/package_users.dart' as schema;
import 'package:test/test.dart';

void main() {
  test('composes generated package-owned schemas in an application database', () async {
    final packageUsers = schema.PackageUsers.db.buildSchema();

    expect(packageUsers.schemaName, 'fixture');
    expect(packageUsers.tableName, 'packageUsers');
    expect(packageUsers.definition.access.codec, isA<RivetEnumCodec<schema.AccessLevel>>());
    expect(schema.AccessLevelRivetEnum.codec.renamedFrom, 'role');
    expect(schema.AccessLevelRivetEnum.codec.renamedLabels, {'owner-label': 'admin-label'});
    final appUsers = PackageUsers.db.buildSchema();
    expect(appUsers.definition.access.codec, isA<RivetEnumCodec<schema.AccessLevel>>());

    final database = await FixtureAppDatabase().open(
      connection: RivetConnection.url(
        'postgresql://localhost/unused',
        sslMode: RivetSslMode.disable,
      ),
    );
    expect(database.tables.map((table) => table.definition.runtimeType), [
      schema.PackageUsers,
      PackageUsers,
    ]);
    expect(appUsers.relations['package']?.targetTable, schema.PackageUsers);
    await database.close();
  });
}

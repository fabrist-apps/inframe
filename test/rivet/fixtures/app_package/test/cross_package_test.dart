import 'package:rivet/rivet.dart';
import 'package:rivet_fixture_app/app_database.dart';
import 'package:rivet_fixture_schema/package_users.dart';
import 'package:test/test.dart';

void main() {
  test('composes generated package-owned schemas in an application database', () async {
    final schema = PackageUsers.db.buildSchema();

    expect(schema.schemaName, 'fixture');
    expect(schema.tableName, 'packageUsers');
    expect(schema.definition.access.codec, isA<RivetEnumCodec<AccessLevel>>());

    final database = await FixtureAppDatabase().open(
      connection: RivetConnection.url(
        'postgresql://localhost/unused',
        sslMode: RivetSslMode.disable,
      ),
    );
    expect(database.tables.single.definition, isA<PackageUsers>());
    await database.close();
  });
}

import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:rivet_fixture_app/app_database.dart';
import 'package:rivet_fixture_schema/package_users.dart' as schema;
import 'package:test/test.dart';

void main() {
  group('cross-package Rivet consumer', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];

    test('should compose generated package-owned schemas', () async {
      final packageUsers = schema.PackageUsers.db.buildSchema();

      expect(packageUsers.schemaName, 'fixture');
      expect(packageUsers.tableName, 'packageUsers');
      expect(packageUsers.definition.access.codec, isA<RivetEnumCodec<schema.AccessLevel>>());
      expect(schema.AccessLevelRivetEnum.codec.renamedFrom, 'role');
      expect(schema.AccessLevelRivetEnum.codec.renamedLabels, {'owner-label': 'admin-label'});
      final appUsers = PackageUsers.db.buildSchema();
      expect(appUsers.definition.access.codec, isA<RivetEnumCodec<schema.AccessLevel>>());
      expect(
        PackageUsers.db.find(include: (include) => [include.package()]),
        isA<RivetFind<PackageUsers, PackageUsersRow>>(),
      );

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

    test(
      'should include a package-owned row in one statement',
      () async {
        final resolvedDatabaseUrl = databaseUrl!;
        final fixture = await pg.Connection.openFromUrl(resolvedDatabaseUrl);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS fixture CASCADE');
        await fixture.execute('CREATE SCHEMA fixture');
        await fixture.execute('''
          CREATE TYPE fixture."accessLevel" AS ENUM ('viewer', 'owner-label')
        ''');
        await fixture.execute('''
          CREATE TABLE fixture."packageUsers" (
            name text NOT NULL,
            access fixture."accessLevel" NOT NULL
          )
        ''');
        await fixture.execute('''
          CREATE TABLE fixture."appUsers" (
            "packageName" text NOT NULL,
            access fixture."accessLevel" NOT NULL,
            "accessRecord" text NOT NULL,
            "accessCallback" text NOT NULL,
            "packageAccess" text NOT NULL
          )
        ''');
        await fixture.execute('''
          INSERT INTO fixture."packageUsers" (name, access)
          VALUES ('Ada', 'owner-label')
        ''');
        await fixture.execute('''
          INSERT INTO fixture."appUsers"
            ("packageName", access, "accessRecord", "accessCallback", "packageAccess")
          VALUES ('Ada', 'viewer', 'viewer', 'viewer', 'viewer')
        ''');
        final statements = <String>[];
        final database = await FixtureAppDatabase().open(
          connection: RivetConnection.url(resolvedDatabaseUrl, onStatement: statements.add),
        );
        addTearDown(database.close);

        final row = await PackageUsers.db
            .find(include: (include) => [include.package()])
            .getSingle(database);
        final related = (row.package as LoadedRelation<schema.PackageUsersRow?>).value;

        expect(related?.name, 'Ada');
        expect(related?.access, schema.AccessLevel.owner);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

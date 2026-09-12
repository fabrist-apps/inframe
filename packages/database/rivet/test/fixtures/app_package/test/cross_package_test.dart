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
        AppProjects,
      ]);
      expect(appUsers.relations['package']?.targetTable, schema.PackageUsers);
      await database.close();
    });

    test(
      'should load cross-package nested and sibling relations in one statement',
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
          CREATE TABLE fixture."appProjects" (
            id integer NOT NULL,
            "ownerName" text NOT NULL,
            "packageOwnerName" text NOT NULL
          )
        ''');
        await fixture.execute('''
          INSERT INTO fixture."packageUsers" (name, access)
          VALUES ('Ada', 'owner-label'), ('Grace', 'viewer')
        ''');
        await fixture.execute('''
          INSERT INTO fixture."appUsers"
            ("packageName", access, "accessRecord", "accessCallback", "packageAccess")
          VALUES
            ('Ada', 'viewer', 'viewer', 'viewer', 'viewer'),
            ('Grace', 'viewer', 'viewer', 'viewer', 'viewer')
        ''');
        await fixture.execute('''
          INSERT INTO fixture."appProjects" (id, "ownerName", "packageOwnerName")
          VALUES (1, 'Ada', 'Ada'), (2, 'Ada', 'Grace'), (3, 'Grace', 'Grace')
        ''');
        final statements = <String>[];
        final database = await FixtureAppDatabase().open(
          connection: RivetConnection.url(resolvedDatabaseUrl, onStatement: statements.add),
        );
        addTearDown(database.close);

        final rows = await PackageUsers.db
            .find(
              orderBy: (user) => [user.packageName.asc()],
              include: (include) => [
                include.package(),
                include.projects(
                  orderBy: (project) => [project.id.desc()],
                  limit: 1,
                  include: (include) => [include.owner(), include.packageOwner()],
                ),
              ],
            )
            .get(database);
        final ada = rows[0];
        final grace = rows[1];
        final related = (ada.package as LoadedRelation<schema.PackageUsersRow?>).value;
        final adaProjects = (ada.projects as LoadedRelation<List<AppProjectsRow>>).value;
        final graceProjects = (grace.projects as LoadedRelation<List<AppProjectsRow>>).value;

        expect(related?.name, 'Ada');
        expect(related?.access, schema.AccessLevel.owner);
        expect(adaProjects.map((project) => project.id), [2]);
        expect(graceProjects.map((project) => project.id), [3]);
        expect(
          (adaProjects.single.owner as LoadedRelation<PackageUsersRow?>).value?.packageName,
          'Ada',
        );
        expect(
          (adaProjects.single.packageOwner as LoadedRelation<schema.PackageUsersRow?>).value?.name,
          'Grace',
        );
        expect(
          (adaProjects.single.owner as LoadedRelation<PackageUsersRow?>).value?.projects.isLoaded,
          isFalse,
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

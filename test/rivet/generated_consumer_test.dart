import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('generated Rivet consumer', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr116');
      await fixture.execute('''
        CREATE TABLE IF NOT EXISTS fbr116."userProfiles" (
          "displayName" text NOT NULL
        )
      ''');
      await fixture.execute('TRUNCATE fbr116."userProfiles"');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should read zero, one, and multiple rows through generated APIs',
      () async {
        expect(await UserProfiles.db.find().get(database), isEmpty);

        await fixture.execute('''
          INSERT INTO fbr116."userProfiles" ("displayName")
          VALUES ('Ada'), ('Grace')
        ''');

        final one = await UserProfiles.db
            .find(where: (users) => users.displayName.equals('Ada'))
            .get(database);
        final all = await UserProfiles.db.find().get(database);

        expect(one.single.displayName, 'Ada');
        expect(one.single.posts.isLoaded, isFalse);
        expect(all.map((row) => row.displayName), containsAll(['Ada', 'Grace']));
        expect(statements, hasLength(3));
        expect(
          statements.singleWhere((sql) => sql.contains('WHERE')),
          contains(r'"displayName" = $1'),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test('should expose generated schema metadata without analyzer dependencies', () {
      final users = UserProfiles.db.buildSchema();
      final posts = Posts.db.buildSchema();

      expect(users.formatVersion, 1);
      expect(users.indexes.single.name, 'display_name_idx');
      expect(users.constraints.single.name, 'display_name_present');
      expect(users.relations['posts']?.kind, RivetRelationKind.many);
      expect(posts.relations['author']?.kind, RivetRelationKind.one);
      expect(posts.columns.single.foreignKey?.targetTable, UserProfiles);
    });
  });
}

import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet delete integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr141 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr141');
      await fixture.execute('''
        CREATE TABLE fbr141."delete Parents" (
          id integer PRIMARY KEY,
          "display Name" text NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr141."cascade Children" (
          id integer PRIMARY KEY,
          "parentId" integer NOT NULL
            REFERENCES fbr141."delete Parents" (id) ON DELETE CASCADE
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr141."restrict Children" (
          id integer PRIMARY KEY,
          "parentId" integer NOT NULL
            REFERENCES fbr141."delete Parents" (id) ON DELETE RESTRICT
        )
      ''');
      await fixture.execute('''
        INSERT INTO fbr141."delete Parents" VALUES
          (1, 'O''Reilly'), (2, 'Restricted'), (3, 'Returning')
      ''');
      await fixture.execute('''
        INSERT INTO fbr141."cascade Children" VALUES (10, 1), (11, 3)
      ''');
      await fixture.execute('''
        INSERT INTO fbr141."restrict Children" VALUES (20, 2)
      ''');
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
      'should delete selected rows and let PostgreSQL cascade in one statement',
      () async {
        final affected = await MutationDeleteParents.db
            .delete(where: (parents) => parents.label.equals("O'Reilly"))
            .execute(database);

        expect(affected, 1);
        expect(
          await fixture.execute(
            'SELECT * FROM fbr141."cascade Children" WHERE "parentId" = 1',
          ),
          isEmpty,
        );
        expect(statements, hasLength(1));
        expect(statements.single, contains(r'"display Name" = $1::text'));
        expect(statements.single, isNot(contains('SELECT')));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should return zero, complete deleted rows, and all-row counts',
      () async {
        expect(
          await MutationDeleteParents.db
              .delete(where: (parents) => parents.id.equals(99))
              .execute(database),
          0,
        );
        final returned = await MutationDeleteParents.db
            .delete(where: (parents) => parents.id.equals(3))
            .returning()
            .get(database);
        expect(returned.single.id, 3);
        expect(returned.single.label, 'Returning');
        expect(returned.single.cascadeChildren.isLoaded, isFalse);
        expect(returned.single.restrictChildren.isLoaded, isFalse);
        await fixture.execute('DELETE FROM fbr141."restrict Children"');
        expect(await MutationDeleteParents.db.delete().execute(database), 2);
        expect(
          await fixture.execute('SELECT * FROM fbr141."delete Parents"'),
          isEmpty,
        );
        expect(statements, hasLength(3));
        expect(statements[1], contains(' RETURNING '));
        expect(statements.every((statement) => !statement.contains('SELECT')), isTrue);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve restrictive foreign-key errors',
      () async {
        await expectLater(
          MutationDeleteParents.db
              .delete(where: (parents) => parents.id.equals(2))
              .execute(database),
          throwsA(isA<RivetDatabaseException>()),
        );
        expect(statements, hasLength(1));
        expect(
          await fixture.execute(
            'SELECT * FROM fbr141."delete Parents" WHERE id = 2',
          ),
          hasLength(1),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should restore target and cascaded rows on transaction rollback',
      () async {
        await expectLater(
          database.transaction((transaction) async {
            expect(
              await MutationDeleteParents.db
                  .delete(where: (parents) => parents.id.equals(1))
                  .execute(transaction),
              1,
            );
            throw StateError('roll back delete');
          }),
          throwsStateError,
        );

        expect(
          await fixture.execute(
            'SELECT * FROM fbr141."delete Parents" WHERE id = 1',
          ),
          hasLength(1),
        );
        expect(
          await fixture.execute(
            'SELECT * FROM fbr141."cascade Children" WHERE "parentId" = 1',
          ),
          hasLength(1),
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

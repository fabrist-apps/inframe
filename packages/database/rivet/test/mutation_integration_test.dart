import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet mutation integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr138');
      await fixture.execute('DROP TABLE IF EXISTS fbr138."mutationChildren"');
      await fixture.execute('DROP TABLE IF EXISTS fbr138."mutationParents"');
      await fixture.execute('DROP TABLE IF EXISTS fbr138."mutationUsers"');
      await fixture.execute('''
        CREATE TABLE fbr138."mutationParents" (
          id integer PRIMARY KEY,
          name text NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr138."mutationChildren" (
          id integer PRIMARY KEY,
          "parentId" integer NOT NULL REFERENCES fbr138."mutationParents" (id)
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr138."mutationUsers" (
          id integer PRIMARY KEY,
          name text NOT NULL,
          nickname text,
          "createdAt" timestamptz(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
          "updatedAt" timestamptz(3) NOT NULL,
          "nullableDefault" text,
          "serverValue" integer NOT NULL DEFAULT 42
        )
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
      mutationDefaultCalls = 0;
      mutationUpdateCalls = 0;
      mutationNullableCalls = 0;
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should insert and return a complete row in one statement',
      () async {
        final affected = await MutationUsers.db
            .insert(
              MutationUsersCompanion.insert(
                id: const RivetValue.present(1),
                name: const RivetValue.present('Ada'),
              ),
            )
            .execute(database);
        final returned = await MutationUsers.db
            .insert(
              MutationUsersCompanion.insert(
                id: const RivetValue.present(2),
                name: const RivetValue.present('Grace'),
                nickname: const RivetValue.present(null),
              ),
            )
            .returning()
            .get(database);

        expect(affected, 1);
        expect(returned.single.id, 2);
        expect(returned.single.name, 'Grace');
        expect(returned.single.nickname, isNull);
        expect(returned.single.createdAt, DateTime.utc(2026, 9, 12, 10, 11, 2));
        expect(returned.single.updatedAt, DateTime.utc(2026, 9, 12, 11, 12, 2));
        expect(returned.single.nullableDefault, isNull);
        expect(returned.single.serverValue, 42);
        expect(mutationDefaultCalls, 2);
        expect(mutationUpdateCalls, 2);
        expect(mutationNullableCalls, 2);
        expect(statements, hasLength(2));
        expect(statements.first, isNot(contains('RETURNING')));
        expect(statements.last, contains('RETURNING'));
        expect(statements.every((statement) => !statement.contains('SELECT')), isTrue);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should insert explicit parent and child mutations in one transaction',
      () async {
        await database.transaction((transaction) async {
          final parent = await MutationParents.db
              .insert(
                MutationParentsCompanion.insert(
                  id: const RivetValue.present(1),
                  name: const RivetValue.present('Ada'),
                ),
              )
              .returning()
              .get(transaction);
          expect(parent.single.children.isLoaded, isFalse);
          expect(
            await MutationChildren.db
                .insert(
                  MutationChildrenCompanion.insert(
                    id: const RivetValue.present(1),
                    parentId: const RivetValue.present(1),
                  ),
                )
                .execute(transaction),
            1,
          );
        });

        expect(statements, hasLength(2));
        expect(
          await fixture.execute('SELECT * FROM fbr138."mutationChildren"'),
          hasLength(1),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should roll back separate parent and child mutations together',
      () async {
        await expectLater(
          database.transaction((transaction) async {
            await MutationParents.db
                .insert(
                  MutationParentsCompanion.insert(
                    id: const RivetValue.present(1),
                    name: const RivetValue.present('Ada'),
                  ),
                )
                .execute(transaction);
            await MutationChildren.db
                .insert(
                  MutationChildrenCompanion.insert(
                    id: const RivetValue.present(1),
                    parentId: const RivetValue.present(1),
                  ),
                )
                .execute(transaction);
            throw StateError('roll back fixture');
          }),
          throwsStateError,
        );

        expect(statements, hasLength(2));
        expect(
          await fixture.execute('SELECT * FROM fbr138."mutationParents"'),
          isEmpty,
        );
        expect(
          await fixture.execute('SELECT * FROM fbr138."mutationChildren"'),
          isEmpty,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

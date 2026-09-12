import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet insertMany integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr142 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr142');
      await fixture.execute('''
        CREATE TABLE fbr142."mutationBatchParents" (
          id integer PRIMARY KEY,
          name text NOT NULL,
          "createdAt" timestamptz(3) NOT NULL,
          nickname text,
          "serverValue" integer NOT NULL DEFAULT 42
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr142."mutationBatchChildren" (
          id integer PRIMARY KEY,
          "parentId" integer NOT NULL
            REFERENCES fbr142."mutationBatchParents" (id)
        )
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
      batchCreatedCalls = 0;
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should resolve each row and return complete rows in one batch statement',
      () async {
        final explicitTime = DateTime.utc(2026);
        final affected = await MutationBatchParents.db
            .insertMany([
              _parent(1, 'Ada'),
              _parent(
                2,
                'Grace',
                createdAt: RivetValue.present(explicitTime),
                nickname: const RivetValue.present('G'),
                serverValue: const RivetValue.present(7),
              ),
            ])
            .execute(database);
        final returned = await MutationBatchParents.db
            .insertMany([
              _parent(3, 'Linus'),
              _parent(4, 'Margaret'),
            ])
            .returning()
            .get(database);

        expect(affected, 2);
        expect(returned.map((row) => row.id), [3, 4]);
        expect(returned.map((row) => row.serverValue), [42, 42]);
        expect(returned.every((row) => !row.children.isLoaded), isTrue);
        expect(batchCreatedCalls, 3);
        final stored = await fixture.execute('''
          SELECT id, name, "createdAt", nickname, "serverValue"
          FROM fbr142."mutationBatchParents" ORDER BY id
        ''');
        expect(stored, hasLength(4));
        expect(stored[0][3], isNull);
        expect(stored[1][2], explicitTime);
        expect(stored[1][3], 'G');
        expect(stored[1][4], 7);
        expect(statements, hasLength(2));
        expect(statements.every((statement) => statement.contains('), (')), isTrue);
        expect(statements.last, contains(' RETURNING '));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should keep explicit chunks separate and roll all back after a later failure',
      () async {
        await expectLater(
          database.transaction((transaction) async {
            expect(
              await MutationBatchParents.db
                  .insertMany([
                    _parent(1, 'Ada'),
                    _parent(2, 'Grace'),
                  ])
                  .execute(transaction),
              2,
            );
            await MutationBatchParents.db
                .insertMany([
                  _parent(2, 'Duplicate'),
                  _parent(3, 'Linus'),
                ])
                .execute(transaction);
          }),
          throwsA(isA<RivetDatabaseException>()),
        );

        expect(
          await fixture.execute('SELECT * FROM fbr142."mutationBatchParents"'),
          isEmpty,
        );
        expect(batchCreatedCalls, 4);
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

MutationBatchParentsCompanion _parent(
  int id,
  String name, {
  RivetValue<MutationBatchParents, DateTime, DateTime> createdAt = const RivetValue.absent(),
  RivetValue<MutationBatchParents, String?, String?> nickname = const RivetValue.absent(),
  RivetValue<MutationBatchParents, int, int> serverValue = const RivetValue.absent(),
}) => MutationBatchParentsCompanion.insert(
  id: RivetValue.present(id),
  name: RivetValue.present(name),
  createdAt: createdAt,
  nickname: nickname,
  serverValue: serverValue,
);

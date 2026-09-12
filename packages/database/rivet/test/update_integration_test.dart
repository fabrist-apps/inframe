import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet update integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr140 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr140');
      await fixture.execute('''
        CREATE TABLE fbr140."mutationUpdateUsers" (
          id integer PRIMARY KEY,
          name text NOT NULL,
          age integer NOT NULL,
          "updatedAt" timestamptz(3) NOT NULL,
          "nullableNote" text,
          code text NOT NULL,
          "defaultOnly" text NOT NULL,
          "serverOnly" integer NOT NULL DEFAULT 42
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr140."mutationUpdateChildren" (
          id integer PRIMARY KEY,
          "userId" integer NOT NULL
            REFERENCES fbr140."mutationUpdateUsers" (id)
        )
      ''');
      await fixture.execute('''
        INSERT INTO fbr140."mutationUpdateUsers"
          (id, name, age, "updatedAt", "nullableNote", code, "defaultOnly", "serverOnly")
        VALUES
          (1, 'Ada', 10, '2026-01-01T00:00:00Z', 'first', 'code:old', 'stored', 9),
          (2, 'Grace', 20, '2026-01-01T00:00:00Z', 'second', 'code:old', 'stored', 9)
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
      _resetUpdateHooks();
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should restrict updates and return complete rows in one statement',
      () async {
        final affected = await MutationUpdateUsers.db
            .update(
              MutationUpdateUsersCompanion.update(
                age: RivetValue.expression((users) => users.age + 1),
                updatedAt: RivetValue.present(DateTime.utc(2026, 2)),
                nullableNote: const RivetValue.present(null),
                code: RivetValue.expression(
                  (users) => users.code.storage.value('code:explicit'),
                ),
              ),
              where: (users) => users.id.equals(1),
            )
            .execute(database);
        final returned = await MutationUpdateUsers.db
            .update(
              MutationUpdateUsersCompanion.update(
                age: RivetValue.expression((users) => users.age + 1),
                updatedAt: RivetValue.present(DateTime.utc(2026, 2, 2)),
                nullableNote: const RivetValue.present(null),
                code: RivetValue.expression(
                  (users) => users.code.storage.value('code:returning'),
                ),
              ),
              where: (users) => users.id.equals(2),
            )
            .returning()
            .get(database);

        expect(affected, 1);
        expect(returned.single.age, 21);
        expect(returned.single.code.value, 'returning');
        expect(returned.single.children.isLoaded, isFalse);
        expect(updateTimestampCalls, 0);
        expect(updateNullableCalls, 0);
        expect(updateCodeCalls, 0);
        final ages = await fixture.execute(
          'SELECT id, age FROM fbr140."mutationUpdateUsers" ORDER BY id',
        );
        expect(ages.map((row) => row.toList()), [
          [1, 11],
          [2, 21],
        ]);
        expect(statements, hasLength(2));
        expect(statements.every((statement) => !statement.contains('SELECT')), isTrue);
        expect(statements.last, contains(' RETURNING '));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should apply one hook value to all rows and reevaluate zero-match plans',
      () async {
        final update = MutationUpdateUsers.db.update(
          MutationUpdateUsersCompanion.update(),
        );
        final prepared = update.prepare();
        expect(updateTimestampCalls, 0);
        expect(updateNullableCalls, 0);
        expect(updateCodeCalls, 0);

        expect(await prepared.execute(database), 2);
        expect(updateTimestampCalls, 1);
        expect(updateNullableCalls, 1);
        expect(updateCodeCalls, 1);
        expect(updateDefaultOnlyCalls, 0);
        final hooked = await fixture.execute('''
          SELECT "updatedAt", "nullableNote", code, "defaultOnly", "serverOnly"
          FROM fbr140."mutationUpdateUsers" ORDER BY id
        ''');
        expect(hooked[0][0], hooked[1][0]);
        expect(hooked[0][1], isNull);
        expect(hooked[1][1], isNull);
        expect(hooked[0][2], 'code:hook-1');
        expect(hooked[1][2], 'code:hook-1');
        expect(hooked.every((row) => row[3] == 'stored' && row[4] == 9), isTrue);

        final zeroMatches = MutationUpdateUsers.db
            .update(
              MutationUpdateUsersCompanion.update(),
              where: (users) => users.id.equals(99),
            )
            .prepare();
        expect(await zeroMatches.execute(database), 0);
        expect(await zeroMatches.execute(database), 0);
        expect(updateTimestampCalls, 3);
        expect(updateNullableCalls, 3);
        expect(updateCodeCalls, 3);
        expect(mutationCodeEncodeCalls, 3);
        expect(statements, hasLength(3));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should accept an existing value and reject truly empty updates before SQL',
      () async {
        expect(
          await MutationUpdateUsers.db
              .update(
                MutationUpdateUsersCompanion.update(
                  name: const RivetValue.present('Ada'),
                  updatedAt: RivetValue.present(DateTime.utc(2026)),
                  nullableNote: const RivetValue.present('first'),
                  code: const RivetValue.present(MutationCode('old')),
                ),
                where: (users) => users.id.equals(1),
              )
              .execute(database),
          1,
        );
        expect(
          () => MutationUpdateChildren.db
              .update(MutationUpdateChildrenCompanion.update())
              .execute(database),
          throwsA(isA<RivetEmptyUpdateException>()),
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should commit, roll back, and expire transaction update executors',
      () async {
        late RivetTransaction expired;
        await database.transaction((transaction) async {
          expired = transaction;
          expect(
            await MutationUpdateUsers.db
                .update(
                  _explicitName('Committed'),
                  where: (users) => users.id.equals(1),
                )
                .execute(transaction),
            1,
          );
        });
        await expectLater(
          database.transaction((transaction) async {
            await MutationUpdateUsers.db
                .update(
                  _explicitName('Rolled back'),
                  where: (users) => users.id.equals(2),
                )
                .execute(transaction);
            throw StateError('roll back update');
          }),
          throwsStateError,
        );
        await expectLater(
          MutationUpdateUsers.db
              .update(
                _explicitName('Expired'),
                where: (users) => users.id.equals(1),
              )
              .execute(expired),
          throwsA(isA<RivetExecutorClosedException>()),
        );

        final names = await fixture.execute(
          'SELECT name FROM fbr140."mutationUpdateUsers" ORDER BY id',
        );
        expect(names.map((row) => row[0]), ['Committed', 'Grace']);
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

MutationUpdateUsersCompanion _explicitName(String name) => MutationUpdateUsersCompanion.update(
  name: RivetValue.present(name),
  updatedAt: RivetValue.present(DateTime.utc(2026)),
  nullableNote: const RivetValue.present(null),
  code: const RivetValue.present(MutationCode('old')),
);

void _resetUpdateHooks() {
  updateTimestampCalls = 0;
  updateNullableCalls = 0;
  updateCodeCalls = 0;
  updateDefaultOnlyCalls = 0;
  mutationCodeEncodeCalls = 0;
}

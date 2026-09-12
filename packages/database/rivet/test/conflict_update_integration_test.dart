import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet conflict update integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr144 CASCADE');
      await fixture.execute('DROP SCHEMA IF EXISTS fbr143 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr144');
      await fixture.execute('CREATE SCHEMA fbr143');
      await fixture.execute('''
        CREATE TABLE fbr144."mutationUpsertUsers" (
          id integer PRIMARY KEY,
          email text NOT NULL UNIQUE,
          name text NOT NULL,
          age integer NOT NULL CHECK (age > 0),
          active boolean NOT NULL,
          "conditionValue" integer,
          "updatedAt" timestamptz(3) NOT NULL,
          note text,
          code text NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE UNIQUE INDEX mutation_upsert_nonempty_name
        ON fbr144."mutationUpsertUsers" (name)
        WHERE NOT (name = '')
      ''');
      await fixture.execute('''
        INSERT INTO fbr144."mutationUpsertUsers"
          (id, email, name, age, active, "conditionValue", "updatedAt", note, code)
        VALUES
          (1, 'seed@example.com', 'shared', 30, true, NULL,
           '2026-01-01T00:00:00Z', 'seed', 'code:seed')
      ''');
      await fixture.execute('''
        CREATE TABLE fbr143."mutationConflictGroups" (
          id integer PRIMARY KEY
        )
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
      _resetHooks();
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should run the shared partial-index example and return updated rows',
      () async {
        final returned = await MutationUpsertUsers.db
            .insert(
              _user(2, email: 'new@example.com', name: 'shared', age: 31),
              onConflict: _updateOlderAge,
            )
            .returning()
            .get(database);

        expect(returned, hasLength(1));
        expect(returned.single.id, 1);
        expect(returned.single.age, 31);
        expect(returned.single.updatedAt, DateTime.utc(2026, 9, 12, 18, 0, 1));
        expect(returned.single.note, 'update-1');
        expect(returned.single.code.value, 'update-1');
        expect(upsertTimestampDefaultCalls, 1);
        expect(upsertTimestampUpdateCalls, 1);
        expect(statements, hasLength(1));
        expect(statements.single, contains(' ON CONFLICT ("name") WHERE '));
        expect(statements.single, contains(' DO UPDATE SET '));
        expect(statements.single, contains('"mutationUpsertUsers"."age" < "excluded"."age"'));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should evaluate hooks but skip false and SQL NULL action predicates',
      () async {
        expect(
          await MutationUpsertUsers.db
              .insert(
                _user(2, email: 'lower@example.com', name: 'shared', age: 29),
                onConflict: _updateOlderAge,
              )
              .execute(database),
          0,
        );
        final nullResult = await MutationUpsertUsers.db
            .insert(
              _user(3, email: 'null@example.com', name: 'shared', age: 40),
              onConflict: (conflict) => conflict.update(
                target: (user) => [user.name],
                targetWhere: (user) => ~user.name.equals(''),
                set: (_, excluded) => MutationUpsertUsersCompanion.update(
                  age: RivetValue.expression((_) => excluded.age),
                ),
                where: (old, excluded) =>
                    old.conditionValue.lessThanExpression(excluded.conditionValue),
              ),
            )
            .returning()
            .get(database);

        expect(nullResult, isEmpty);
        expect(upsertTimestampUpdateCalls, 2);
        expect(upsertNoteUpdateCalls, 2);
        expect(upsertCodeUpdateCalls, 2);
        final stored = await fixture.execute(
          'SELECT age, note, code FROM fbr144."mutationUpsertUsers" WHERE id = 1',
        );
        expect(stored.single[0], 30);
        expect(stored.single[1], 'seed');
        expect(stored.single[2], 'code:seed');
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should evaluate update hooks without applying them when no conflict occurs',
      () async {
        final returned = await MutationUpsertUsers.db
            .insert(
              _user(2, email: 'fresh@example.com', name: 'fresh', age: 22),
              onConflict: _updateOlderAge,
            )
            .returning()
            .get(database);

        expect(returned.single.id, 2);
        expect(returned.single.updatedAt, DateTime.utc(2026, 9, 12, 17, 0, 1));
        expect(returned.single.note, 'insert-1');
        expect(returned.single.code.value, 'insert-1');
        expect(upsertTimestampUpdateCalls, 1);
        expect(upsertNoteUpdateCalls, 1);
        expect(upsertCodeUpdateCalls, 1);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should let explicit values, nulls, and mapped expressions suppress hooks',
      () async {
        final explicitTime = DateTime.utc(2026, 8);
        final returned = await MutationUpsertUsers.db
            .insert(
              _user(2, email: 'explicit@example.com', name: 'shared', age: 35),
              onConflict: (conflict) => conflict.update(
                target: (user) => [user.name],
                targetWhere: (user) => ~user.name.equals(''),
                set: (_, excluded) => MutationUpsertUsersCompanion.update(
                  age: RivetValue.expression((_) => excluded.age),
                  updatedAt: RivetValue.present(explicitTime),
                  note: const RivetValue.present(null),
                  code: RivetValue.expression((_) => excluded.code.storage),
                ),
              ),
            )
            .returning()
            .get(database);

        expect(returned.single.updatedAt, explicitTime);
        expect(returned.single.note, isNull);
        expect(returned.single.code.value, 'insert-1');
        expect(upsertTimestampUpdateCalls, 0);
        expect(upsertNoteUpdateCalls, 0);
        expect(upsertCodeUpdateCalls, 0);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve unrelated errors and repeated-key cardinality failures',
      () async {
        await expectLater(
          MutationUpsertUsers.db
              .insert(
                _user(2, email: 'seed@example.com', name: 'different'),
                onConflict: _updateOlderAge,
              )
              .execute(database),
          throwsA(isA<RivetDatabaseException>()),
        );
        await expectLater(
          MutationUpsertUsers.db
              .insert(
                _user(3, email: 'invalid@example.com', name: 'invalid', age: -1),
                onConflict: _updateOlderAge,
              )
              .execute(database),
          throwsA(isA<RivetDatabaseException>()),
        );
        await expectLater(
          MutationUpsertUsers.db
              .insertMany(
                [
                  _user(4, email: 'first@example.com', name: 'shared', age: 31),
                  _user(5, email: 'second@example.com', name: 'shared', age: 32),
                ],
                onConflict: _updateOlderAge,
              )
              .execute(database),
          throwsA(isA<RivetDatabaseException>()),
        );

        final stored = await fixture.execute(
          'SELECT age FROM fbr144."mutationUpsertUsers" WHERE id = 1',
        );
        expect(stored.single[0], 30);
        expect(statements, hasLength(3));
        expect(statements.last, startsWith('INSERT INTO'));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should use one statement for successful mixed batch upserts',
      () async {
        final returned = await MutationUpsertUsers.db
            .insertMany(
              [
                _user(2, email: 'update@example.com', name: 'shared', age: 31),
                _user(3, email: 'insert@example.com', name: 'inserted', age: 20),
              ],
              onConflict: _updateOlderAge,
            )
            .returning()
            .get(database);

        expect(returned.map((row) => row.id), [1, 3]);
        expect(statements, hasLength(1));
        expect(statements.single, contains('), ('));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should roll back an explicit transaction after a cardinality failure',
      () async {
        await expectLater(
          database.transaction((transaction) async {
            await MutationUpsertUsers.db
                .insert(
                  _user(2, email: 'before@example.com', name: 'before'),
                  onConflict: _updateOlderAge,
                )
                .execute(transaction);
            await MutationUpsertUsers.db
                .insertMany(
                  [
                    _user(3, email: 'first@example.com', name: 'shared', age: 31),
                    _user(4, email: 'second@example.com', name: 'shared', age: 32),
                  ],
                  onConflict: _updateOlderAge,
                )
                .execute(transaction);
          }),
          throwsA(isA<RivetDatabaseException>()),
        );

        final inserted = await fixture.execute(
          'SELECT count(*) FROM fbr144."mutationUpsertUsers" WHERE id = 2',
        );
        expect(inserted.single[0], 0);
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject an empty effective set before sending SQL without a conflict',
      () async {
        expect(
          () => MutationConflictGroups.db
              .insert(
                MutationConflictGroupsCompanion.insert(
                  id: const RivetValue.present(1),
                ),
                onConflict: (conflict) => conflict.update(
                  target: (group) => [group.id],
                  set: (_, _) => MutationConflictGroupsCompanion.update(),
                ),
              )
              .execute(database),
          throwsA(isA<RivetEmptyUpdateException>()),
        );
        expect(statements, isEmpty);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

RivetConflictAction<MutationUpsertUsers> _updateOlderAge(
  RivetConflictBuilder<MutationUpsertUsers> conflict,
) => conflict.update(
  target: (user) => [user.name],
  targetWhere: (user) => ~user.name.equals(''),
  set: (old, excluded) => MutationUpsertUsersCompanion.update(
    age: RivetValue.expression((_) => excluded.age),
  ),
  where: (old, excluded) => old.age.lessThanExpression(excluded.age),
);

MutationUpsertUsersCompanion _user(
  int id, {
  required String email,
  required String name,
  int age = 30,
  bool active = true,
  RivetValue<MutationUpsertUsers, int?, int?> conditionValue = const RivetValue.absent(),
}) => MutationUpsertUsersCompanion.insert(
  id: RivetValue.present(id),
  email: RivetValue.present(email),
  name: RivetValue.present(name),
  age: RivetValue.present(age),
  active: RivetValue.present(active),
  conditionValue: conditionValue,
);

void _resetHooks() {
  upsertTimestampDefaultCalls = 0;
  upsertTimestampUpdateCalls = 0;
  upsertNoteDefaultCalls = 0;
  upsertNoteUpdateCalls = 0;
  upsertCodeDefaultCalls = 0;
  upsertCodeUpdateCalls = 0;
}

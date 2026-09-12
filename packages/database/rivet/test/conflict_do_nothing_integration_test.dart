import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet doNothing integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr143 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr143');
      await fixture.execute('''
        CREATE TABLE fbr143."mutationConflictGroups" (
          id integer PRIMARY KEY
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr143."mutationConflictParents" (
          id integer PRIMARY KEY,
          email text NOT NULL,
          username text NOT NULL UNIQUE,
          active boolean NOT NULL,
          name text NOT NULL,
          age integer NOT NULL CHECK (age > 0),
          "createdAt" timestamptz(3) NOT NULL,
          "requiredByDatabase" text NOT NULL,
          "groupId" integer REFERENCES fbr143."mutationConflictGroups" (id)
        )
      ''');
      await fixture.execute('''
        CREATE UNIQUE INDEX mutation_conflict_active_email
        ON fbr143."mutationConflictParents" (email)
        WHERE active = true
      ''');
      await fixture.execute('''
        CREATE TABLE fbr143."mutationConflictChildren" (
          id integer PRIMARY KEY,
          "parentId" integer NOT NULL
            REFERENCES fbr143."mutationConflictParents" (id)
        )
      ''');
      await fixture.execute('INSERT INTO fbr143."mutationConflictGroups" VALUES (1)');
      await fixture.execute('''
        INSERT INTO fbr143."mutationConflictParents"
          (id, email, username, active, name, age, "createdAt",
           "requiredByDatabase", "groupId")
        VALUES
          (1, 'shared@example.com', 'seed', true, 'Seed', 30,
           '2026-01-01T00:00:00Z', 'required', 1)
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
      conflictDefaultCalls = 0;
      conflictUpdateCalls = 0;
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should skip any eligible conflict and return only successful batch rows',
      () async {
        expect(
          await MutationConflictParents.db
              .insert(
                _parent(2, email: 'other@example.com', username: 'seed'),
                onConflict: (conflict) => conflict.doNothing(),
              )
              .execute(database),
          0,
        );
        final returned = await MutationConflictParents.db
            .insertMany(
              [
                _parent(3, email: 'third@example.com', username: 'seed'),
                _parent(4, email: 'fourth@example.com', username: 'fourth'),
              ],
              onConflict: (conflict) => conflict.doNothing(),
            )
            .returning()
            .get(database);

        expect(returned.map((row) => row.id), [4]);
        expect(returned.single.children.isLoaded, isFalse);
        expect(conflictDefaultCalls, 3);
        expect(conflictUpdateCalls, 0);
        expect(statements, hasLength(2));
        expect(statements.last, contains(' ON CONFLICT DO NOTHING RETURNING '));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should restrict handling to the selected target',
      () async {
        expect(
          await MutationConflictParents.db
              .insert(
                _parent(1, email: 'id@example.com', username: 'id-conflict'),
                onConflict: (conflict) => conflict.doNothing(
                  target: (parents) => [parents.id],
                ),
              )
              .execute(database),
          0,
        );
        await expectLater(
          MutationConflictParents.db
              .insert(
                _parent(2, email: 'outside@example.com', username: 'seed'),
                onConflict: (conflict) => conflict.doNothing(
                  target: (parents) => [parents.id],
                ),
              )
              .execute(database),
          throwsA(isA<RivetDatabaseException>()),
        );
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should infer a partial unique target from a literal predicate',
      () async {
        final returned = await MutationConflictParents.db
            .insertMany(
              [
                _parent(2, email: 'shared@example.com', username: 'active'),
                _parent(3, email: 'shared@example.com', username: 'inactive', active: false),
              ],
              onConflict: (conflict) => conflict.doNothing(
                target: (parents) => [parents.email],
                targetWhere: (parents) => parents.active.equals(true),
              ),
            )
            .returning()
            .get(database);

        expect(returned.map((row) => row.id), [3]);
        expect(returned.single.active, isFalse);
        expect(statements, hasLength(1));
        expect(
          statements.single,
          contains('ON CONFLICT ("email") WHERE "active" = TRUE::bool DO NOTHING'),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve foreign-key, check, and not-null errors',
      () async {
        final invalidRows = [
          _parent(2, email: 'foreign@example.com', username: 'foreign', groupId: 99),
          _parent(3, email: 'check@example.com', username: 'check', age: -1),
          _parent(
            4,
            email: 'null@example.com',
            username: 'null',
            requiredByDatabase: const RivetValue.present(null),
          ),
        ];

        for (final row in invalidRows) {
          await expectLater(
            MutationConflictParents.db
                .insert(
                  row,
                  onConflict: (conflict) => conflict.doNothing(),
                )
                .execute(database),
            throwsA(isA<RivetDatabaseException>()),
          );
        }
        expect(statements, hasLength(3));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

MutationConflictParentsCompanion _parent(
  int id, {
  required String email,
  required String username,
  bool active = true,
  int age = 30,
  int? groupId = 1,
  RivetValue<MutationConflictParents, String?, String?> requiredByDatabase =
      const RivetValue.present('required'),
}) => MutationConflictParentsCompanion.insert(
  id: RivetValue.present(id),
  email: RivetValue.present(email),
  username: RivetValue.present(username),
  active: RivetValue.present(active),
  name: RivetValue.present('User $id'),
  age: RivetValue.present(age),
  requiredByDatabase: requiredByDatabase,
  groupId: RivetValue.present(groupId),
);

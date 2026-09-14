import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet transactions and shutdown', () {
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
      await fixture.execute("INSERT INTO fbr116.\"userProfiles\" VALUES ('Ada')");
      await fixture.execute('CREATE EXTENSION IF NOT EXISTS vector');
      await fixture.execute('CREATE EXTENSION IF NOT EXISTS vectorscale');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 1),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should apply all vector tuning locally and reset it after commit',
      () async {
        await database.transaction((tx) async {
          await tx.setVectorSearchOptions(const HnswSearchOptions(efSearch: 80));
          await tx.setVectorSearchOptions(const IvfFlatSearchOptions(probes: 3));
          await tx.setVectorSearchOptions(
            const DiskAnnSearchOptions(searchListSize: 120, rescore: 60),
          );

          expect(await _vectorSettings(tx), ['80', '3', '120', '60']);
        });

        final afterCommit = await _vectorSettings(database);
        expect(afterCommit[0], isNot('80'));
        expect(afterCommit[1], isNot('3'));
        expect(afterCommit[2], isNot('120'));
        expect(afterCommit[3], isNot('60'));
        expect(statements.where((sql) => sql.contains('set_config')), hasLength(3));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reset vector tuning after rollback on the reused pool connection',
      () async {
        await expectLater(
          database.transaction<void>((tx) async {
            await tx.setVectorSearchOptions(
              const DiskAnnSearchOptions(searchListSize: 140, rescore: 70),
            );
            expect((await _vectorSettings(tx)).skip(2), ['140', '70']);
            throw StateError('roll back vector tuning');
          }),
          throwsA(isA<StateError>()),
        );

        final afterRollback = await _vectorSettings(database);
        expect(afterRollback[2], isNot('140'));
        expect(afterRollback[3], isNot('70'));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject invalid options and expired executors before setup SQL',
      () async {
        late RivetTransaction expired;
        await database.transaction((tx) async {
          expired = tx;
          final before = statements.length;
          await expectLater(
            tx.setVectorSearchOptions(const HnswSearchOptions(efSearch: 0)),
            throwsA(isA<RangeError>()),
          );
          await expectLater(
            tx.setVectorSearchOptions(const IvfFlatSearchOptions(probes: 32769)),
            throwsA(isA<RangeError>()),
          );
          await expectLater(
            tx.setVectorSearchOptions(const DiskAnnSearchOptions()),
            throwsA(isA<ArgumentError>()),
          );
          expect(statements, hasLength(before));
        });
        statements.clear();

        await expectLater(
          expired.setVectorSearchOptions(const HnswSearchOptions(efSearch: 80)),
          throwsA(isA<RivetExecutorClosedException>()),
        );
        expect(statements, isEmpty);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should report missing vector tuning capabilities explicitly',
      () async {
        const databaseName = 'fbr200_missing_vector';
        await fixture.execute('DROP DATABASE IF EXISTS $databaseName WITH (FORCE)');
        await fixture.execute('CREATE DATABASE $databaseName');
        final missingUrl = Uri.parse(databaseUrl!).replace(path: '/$databaseName').toString();
        final missingStatements = <String>[];
        final missingDatabase = await RivetTestDatabase().open(
          connection: RivetConnection.url(missingUrl, onStatement: missingStatements.add),
          pool: const RivetPoolOptions(maxConnections: 1),
        );
        addTearDown(() async {
          await missingDatabase.close();
          await fixture.execute('DROP DATABASE IF EXISTS $databaseName WITH (FORCE)');
        });

        await expectLater(
          missingDatabase.transaction(
            (tx) => tx.setVectorSearchOptions(
              const HnswSearchOptions(efSearch: 80),
            ),
          ),
          throwsA(isA<RivetCapabilityException>()),
        );
        expect(missingStatements, hasLength(1));
        expect(missingStatements.single, contains('pg_extension'));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reserve one connection and expire the transaction executor',
      () async {
        late RivetTransaction expired;
        final name = await database.transaction((transaction) async {
          expired = transaction;
          return (await UserProfiles.db.find().getSingle(transaction)).displayName;
        });

        expect(name, 'Ada');
        await expectLater(
          UserProfiles.db.find().get(expired),
          throwsA(isA<RivetExecutorClosedException>()),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should roll back a failed callback and return the reservation',
      () async {
        await expectLater(
          database.transaction<void>((transaction) async {
            await UserProfiles.db.find().getSingle(transaction);
            throw StateError('fail transaction');
          }),
          throwsA(isA<StateError>()),
        );
        expect((await UserProfiles.db.find().getSingle(database)).displayName, 'Ada');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should drain an accepted transaction and share repeated close completion',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final transaction = database.transaction((tx) async {
          entered.complete();
          await release.future;
          return UserProfiles.db.find().getSingle(tx);
        });
        await entered.future;

        final firstClose = database.close();
        final secondClose = database.close();
        var closed = false;
        unawaited(firstClose.then((_) => closed = true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(closed, isFalse);
        await expectLater(
          UserProfiles.db.find().get(database),
          throwsA(isA<RivetExecutorClosedException>()),
        );

        release.complete();
        expect((await transaction).displayName, 'Ada');
        await Future.wait([firstClose, secondClose]);
        expect(closed, isTrue);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject close from its own transaction callback promptly',
      () async {
        await database.transaction((tx) async {
          expect(database.close, throwsA(isA<RivetExecutorClosedException>()));
          expect((await UserProfiles.db.find().getSingle(tx)).displayName, 'Ada');
        });
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject root reads and mutations inside its own transaction',
      () async {
        await database.transaction((transaction) async {
          await expectLater(
            UserProfiles.db.find().get(database),
            throwsA(isA<RivetExecutorClosedException>()),
          );
          await expectLater(
            UserProfiles.db
                .insert(
                  UserProfilesCompanion.insert(
                    displayName: const RivetValue.present('Grace'),
                  ),
                )
                .execute(database),
            throwsA(isA<RivetExecutorClosedException>()),
          );

          expect(
            (await UserProfiles.db.find().getSingle(transaction)).displayName,
            'Ada',
          );
        });
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

Future<List<String?>> _vectorSettings(RivetExecutor executor) => executor
    .execute(
      RivetCompiledQuery('''
    SELECT current_setting('hnsw.ef_search', true),
           current_setting('ivfflat.probes', true),
           current_setting('diskann.query_search_list_size', true),
           current_setting('diskann.query_rescore', true)
  ''', const []),
      (values, _) => values.cast<String?>(),
    )
    .then((rows) => rows.single);

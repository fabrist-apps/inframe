import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet afterCommit', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;

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
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl),
        pool: const RivetPoolOptions(maxConnections: 1),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should release the reservation then await callbacks in order',
      () async {
        final events = <String>[];
        final result = await database.transaction((transaction) async {
          transaction
            ..afterCommit(() => events.add('sync'))
            ..afterCommit(() async {
              final row = await UserProfiles.db.find().getSingle(database);
              events.add(row.displayName);
            });
          return 42;
        });

        expect(result, 42);
        expect(events, ['sync', 'Ada']);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should discard callbacks on rollback',
      () async {
        var called = false;
        await expectLater(
          database.transaction<void>((transaction) async {
            transaction.afterCommit(() => called = true);
            throw StateError('rollback');
          }),
          throwsStateError,
        );
        expect(called, isFalse);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should continue callbacks and aggregate committed-state failures',
      () async {
        final events = <String>[];
        await expectLater(
          database.transaction<void>((transaction) async {
            transaction
              ..afterCommit(() => throw StateError('first'))
              ..afterCommit(() => events.add('continued'))
              ..afterCommit(() async => throw ArgumentError('last'));
          }),
          throwsA(
            isA<AfterCommitException>()
                .having((error) => error.alreadyCommitted, 'alreadyCommitted', isTrue)
                .having((error) => error.failures, 'failures', hasLength(2)),
          ),
        );
        expect(events, ['continued']);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should run database callbacks immediately and reject transaction ambiguity',
      () async {
        final transactionEntered = Completer<void>();
        final releaseTransaction = Completer<void>();
        final unrelatedTransaction = database.transaction<void>((transaction) async {
          transactionEntered.complete();
          await releaseTransaction.future;
        });
        addTearDown(() async {
          if (!releaseTransaction.isCompleted) releaseTransaction.complete();
          await unrelatedTransaction;
        });
        await transactionEntered.future;

        final completed = Completer<void>();
        final immediate = database.afterCommit(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          completed.complete();
        });
        await immediate.timeout(const Duration(seconds: 1));
        expect(completed.isCompleted, isTrue);
        await expectLater(
          database.afterCommit(() => throw StateError('immediate')),
          throwsStateError,
        );
        releaseTransaction.complete();
        await unrelatedTransaction;

        await database.transaction((transaction) async {
          await expectLater(
            database.afterCommit(() {}),
            throwsA(isA<RivetExecutorClosedException>()),
          );
        });
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should drain an accepted database callback during external close',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final callback = database.afterCommit(() async {
          entered.complete();
          await release.future;
        });
        await entered.future;

        var closed = false;
        final close = database.close();
        unawaited(close.then((_) => closed = true));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(closed, isFalse);

        release.complete();
        await callback;
        await close;
        expect(closed, isTrue);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject close in an own callback without deadlocking',
      () async {
        await expectLater(
          database.transaction<void>((transaction) async {
            transaction.afterCommit(database.close);
          }),
          throwsA(
            isA<AfterCommitException>().having(
              (error) => error.failures.single.error,
              'failure',
              isA<RivetExecutorClosedException>(),
            ),
          ),
        );
        expect((await UserProfiles.db.find().getSingle(database)).displayName, 'Ada');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

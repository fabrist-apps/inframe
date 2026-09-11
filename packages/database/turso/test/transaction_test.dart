@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:turso/turso.dart';

void main() {
  group('TursoDatabase transactions', () {
    for (final query in [false, true]) {
      test('should roll back caught ${query ? 'query' : 'execute'} validation failures', () async {
        final database = await TursoDatabase.open(TursoLocation.memory());
        addTearDown(database.close);
        await database.execute('CREATE TABLE events (value INTEGER)');

        await expectLater(
          database.transaction((tx) async {
            await tx.execute('INSERT INTO events VALUES (1)');
            await expectLater(
              query
                  ? tx.query('SELECT ?', parameters: [true])
                  : tx.execute('INSERT INTO events VALUES (?)', parameters: [true]),
              throwsArgumentError,
            );
          }),
          throwsArgumentError,
        );

        expect((await database.query('SELECT * FROM events')).rows, isEmpty);
      });
    }

    test('should isolate root work and return only after commit', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute('CREATE TABLE events (value TEXT)');
      final entered = Completer<void>();
      final release = Completer<void>();

      final transaction = database.transaction((tx) async {
        await tx.execute('INSERT INTO events VALUES (?)', parameters: const ['transaction']);
        final visible = await tx.query('SELECT value FROM events');
        expect(visible.rows.single.getString('value'), 'transaction');
        entered.complete();
        await release.future;
        return 42;
      });
      await entered.future;
      var rootCompleted = false;
      final root = database
          .execute('INSERT INTO events VALUES (?)', parameters: const ['root'])
          .whenComplete(() => rootCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(rootCompleted, isFalse);

      release.complete();
      expect(await transaction, 42);
      await root;
      final rows = await database.query('SELECT value FROM events ORDER BY rowid');
      expect(rows.rows.map((row) => row.getString('value')), ['transaction', 'root']);
    });

    test('should reject parent use and expire the transaction handle', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      final other = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      addTearDown(other.close);
      late TursoTransaction expired;

      await database.transaction((tx) async {
        expired = tx;
        await expectLater(database.query('SELECT 1'), throwsStateError);
        await expectLater(database.execute('SELECT 1'), throwsStateError);
        await expectLater(database.transaction((_) async {}), throwsStateError);
        await expectLater(database.close(), throwsStateError);
        expect((await other.query('SELECT 1 AS value')).rows.single.getInt('value'), 1);
      });

      await expectLater(expired.query('SELECT 1'), throwsStateError);
      await expectLater(expired.execute('SELECT 1'), throwsStateError);
      expect((await database.query('SELECT 1 AS value')).rows.single.getInt('value'), 1);
    });

    test('should roll back callback failures with their original stack', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute('CREATE TABLE events (value TEXT)');
      const failure = _TransactionTestFailure();

      Object? caught;
      StackTrace? caughtStack;
      try {
        await database.transaction((tx) async {
          await tx.execute(
            'INSERT INTO events VALUES (?)',
            parameters: const ['rolled back'],
          );
          await _failTransactionCallback(failure);
        });
      } on Object catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, same(failure));
      expect(caughtStack.toString(), contains('_failTransactionCallback'));
      final count = await database.query('SELECT count(*) AS count FROM events');
      expect(count.rows.single.getInt('count'), 0);
    });

    test('should drain submitted work and cancel queued work after failure', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute('CREATE TABLE events (value TEXT)');
      late Future<TursoQueryResult> inFlight;
      late Future<void> queuedExpectation;
      const failure = _TransactionTestFailure();

      await expectLater(
        database.transaction<void>((tx) {
          inFlight = tx.query('SELECT randomblob(1048576) AS payload');
          queuedExpectation = expectLater(
            tx.execute('INSERT INTO events VALUES (?)', parameters: const ['must not escape']),
            throwsStateError,
          );
          return Future<void>.error(failure);
        }),
        throwsA(same(failure)),
      );
      expect((await inFlight).rows.single.getBlob('payload'), hasLength(1048576));
      await queuedExpectation;
      final count = await database.query('SELECT count(*) AS count FROM events');
      expect(count.rows.single.getInt('count'), 0);
    });

    test('should drain unawaited work before committing', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute('CREATE TABLE events (value TEXT)');
      late Future<TursoExecuteResult> submitted;

      await database.transaction((tx) async {
        submitted = tx.execute('INSERT INTO events VALUES (?)', parameters: const ['drained']);
      });

      expect((await submitted).rowsAffected, BigInt.one);
      final count = await database.query('SELECT count(*) AS count FROM events');
      expect(count.rows.single.getInt('count'), 1);
    });

    test('should roll back when an unawaited operation fails', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute('CREATE TABLE events (value TEXT)');

      for (final invalidParameters in [false, true]) {
        await expectLater(
          database.transaction((tx) async {
            await tx.execute("INSERT INTO events VALUES ('must roll back')");
            unawaited(
              invalidParameters
                  ? tx.execute('INSERT INTO events VALUES (?)', parameters: [true])
                  : tx.execute('INSERT INTO missing_table VALUES (1)'),
            );
          }),
          invalidParameters ? throwsArgumentError : throwsA(isA<TursoException>()),
        );

        final count = await database.query('SELECT count(*) AS count FROM events');
        expect(count.rows.single.getInt('count'), 0);
      }
    });
  });
}

final class _TransactionTestFailure implements Exception {
  const _TransactionTestFailure();
}

Future<Never> _failTransactionCallback(Exception failure) async {
  throw failure;
}

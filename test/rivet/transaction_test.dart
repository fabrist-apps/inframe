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
        firstClose.then((_) => closed = true);
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
  });
}

import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet connection configuration', () {
    test('should apply secure defaults and explicit SSL precedence', () {
      expect(RivetConnection.url('postgresql://localhost/db').sslMode, RivetSslMode.verifyFull);
      expect(
        RivetConnection.url('postgresql://localhost/db?sslmode=require').sslMode,
        RivetSslMode.require,
      );
      expect(
        RivetConnection.url(
          'postgresql://localhost/db?sslmode=require',
          sslMode: RivetSslMode.disable,
        ).sslMode,
        RivetSslMode.disable,
      );
      expect(
        () => RivetConnection.url('postgresql://localhost/db?sslmode=prefer'),
        throwsArgumentError,
      );
      expect(
        () => RivetConnection.url(
          'postgresql://localhost/db?sslmode=prefer',
          sslMode: RivetSslMode.disable,
        ),
        throwsArgumentError,
      );
      expect(
        () => RivetConnection.url('postgresql://localhost/db?sslmode=verify-ca'),
        throwsArgumentError,
      );
      expect(
        RivetConnection.url('postgresql://localhost/db').connectTimeout,
        const Duration(seconds: 10),
      );
      expect(const RivetPoolOptions().maxConnections, 10);
      expect(const RivetPoolOptions().acquireTimeout, const Duration(seconds: 30));
    });
  });

  group('Rivet bounded pool', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];

    test('should finish closing when an in-flight connection attempt fails', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      final subscription = server.listen(accepted.complete);
      addTearDown(() async {
        if (accepted.isCompleted) (await accepted.future).destroy();
        await subscription.cancel();
        await server.close();
      });
      final database = await RivetTestDatabase().open(
        connection: RivetConnection.url(
          'postgresql://postgres:password@127.0.0.1:${server.port}/unused',
          connectTimeout: const Duration(milliseconds: 100),
          sslMode: RivetSslMode.disable,
        ),
        pool: const RivetPoolOptions(maxConnections: 1),
      );

      final query = UserProfiles.db.find().get(database);
      await accepted.future;
      final close = database.close();

      await expectLater(query, throwsA(isA<RivetException>()));
      await close.timeout(const Duration(seconds: 1));
    });

    test(
      'should time out pool waiting without timing out acquired SQL',
      () async {
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr116');
        await fixture.execute('''
          CREATE TABLE IF NOT EXISTS fbr116."userProfiles" (
            "displayName" text NOT NULL
          )
        ''');
        await fixture.execute('TRUNCATE fbr116."userProfiles"');
        await fixture.execute("INSERT INTO fbr116.\"userProfiles\" VALUES ('Ada')");
        final database = await RivetTestDatabase().open(
          connection: RivetConnection.url(databaseUrl),
          pool: const RivetPoolOptions(
            maxConnections: 1,
            acquireTimeout: Duration(milliseconds: 100),
          ),
        );
        addTearDown(() async {
          await database.close();
          await fixture.close();
        });

        final locked = Completer<void>();
        final release = Completer<void>();
        final lock = fixture.runTx((session) async {
          await session.execute('LOCK TABLE fbr116."userProfiles" IN ACCESS EXCLUSIVE MODE');
          locked.complete();
          await release.future;
        });
        await locked.future;
        final acquiredQuery = UserProfiles.db.find().get(database);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await expectLater(
          UserProfiles.db.find().get(database),
          throwsA(
            isA<RivetDatabaseException>().having(
              (error) => error.cause,
              'cause',
              isA<TimeoutException>(),
            ),
          ),
        );
        release.complete();
        await lock;
        expect((await acquiredQuery).single.displayName, 'Ada');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should replace a connection closed during a transaction',
      () async {
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr116');
        await fixture.execute('''
          CREATE TABLE IF NOT EXISTS fbr116."userProfiles" (
            "displayName" text NOT NULL
          )
        ''');
        await fixture.execute('TRUNCATE fbr116."userProfiles"');
        await fixture.execute("INSERT INTO fbr116.\"userProfiles\" VALUES ('Ada')");
        await fixture.execute(
          "ALTER ROLE CURRENT_USER SET idle_in_transaction_session_timeout = '100ms'",
        );
        addTearDown(() async {
          await fixture.execute(
            'ALTER ROLE CURRENT_USER RESET idle_in_transaction_session_timeout',
          );
          await fixture.close();
        });
        final database = await RivetTestDatabase().open(
          connection: RivetConnection.url(databaseUrl),
          pool: const RivetPoolOptions(maxConnections: 1),
        );
        addTearDown(database.close);

        await expectLater(
          database.transaction((transaction) async {
            await UserProfiles.db.find().get(transaction);
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await UserProfiles.db.find().get(transaction);
          }),
          throwsA(isA<RivetException>()),
        );

        expect(await UserProfiles.db.find().get(database), isNotEmpty);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

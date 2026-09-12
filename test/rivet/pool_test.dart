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
        RivetConnection.url('postgresql://localhost/db').connectTimeout,
        const Duration(seconds: 10),
      );
      expect(const RivetPoolOptions().maxConnections, 10);
      expect(const RivetPoolOptions().acquireTimeout, const Duration(seconds: 30));
    });
  });

  group('Rivet bounded pool', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];

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
  });
}

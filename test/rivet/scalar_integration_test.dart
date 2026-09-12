import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet scalar integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr119');
      await fixture.execute('DROP TABLE IF EXISTS fbr119."scalarValues"');
      await fixture.execute('''
        CREATE TABLE fbr119."scalarValues" (
          id text NOT NULL,
          count integer NOT NULL,
          score double precision NOT NULL,
          active boolean NOT NULL,
          "createdAt" timestamptz(3) NOT NULL,
          payload jsonb NOT NULL,
          code text NOT NULL,
          "optionalCode" text
        )
      ''');
      await fixture.execute(
        pg.Sql.named('''
          INSERT INTO fbr119."scalarValues"
            (id, count, score, active, "createdAt", payload, code, "optionalCode")
          VALUES (@id:text, @count:int4, @score:float8, @active:boolean,
                  @created:timestamptz, @payload:jsonb, @code:text, NULL)
        '''),
        parameters: {
          'id': 'usr_000000000000000000000000',
          'count': 2147483647,
          'score': 1.5,
          'active': true,
          'created': DateTime.utc(1969, 12, 31, 23, 59, 59, 999),
          'payload': {'ok': true, 'value': null},
          'code': 'A',
        },
      );
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should round-trip every scalar and mapped value',
      () async {
        final row = await ScalarValues.db.find().getSingle(database);

        expect(row.id, 'usr_000000000000000000000000');
        expect(row.count, 2147483647);
        expect(row.score, 1.5);
        expect(row.active, isTrue);
        expect(row.createdAt, DateTime.utc(1969, 12, 31, 23, 59, 59, 999));
        expect(row.payload, JsonValue.from({'ok': true, 'value': null}));
        expect(row.code.value, 'A');
        expect(row.optionalCode, isNull);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

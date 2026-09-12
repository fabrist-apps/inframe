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
          preferences jsonb NOT NULL,
          code text NOT NULL,
          "optionalCode" text
        )
      ''');
      await fixture.execute(
        pg.Sql.named('''
          INSERT INTO fbr119."scalarValues"
            (id, count, score, active, "createdAt", payload, preferences, code, "optionalCode")
          VALUES (@id:text, @count:int4, @score:float8, @active:boolean,
                  @created:timestamptz, @payload:jsonb, @preferences:jsonb, @code:text, NULL)
        '''),
        parameters: {
          'id': 'usr_000000000000000000000000',
          'count': 2147483647,
          'score': 1.5,
          'active': true,
          'created': DateTime.utc(1969, 12, 31, 23, 59, 59, 999),
          'payload': {'ok': true, 'value': null},
          'preferences': {'darkMode': true},
          'code': 'A',
        },
      );
      await fixture.execute('''
        INSERT INTO fbr119."scalarValues"
          (id, count, score, active, "createdAt", payload, preferences, code, "optionalCode")
        VALUES (
          'usr_111111111111111111111111', 0, 0, false,
          '1970-01-01 00:00:00+00', 'null'::jsonb, '{"darkMode":false}'::jsonb, 'B', NULL
        )
      ''');
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
        final row = await ScalarValues.db
            .find(where: (values) => values.code.equals(const UserCode('A')))
            .getSingle(database);
        final jsonNull = await ScalarValues.db
            .find(where: (values) => values.payload.equals(const JsonNull()))
            .getSingle(database);
        final mappedJson = await ScalarValues.db
            .find(where: (values) => values.preferences.equals(const Preferences(darkMode: true)))
            .getSingle(database);

        expect(row.id, 'usr_000000000000000000000000');
        expect(row.count, 2147483647);
        expect(row.score, 1.5);
        expect(row.active, isTrue);
        expect(row.createdAt, DateTime.utc(1969, 12, 31, 23, 59, 59, 999));
        expect(row.payload, JsonValue.from(const {'ok': true, 'value': null}));
        expect(row.preferences.darkMode, isTrue);
        expect(row.code.value, 'A');
        expect(row.optionalCode, isNull);
        expect(jsonNull.payload, const JsonNull());
        expect(mappedJson.code.value, 'A');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

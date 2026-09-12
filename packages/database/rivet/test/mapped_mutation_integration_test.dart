import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet mapped mutations', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('CREATE EXTENSION IF NOT EXISTS vector');
      await fixture.execute('DROP SCHEMA IF EXISTS fbr139 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr139');
      await fixture.execute(
        'CREATE TYPE fbr139."mutationStatus" AS ENUM (\'waiting\', \'finished\')',
      );
      await fixture.execute('''
        CREATE TABLE fbr139."mutationCatalog" (
          id integer PRIMARY KEY,
          "textValue" text NOT NULL,
          count integer NOT NULL,
          score double precision NOT NULL,
          active boolean NOT NULL,
          "createdAt" timestamptz(3) NOT NULL,
          payload jsonb NOT NULL,
          "nullablePayload" jsonb,
          preferences jsonb NOT NULL,
          code text NOT NULL,
          "optionalCode" text,
          status fbr139."mutationStatus" NOT NULL,
          statuses fbr139."mutationStatus"[] NOT NULL,
          timestamps timestamptz(3)[] NOT NULL,
          "nullableInts" integer[] NOT NULL,
          "optionalInts" integer[],
          "jsonValues" jsonb[] NOT NULL,
          "mappedCodes" text[] NOT NULL,
          embedding vector(3) NOT NULL,
          embeddings vector(3)[] NOT NULL
        )
      ''');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
        pool: const RivetPoolOptions(maxConnections: 2),
      );
      mappedCodeDefaultCalls = 0;
      mutationCodeEncodeCalls = 0;
      enumDefaultCalls = 0;
      timestampDefaultCalls = 0;
      mappedArrayDefaultCalls = 0;
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should round-trip catalog values identically through returning and reads',
      () async {
        final beforeEpoch = DateTime.utc(1969, 12, 31, 23, 59, 59, 998, 999);
        final returned = await MutationCatalog.db
            .insert(
              _catalog(
                id: 1,
                nullablePayload: const RivetValue.present(null),
                timestamps: [beforeEpoch],
                nullableInts: const [1, null, 3],
                optionalInts: const RivetValue.present([]),
                jsonValues: [
                  null,
                  const JsonNull(),
                  JsonValue.from(const {'ok': true}),
                ],
              ),
            )
            .returning()
            .get(database);
        final read = await MutationCatalog.db
            .find(where: (values) => values.id.equals(1))
            .getSingle(database);
        final storedEnumLabels = await fixture.execute(
          'SELECT status::text, statuses::text[] '
          'FROM fbr139."mutationCatalog" WHERE id = 1',
        );

        for (final row in [returned.single, read]) {
          expect(row.id, 1);
          expect(row.textValue, 'row-1');
          expect(row.count, 1);
          expect(row.score, 1.5);
          expect(row.active, isTrue);
          expect(row.createdAt, DateTime.utc(1969, 12, 31, 23, 59, 59, 999));
          expect(row.payload, const JsonNull());
          expect(row.nullablePayload, isNull);
          expect(row.preferences.darkMode, isTrue);
          expect(row.code.value, 'default');
          expect(row.optionalCode, isNull);
          expect(row.status, MutationStatus.complete);
          expect(row.statuses, [MutationStatus.queued, MutationStatus.complete]);
          expect(row.timestamps, [DateTime.utc(1969, 12, 31, 23, 59, 59, 998)]);
          expect(row.nullableInts, [1, null, 3]);
          expect(row.optionalInts, isEmpty);
          expect(row.jsonValues, [
            null,
            const JsonNull(),
            JsonValue.from(const {'ok': true}),
          ]);
          expect(row.mappedCodes.map((code) => code?.value), [
            'array-default',
            null,
          ]);
          expect(row.embedding, Float32List.fromList([1, 2, 3]));
          expect(row.embeddings, [
            Float32List.fromList([4, 5, 6]),
          ]);
        }
        expect(mappedCodeDefaultCalls, 1);
        expect(mutationCodeEncodeCalls, 2);
        expect(enumDefaultCalls, 1);
        expect(timestampDefaultCalls, 1);
        expect(mappedArrayDefaultCalls, 1);
        expect(storedEnumLabels.single[0], 'finished');
        expect(storedEnumLabels.single[1], ['waiting', 'finished']);
        expect(statements, hasLength(2));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should write storage expressions without invoking mapped converters',
      () async {
        final explicitTimestamp = DateTime.parse(
          '1969-12-31T18:29:59.997999-05:30',
        );
        final returned = await MutationCatalog.db
            .insert(
              _catalog(
                id: 2,
                preferences: RivetValue.expression(
                  (values) => values.preferences.storage.value(
                    JsonValue.from(const {'darkMode': false}),
                  ),
                ),
                code: RivetValue.expression(
                  (values) => values.code.storage.value('code:expression'),
                ),
                mappedCodes: RivetValue.expression(
                  (values) => values.mappedCodes.storage.value([
                    'code:first',
                    null,
                  ]),
                ),
                createdAt: RivetValue.present(explicitTimestamp),
              ),
            )
            .returning()
            .get(database);

        expect(returned.single.preferences.darkMode, isFalse);
        expect(returned.single.code.value, 'expression');
        expect(returned.single.mappedCodes.map((code) => code?.value), [
          'first',
          null,
        ]);
        expect(
          returned.single.createdAt,
          DateTime.utc(1969, 12, 31, 23, 59, 59, 997),
        );
        expect(mappedCodeDefaultCalls, 0);
        expect(mappedArrayDefaultCalls, 0);
        expect(mutationCodeEncodeCalls, 0);
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should report contextual decode failures for invalid storage expressions',
      () async {
        final decodeFailure = throwsA(
          isA<RivetConversionException>()
              .having((error) => error.table, 'table', 'fbr139.mutationCatalog')
              .having((error) => error.column, 'column', 'code')
              .having((error) => error.message, 'message', isNot(contains('invalid'))),
        );
        await expectLater(
          MutationCatalog.db
              .insert(
                _catalog(
                  id: 3,
                  code: RivetValue.expression(
                    (values) => values.code.storage.value('invalid'),
                  ),
                ),
              )
              .returning()
              .get(database),
          decodeFailure,
        );
        await expectLater(
          MutationCatalog.db.find(where: (values) => values.id.equals(3)).getSingle(database),
          decodeFailure,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should surface PostgreSQL integer overflow from a SQL expression',
      () async {
        await expectLater(
          MutationCatalog.db
              .insert(
                _catalog(
                  id: 4,
                  count: RivetValue.expression(
                    (values) => values.count.value(2147483647) + 1,
                  ),
                ),
              )
              .execute(database),
          throwsA(isA<RivetDatabaseException>()),
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

MutationCatalogCompanion _catalog({
  required int id,
  JsonValue payload = const JsonNull(),
  RivetValue<MutationCatalog, JsonValue?, JsonValue?> nullablePayload = const RivetValue.absent(),
  List<DateTime> timestamps = const [],
  List<int?> nullableInts = const [],
  RivetValue<MutationCatalog, List<int>?, List<int>?> optionalInts = const RivetValue.absent(),
  List<JsonValue?> jsonValues = const [],
  RivetValue<MutationCatalog, int, int>? count,
  RivetValue<MutationCatalog, DateTime, DateTime>? createdAt,
  RivetValue<MutationCatalog, Preferences, JsonValue>? preferences,
  RivetValue<MutationCatalog, MutationCode, String>? code,
  RivetValue<MutationCatalog, List<MutationCode?>, List<String?>>? mappedCodes,
}) => MutationCatalogCompanion.insert(
  id: RivetValue.present(id),
  textValue: RivetValue.present('row-$id'),
  count: count ?? RivetValue.present(id),
  score: const RivetValue.present(1.5),
  active: const RivetValue.present(true),
  createdAt: createdAt ?? const RivetValue.absent(),
  payload: RivetValue.present(payload),
  nullablePayload: nullablePayload,
  preferences: preferences ?? const RivetValue.present(Preferences(darkMode: true)),
  code: code ?? const RivetValue.absent(),
  timestamps: RivetValue.present(timestamps),
  nullableInts: RivetValue.present(nullableInts),
  optionalInts: optionalInts,
  jsonValues: RivetValue.present(jsonValues),
  mappedCodes: mappedCodes ?? const RivetValue.absent(),
  embedding: RivetValue.present(Float32List.fromList([1, 2, 3])),
  embeddings: RivetValue.present([
    Float32List.fromList([4, 5, 6]),
  ]),
);

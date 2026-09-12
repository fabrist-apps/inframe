import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet nested codec transport', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;
    late List<String> statements;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr148 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr148');
      await fixture.execute('CREATE EXTENSION IF NOT EXISTS vector');
      await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr120');
      await fixture.execute(r'''
        DO $$ BEGIN
          CREATE TYPE fbr120."workStatus" AS ENUM ('zeta', 'alpha');
        EXCEPTION WHEN duplicate_object THEN NULL;
        END $$
      ''');
      await fixture.execute('CREATE TABLE fbr148."codecParents" (id integer NOT NULL)');
      await fixture.execute('''
        CREATE TABLE fbr148."codecValues" (
          id integer NOT NULL,
          "ownerId" integer NOT NULL,
          payload jsonb NOT NULL,
          "happenedAt" timestamptz NOT NULL,
          status fbr120."workStatus" NOT NULL,
          score double precision,
          embedding vector(3) NOT NULL,
          ints integer[] NOT NULL,
          "optionalInts" integer[],
          "nullableInts" integer[] NOT NULL,
          "jsonValues" jsonb[] NOT NULL,
          vectors vector(3)[] NOT NULL,
          statuses fbr120."workStatus"[] NOT NULL,
          codes text[] NOT NULL
        )
      ''');
      await fixture.execute('''
        CREATE TABLE fbr148."codecLinks" ("ownerId" integer NOT NULL, "valueId" integer NOT NULL)
      ''');
      await fixture.execute('INSERT INTO fbr148."codecParents" VALUES (1), (2)');
      await fixture.execute('''
        INSERT INTO fbr148."codecValues" VALUES (
          10,
          1,
          'null'::jsonb,
          '1969-12-31 23:59:59.123+00',
          'zeta',
          7.5,
          '[1,2,3]'::vector,
          ARRAY[]::integer[],
          NULL,
          ARRAY[1, NULL, 3]::integer[],
          ARRAY[NULL::jsonb, 'null'::jsonb, '[1,null]'::jsonb],
          ARRAY['[1,2,3]'::vector, '[4,5,6]'::vector],
          ARRAY['zeta', 'alpha']::fbr120."workStatus"[],
          ARRAY['A', NULL]::text[]
        )
      ''');
      await fixture.execute('INSERT INTO fbr148."codecLinks" VALUES (1, 10)');
      statements = [];
      database = await RivetTestDatabase().open(
        connection: RivetConnection.url(databaseUrl, onStatement: statements.add),
      );
    });

    tearDown(() async {
      if (databaseUrl == null) return;
      await database.close();
      await fixture.close();
    });

    test(
      'should preserve catalog values through one, many, and through envelopes',
      () async {
        final direct = await CodecValues.db.find().getSingle(database);
        final scoredParent = await CodecParents.db
            .find(
              where: (parent) => parent.id.equals(1),
              include: (include) => [
                include.values(include: (include) => [include.owner()]),
                include.linkedValues(),
              ],
            )
            .withScore(
              (parent) => parent.linkedValues.max((value) => value.score),
            )
            .getSingle(database);
        final parent = scoredParent.row;
        expect(scoredParent.score, 7.5);
        final nested = (parent.values as LoadedRelation<List<CodecRecord>>).value.single;
        final through = (parent.linkedValues as LoadedRelation<List<CodecRecord>>).value.single;

        for (final row in [direct, nested, through]) {
          expect(row, isA<CodecRecord>());
          expect(row.payload, const JsonNull());
          expect(row.happenedAt, DateTime.utc(1969, 12, 31, 23, 59, 59, 123));
          expect(row.status, WorkStatus.queued);
          expect(row.embedding, Float32List.fromList([1, 2, 3]));
          expect(row.ints, isEmpty);
          expect(row.optionalInts, isNull);
          expect(row.nullableInts, [1, null, 3]);
          expect(row.jsonValues, [
            null,
            const JsonNull(),
            JsonValue.from(const [1, null]),
          ]);
          expect(row.vectors, [
            Float32List.fromList([1, 2, 3]),
            Float32List.fromList([4, 5, 6]),
          ]);
          expect(row.statuses, [WorkStatus.queued, WorkStatus.complete]);
          expect(row.codes.map((code) => code?.value), ['A', null]);
        }
        expect((nested.owner as LoadedRelation<CodecParentsRow?>).value?.id, 1);
        expect(through.owner.isLoaded, isFalse);

        final returned = await CodecValues.db
            .insert(
              CodecValuesCompanion.insert(
                id: const RivetValue.present(11),
                ownerId: const RivetValue.present(2),
                payload: const RivetValue.present(JsonNull()),
                happenedAt: RivetValue.present(
                  DateTime.utc(1969, 12, 31, 23, 59, 59, 123),
                ),
                status: const RivetValue.present(WorkStatus.queued),
                score: const RivetValue.present(null),
                embedding: RivetValue.present(Float32List.fromList([1, 2, 3])),
                ints: const RivetValue.present([]),
                optionalInts: const RivetValue.present(null),
                nullableInts: const RivetValue.present([1, null, 3]),
                jsonValues: RivetValue.present([
                  null,
                  const JsonNull(),
                  JsonValue.from(const [1, null]),
                ]),
                vectors: RivetValue.present([
                  Float32List.fromList([1, 2, 3]),
                  Float32List.fromList([4, 5, 6]),
                ]),
                statuses: const RivetValue.present([
                  WorkStatus.queued,
                  WorkStatus.complete,
                ]),
                codes: const RivetValue.present([UserCode('A'), null]),
              ),
            )
            .returning()
            .get(database);
        expect(returned.single, isA<CodecRecord>());
        expect(returned.single.jsonValues, direct.jsonValues);
        expect(returned.single.nullableInts, direct.nullableInts);
        expect(returned.single.owner.isLoaded, isFalse);

        final scoredRecord = await CodecValues.db
            .find(
              where: (value) => value.id.equals(10),
              include: (include) => [include.owner()],
            )
            .withScore((value) => value.score)
            .getSingle(database);
        expect(scoredRecord.row, isA<CodecRecord>());
        expect(scoredRecord.score, 7.5);
        expect(scoredRecord.row.owner.isLoaded, isTrue);

        final enumAggregate = await CodecParents.db
            .find(
              where: (parent) => parent.values
                  .min(
                    (value) => value.status,
                    where: (value) => value.id.equals(10),
                  )
                  .equals(WorkStatus.queued),
              orderBy: (parent) => [
                parent.values.max((value) => value.status).asc(),
              ],
            )
            .getSingle(database);
        expect(enumAggregate.id, 1);
        expect(statements, hasLength(5));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject malformed nested arrays without follow-up SQL',
      () async {
        await fixture.execute('''
          UPDATE fbr148."codecValues" SET ints = '[0:1]={1,2}' WHERE id = 10
        ''');

        await expectLater(
          CodecParents.db.find(include: (include) => [include.values()]).get(database),
          throwsA(isA<RivetConversionException>()),
        );
        expect(statements, hasLength(1));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

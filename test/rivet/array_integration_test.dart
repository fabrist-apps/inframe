import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet native arrays', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;

    test('should reject null non-nullable elements and multidimensional values', () {
      final table = ArrayValues.db.buildSchema().definition;
      final dynamic encodeInts = table.ints.codec.encode;
      expect(
        // Deliberately bypass static typing to verify the runtime guard.
        // ignore: avoid_dynamic_calls
        () => encodeInts(<dynamic>[1, null]),
        throwsA(anything),
      );
      expect(
        () => (table.ints.codec as dynamic).encode(<dynamic>[
          [1],
        ]),
        throwsA(anything),
      );
      expect(
        () => table.nullableInts.codec.encode([2147483648]),
        throwsRangeError,
      );
    });

    test(
      'should preserve array shape, nulls, JSON null, converters, enums, and vectors',
      () async {
        fixture = await pg.Connection.openFromUrl(databaseUrl!);
        await fixture.execute('DROP SCHEMA IF EXISTS fbr122 CASCADE');
        await fixture.execute('CREATE SCHEMA fbr122');
        await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr120');
        await fixture.execute(r'''
          DO $$ BEGIN
            CREATE TYPE fbr120."workStatus" AS ENUM ('zeta', 'alpha');
          EXCEPTION WHEN duplicate_object THEN NULL;
          END $$
        ''');
        await fixture.execute('''
          CREATE TABLE fbr122."arrayValues" (
            ints integer[] NOT NULL,
            "nullableInts" integer[] NOT NULL,
            "optionalInts" integer[],
            "optionalNullableInts" integer[],
            "jsonValues" jsonb[] NOT NULL,
            vectors vector(3)[] NOT NULL,
            statuses fbr120."workStatus"[] NOT NULL,
            codes text[] NOT NULL
          )
        ''');
        await fixture.execute('''
          CREATE TABLE fbr122."malformedArrays" (
            ints integer[] NOT NULL
          )
        ''');
        await fixture.execute('''
          INSERT INTO fbr122."arrayValues" VALUES (
            ARRAY[]::integer[],
            ARRAY[1, NULL, 3]::integer[],
            NULL,
            ARRAY[NULL, 4]::integer[],
            ARRAY[NULL::jsonb, 'null'::jsonb, '{"ok":true}'::jsonb],
            ARRAY['[1,2,3]'::vector, '[4,5,6]'::vector],
            ARRAY['zeta', 'alpha']::fbr120."workStatus"[],
            ARRAY['A', NULL]::text[]
          )
        ''');
        database = await RivetTestDatabase().open(
          connection: RivetConnection.url(databaseUrl),
          pool: const RivetPoolOptions(maxConnections: 2),
        );
        addTearDown(() async {
          await database.close();
          await fixture.close();
        });

        final row = await ArrayValues.db.find().getSingle(database);
        final filtered = await ArrayValues.db
            .find(
              where: (values) => values.statuses.equals([
                WorkStatus.queued,
                WorkStatus.complete,
              ]),
            )
            .getSingle(database);
        final jsonFiltered = await ArrayValues.db
            .find(
              where: (values) => values.jsonValues.equals([
                null,
                const JsonNull(),
                JsonValue.from(const {'ok': true}),
              ]),
            )
            .getSingle(database);
        final vectorFiltered = await ArrayValues.db
            .find(
              where: (values) => values.vectors.equals([
                Float32List.fromList([1, 2, 3]),
                Float32List.fromList([4, 5, 6]),
              ]),
            )
            .getSingle(database);
        expect(row.ints, isEmpty);
        expect(row.nullableInts, [1, null, 3]);
        expect(row.optionalInts, isNull);
        expect(row.optionalNullableInts, [null, 4]);
        expect(row.jsonValues[0], isNull);
        expect(row.jsonValues[1], const JsonNull());
        expect(row.jsonValues[2], JsonValue.from(const {'ok': true}));
        expect(row.vectors, [
          Float32List.fromList([1, 2, 3]),
          Float32List.fromList([4, 5, 6]),
        ]);
        expect(row.statuses, [WorkStatus.queued, WorkStatus.complete]);
        expect(row.codes.map((value) => value?.value), ['A', null]);
        expect(filtered.statuses, [WorkStatus.queued, WorkStatus.complete]);
        expect(jsonFiltered.jsonValues, [
          null,
          const JsonNull(),
          JsonValue.from(const {'ok': true}),
        ]);
        expect(vectorFiltered.vectors, hasLength(2));

        await fixture.execute("INSERT INTO fbr122.\"malformedArrays\" VALUES ('[0:1]={1,2}')");
        await expectLater(
          MalformedArrays.db.find().get(database),
          throwsA(isA<RivetDatabaseException>()),
        );
        await fixture.execute('TRUNCATE fbr122."malformedArrays"');
        await fixture.execute('''
          INSERT INTO fbr122."malformedArrays" VALUES (ARRAY[[1, 2], [3, 4]])
        ''');
        await expectLater(
          MalformedArrays.db.find().get(database),
          throwsA(isA<RivetDatabaseException>()),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

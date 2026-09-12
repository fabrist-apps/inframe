import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';

void main() {
  group('Rivet native enum integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late pg.Connection fixture;
    late RivetDb database;

    setUp(() async {
      if (databaseUrl == null) return;
      fixture = await pg.Connection.openFromUrl(databaseUrl);
      await fixture.execute('DROP SCHEMA IF EXISTS fbr120 CASCADE');
      await fixture.execute('CREATE SCHEMA fbr120');
      await fixture.execute("CREATE TYPE fbr120.\"workStatus\" AS ENUM ('zeta', 'alpha')");
      await fixture.execute('''
        CREATE TABLE fbr120."enumValues" (
          status fbr120."workStatus" NOT NULL,
          "optionalStatus" fbr120."workStatus",
          "nullableStatuses" fbr120."workStatus"[] NOT NULL,
          "optionalStatuses" fbr120."workStatus"[],
          "optionalNullableStatuses" fbr120."workStatus"[],
          "mappedStatus" fbr120."workStatus" NOT NULL
        )
      ''');
      await fixture.execute('''
        INSERT INTO fbr120."enumValues" VALUES
          ('alpha', NULL, ARRAY['zeta', NULL]::fbr120."workStatus"[], NULL, NULL, 'zeta'),
          ('zeta', 'alpha', ARRAY['alpha']::fbr120."workStatus"[],
           ARRAY['zeta']::fbr120."workStatus"[],
           ARRAY[NULL, 'alpha']::fbr120."workStatus"[], 'alpha')
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
      'should decode labels and sort in PostgreSQL declaration order',
      () async {
        final ascending = await EnumValues.db
            .find(orderBy: (values) => [values.status.asc()])
            .get(database);
        final descending = await EnumValues.db
            .find(orderBy: (values) => [values.status.desc()])
            .get(database);
        final filtered = await EnumValues.db
            .find(where: (values) => values.status.equals(WorkStatus.complete))
            .getSingle(database);

        expect(ascending.map((row) => row.status), [WorkStatus.queued, WorkStatus.complete]);
        expect(descending.map((row) => row.status), [WorkStatus.complete, WorkStatus.queued]);
        expect(filtered.status, WorkStatus.complete);
        expect(ascending.first.optionalStatus, WorkStatus.complete);
        expect(ascending.first.nullableStatuses, [WorkStatus.complete]);
        expect(ascending.first.optionalStatuses, [WorkStatus.queued]);
        expect(ascending.first.optionalNullableStatuses, [null, WorkStatus.complete]);
        expect(ascending.first.mappedStatus.value, WorkStatus.complete);
        expect(ascending.last.optionalStatus, isNull);
        expect(ascending.last.nullableStatuses, [WorkStatus.queued, null]);
        expect(ascending.last.optionalStatuses, isNull);
        expect(ascending.last.optionalNullableStatuses, isNull);
        expect(ascending.last.mappedStatus.value, WorkStatus.queued);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

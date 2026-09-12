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
      await fixture.execute('CREATE SCHEMA IF NOT EXISTS fbr120');
      await fixture.execute('DROP TABLE IF EXISTS fbr120."enumValues"');
      await fixture.execute('DROP TYPE IF EXISTS fbr120."workStatus"');
      await fixture.execute("CREATE TYPE fbr120.\"workStatus\" AS ENUM ('zeta', 'alpha')");
      await fixture.execute('''
        CREATE TABLE fbr120."enumValues" (
          status fbr120."workStatus" NOT NULL
        )
      ''');
      await fixture.execute("INSERT INTO fbr120.\"enumValues\" VALUES ('alpha'), ('zeta')");
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

        expect(ascending.map((row) => row.status), [WorkStatus.queued, WorkStatus.complete]);
        expect(descending.map((row) => row.status), [WorkStatus.complete, WorkStatus.queued]);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

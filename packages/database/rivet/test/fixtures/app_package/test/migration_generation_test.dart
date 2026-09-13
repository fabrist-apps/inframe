import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:rivet_fixture_schema/package_users.dart' as schema;
import 'package:rivet_generator/rivet_generator.dart';
import 'package:test/test.dart';

void main() {
  group('Rivet package migration composition', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late Directory directory;
    late pg.Connection connection;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('rivet_package_migration_');
      if (databaseUrl == null) return;
      connection = await pg.Connection.openFromUrl(databaseUrl);
      await connection.execute('DROP SCHEMA IF EXISTS fixture CASCADE');
    });

    tearDown(() async {
      if (databaseUrl != null) await connection.close();
      directory.deleteSync(recursive: true);
    });

    test(
      'should apply an independently generated package table',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: RivetDatabaseSchema(
            name: 'package_composition',
            tables: [schema.PackageLabels.db.buildSchema()],
          ),
          directory: directory,
          name: 'initial',
        );
        final journal = jsonDecode(
          File('${directory.path}/journal.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
        final migrationDirectory = '${directory.path}/${entry['directory']}';
        final sqlBytes = File('$migrationDirectory/migration.sql').readAsBytesSync();
        final migration = jsonDecode(
          File('$migrationDirectory/migration.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final phase = (migration['phases']! as List<Object?>).single! as Map<String, Object?>;

        for (final value in phase['statements']! as List<Object?>) {
          final statement = value! as Map<String, Object?>;
          await connection.execute(
            utf8.decode(
              sqlBytes.sublist(
                statement['startByte']! as int,
                statement['endByte']! as int,
              ),
            ),
          );
        }
        await connection.execute('''
          INSERT INTO "fixture"."packageLabels" ("code", "name", "aliases")
          VALUES ('one', 'One', ARRAY['{"value":1}'::jsonb, NULL])
        ''');
        final rows = await connection.execute(
          'SELECT "name" FROM "fixture"."packageLabels" WHERE "code" = \'one\'',
        );

        expect(rows.single.single, 'One');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet_generator/rivet_generator.dart';
import 'package:test/test.dart';

import 'migration_fixture.dart';

void main() {
  group('RivetMigrationGenerator integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late Directory directory;
    late pg.Connection connection;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('rivet_migration_integration_');
      if (databaseUrl == null) return;
      connection = await pg.Connection.openFromUrl(databaseUrl);
      await connection.execute('DROP SCHEMA IF EXISTS auth CASCADE');
    });

    tearDown(() async {
      if (databaseUrl != null) await connection.close();
      directory.deleteSync(recursive: true);
    });

    test(
      'should apply generated ordinary SQL without the migration runner',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        final journal = jsonDecode(
          File('${directory.path}/journal.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
        final sql = File(
          '${directory.path}/${entry['directory']}/migration.sql',
        ).readAsStringSync();
        final migration = jsonDecode(
          File(
            '${directory.path}/${entry['directory']}/migration.json',
          ).readAsStringSync(),
        ) as Map<String, Object?>;

        final sqlBytes = utf8.encode(sql);
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
        await connection.execute(
          'INSERT INTO "auth"."users" ("id", "name") VALUES (1, \'Bhaswanth\')',
        );
        final rows = await connection.execute(
          'SELECT "name" FROM "auth"."users" WHERE "id" = 1',
        );

        expect(rows.single.single, 'Bhaswanth');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve data through declared table and column renames',
      () async {
        const generator = RivetMigrationGenerator();
        await generator.generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        await _applyLastMigration(connection, directory);
        await connection.execute(
          'INSERT INTO "auth"."users" ("id", "name") VALUES (1, \'Bhaswanth\')',
        );

        await generator.generate(
          schema: MigratedFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'rename users',
        );
        await _applyLastMigration(connection, directory);
        final rows = await connection.execute(
          'SELECT "fullName", "active" FROM "auth"."members" WHERE "id" = 1',
        );

        expect(rows.single, ['Bhaswanth', true]);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

Future<void> _applyLastMigration(pg.Connection connection, Directory directory) async {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  final migrationDirectory = '${directory.path}/${entry['directory']}';
  final sqlBytes = File('$migrationDirectory/migration.sql').readAsBytesSync();
  final migration = jsonDecode(
    File('$migrationDirectory/migration.json').readAsStringSync(),
  ) as Map<String, Object?>;
  for (final rawPhase in migration['phases']! as List<Object?>) {
    final phase = rawPhase! as Map<String, Object?>;
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
  }
}

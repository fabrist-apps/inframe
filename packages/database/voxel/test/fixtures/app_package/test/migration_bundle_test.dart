import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/fixture_app.voxel_migrations.dart';

void main() {
  group('FixtureAppDatabase', () {
    test('should reject a malformed bundle before opening', () async {
      const source = FixtureAppDatabaseVoxelMigrations.bundle;
      final first = source.migrations.first;
      final malformed = VoxelMigrationBundle(
        databaseId: source.databaseId,
        migrations: [
          VoxelBundledMigration(
            directory: first.directory,
            sql: first.sql,
            metadata: {...first.metadata, 'parentId': 'ffffffffffffffffffffffffffffffff'},
            snapshot: first.snapshot,
          ),
          ...source.migrations.skip(1),
        ],
      );

      await expectLater(
        VoxelDatabaseRuntime.open(
          schema: FixtureAppDatabaseVoxelSchema.build(),
          bundle: malformed,
          storage: const VoxelStorage.memory(),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should open independent migrated memory databases', () async {
      final first = await FixtureAppDatabase().open(storage: const VoxelStorage.memory());
      final second = await FixtureAppDatabase().open(storage: const VoxelStorage.memory());
      addTearDown(first.close);
      addTearDown(second.close);

      await VoxelTesting.execute(first, "INSERT INTO content.authors VALUES ('1', 'Ada')");
      final firstCount = await VoxelTesting.scalarInt(
        first,
        'SELECT COUNT(*) AS value FROM content.authors',
      );
      final secondCount = await VoxelTesting.scalarInt(
        second,
        'SELECT COUNT(*) AS value FROM content.authors',
      );

      expect(firstCount, 1);
      expect(secondCount, 0);
    });

    test('should enforce generated indexes, checks, keys, and foreign keys', () async {
      final database = await FixtureAppDatabase().open(
        storage: const VoxelStorage.memory(),
      );
      addTearDown(database.close);

      await VoxelTesting.execute(
        database,
        "INSERT INTO content.authors VALUES ('author-1', 'Ada')",
      );
      await expectLater(
        VoxelTesting.execute(
          database,
          "INSERT INTO content.authors VALUES ('author-2', 'Ada')",
        ),
        throwsA(isA<VoxelDatabaseException>()),
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          "SELECT COUNT(*) AS value FROM content.authors WHERE name = 'Ada'",
        ),
        1,
      );
      await expectLater(
        VoxelTesting.execute(
          database,
          "INSERT INTO content.authors VALUES ('author-3', '')",
        ),
        throwsA(isA<VoxelDatabaseException>()),
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          "SELECT COUNT(*) AS value FROM content.authors WHERE id = 'author-3'",
        ),
        0,
      );
      await expectLater(
        VoxelTesting.execute(
          database,
          "INSERT INTO content.posts VALUES ('post-1', 'missing', 'draft')",
        ),
        throwsA(isA<VoxelDatabaseException>()),
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          "SELECT COUNT(*) AS value FROM content.posts WHERE id = 'post-1'",
        ),
        0,
      );
      await VoxelTesting.execute(
        database,
        "INSERT INTO content.locales VALUES ('en', 'title')",
      );
      await expectLater(
        VoxelTesting.execute(
          database,
          "INSERT INTO content.locales VALUES ('en', 'title')",
        ),
        throwsA(isA<VoxelDatabaseException>()),
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          "SELECT COUNT(*) AS value FROM content.locales WHERE language = 'en' AND key = 'title'",
        ),
        1,
      );
      await expectLater(
        VoxelTesting.execute(
          database,
          "INSERT INTO content.translations VALUES ('en', 'missing', 'Title')",
        ),
        throwsA(isA<VoxelDatabaseException>()),
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          "SELECT COUNT(*) AS value FROM content.translations WHERE language = 'en' AND key = 'missing'",
        ),
        0,
      );

      expect(
        await VoxelTesting.scalarInt(
          database,
          'SELECT COUNT(*) AS value FROM content.sqlite_master '
          "WHERE type = 'index' AND name = 'authors_name'",
        ),
        1,
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          'SELECT COUNT(*) AS value FROM content._voxel_migrations',
        ),
        3,
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          'SELECT COUNT(*) AS value FROM content._voxel_phases '
          "WHERE status = 'completed'",
        ),
        3,
      );
    });
  });

  test('generated migration bundle should preserve and execute checked history', () async {
    const bundle = FixtureAppDatabaseVoxelMigrations.bundle;
    final sourceDirectory = [
      Directory('${Directory.current.path}/migrations/fixture_app'),
      Directory('${Directory.current.path}/test/fixtures/app_package/migrations/fixture_app'),
      Directory(
        '${Directory.current.path}/packages/database/voxel/test/fixtures/app_package/migrations/fixture_app',
      ),
    ].singleWhere((directory) => directory.existsSync());
    final journal = jsonDecode(
      File('${sourceDirectory.path}/journal.json').readAsStringSync(),
    ) as Map<String, Object?>;
    expect(bundle.migrations, hasLength(3));
    expect(bundle.databaseId, journal['databaseId']);
    for (final (index, migration) in bundle.migrations.indexed) {
      final entry = (journal['entries']! as List<Object?>)[index]! as Map<String, Object?>;
      final path = '${sourceDirectory.path}/${entry['directory']}';
      expect(migration.directory, entry['directory']);
      expect(migration.sql, File('$path/migration.sql').readAsStringSync());
      expect(
        migration.metadata,
        jsonDecode(File('$path/migration.json').readAsStringSync()),
      );
      expect(
        migration.snapshot,
        jsonDecode(File('$path/snapshot.json').readAsStringSync()),
      );
    }
    expect(bundle.migrations.first.parentId, isNull);
    expect(bundle.migrations[1].parentId, bundle.migrations.first.id);
    expect(bundle.migrations[2].parentId, bundle.migrations[1].id);
    expect(bundle.migrations[1].sql, contains('RENAME TO "posts"'));
    expect(bundle.migrations.last.sql, startsWith('-- reviewed bundle fixture\n'));
    final finalPhase =
        (bundle.migrations.last.metadata['phases']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(finalPhase['platforms'], ['native', 'browser']);
    expect(finalPhase['rebuild'], isA<Map<String, Object?>>());

    final database = await TursoDatabase.open(TursoLocation.memory());
    addTearDown(database.close);
    await database.execute("ATTACH DATABASE ':memory:' AS content");
    for (final (index, migration) in bundle.migrations.indexed) {
      await _execute(database, migration);
      if (index == 0) {
        await database.execute("INSERT INTO content.authors VALUES ('author-1', 'Ada')");
        await database.execute(
          "INSERT INTO content.articles VALUES ('post-1', 'author-1', 'published')",
        );
      }
    }
    final row = (await database.query(
      'SELECT authorID, status FROM content.posts',
    )).rows.single;
    expect(row.getString('authorID'), 'author-1');
    expect(row.getString('status'), 'live');
  });
}

Future<void> _execute(TursoDatabase database, VoxelBundledMigration migration) async {
  final bytes = utf8.encode(migration.sql);
  for (final rawPhase in migration.metadata['phases']! as List<Object?>) {
    final phase = rawPhase! as Map<String, Object?>;
    final rebuild = phase['rebuild'] as Map<String, Object?>?;
    if (rebuild != null) await database.execute('PRAGMA foreign_keys=OFF');
    try {
      await database.transaction<void>((transaction) async {
        for (final rawRange in phase['statements']! as List<Object?>) {
          final range = rawRange! as Map<String, Object?>;
          await transaction.execute(
            utf8.decode(
              bytes.sublist(range['startByte']! as int, range['endByte']! as int),
            ),
          );
        }
        if (rebuild != null) {
          for (final rawValidation in rebuild['validations']! as List<Object?>) {
            final validation = rawValidation! as Map<String, Object?>;
            final row = (await transaction.query(validation['sql']! as String)).rows.single;
            if (row.getInt('valid') != 1) {
              throw StateError('Bundled migration validation failed.');
            }
          }
        }
      });
    } finally {
      if (rebuild != null) await database.execute('PRAGMA foreign_keys=ON');
    }
  }
}

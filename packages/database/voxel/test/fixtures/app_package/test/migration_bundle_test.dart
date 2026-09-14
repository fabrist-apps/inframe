import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/fixture_app.voxel_migrations.dart';

void main() {
  test('generated migration bundle should preserve and execute checked history', () async {
    const bundle = FixtureAppDatabaseVoxelMigrations.bundle;
    final localDirectory = Directory('${Directory.current.path}/migrations/fixture_app');
    final sourceDirectory = localDirectory.existsSync()
        ? localDirectory
        : Directory(
            '${Directory.current.path}/test/fixtures/app_package/migrations/fixture_app',
          );
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
    await database.execute('BEGIN');
    try {
      for (final rawRange in phase['statements']! as List<Object?>) {
        final range = rawRange! as Map<String, Object?>;
        await database.execute(
          utf8.decode(
            bytes.sublist(range['startByte']! as int, range['endByte']! as int),
          ),
        );
      }
      if (rebuild != null) {
        for (final rawValidation in rebuild['validations']! as List<Object?>) {
          final validation = rawValidation! as Map<String, Object?>;
          final row = (await database.query(validation['sql']! as String)).rows.single;
          if (row.getInt('valid') != 1) throw StateError('Bundled migration validation failed.');
        }
      }
      await database.execute('COMMIT');
    } on Object {
      await database.execute('ROLLBACK');
      rethrow;
    } finally {
      if (rebuild != null) await database.execute('PRAGMA foreign_keys=ON');
    }
  }
}

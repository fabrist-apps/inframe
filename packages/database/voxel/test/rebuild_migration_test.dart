import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/src/migration.dart';
import 'package:voxel/src/schema.dart';

void main() {
  group('Voxel rebuild migration', () {
    late Directory directory;
    late VoxelMigrationPlan plan;
    late String initialMigrationId;
    late TursoDatabase database;

    setUp(() async {
      directory = _fixtureDirectory();
      database = await TursoDatabase.open(TursoLocation.memory());
      final bundle = _bundle(directory);
      initialMigrationId = bundle.migrations.first.id;
      plan = VoxelMigrationPlan.validate(
        schema: _runtimeSchema(),
        bundle: bundle,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('should roll back an invalid rebuild, then preserve a repaired cycle', () async {
      await _openAtInitial(database, plan, initialMigrationId);
      await database.execute('PRAGMA foreign_keys=OFF');
      await database.execute(
        "INSERT INTO content.children VALUES ('acme', 'c1', 'acme', 'missing')",
      );
      await database.execute('PRAGMA foreign_keys=ON');

      await expectLater(
        plan.applyPersistentScope(
          database,
          scope: 'content',
          fileIdentity: 'rebuild-file',
        ),
        throwsStateError,
      );

      expect(
        (await database.query('PRAGMA content.table_info(parents)')).rows
            .singleWhere((row) => row.getString('name') == 'name')
            .getString('type'),
        'TEXT',
      );
      expect(
        (await database.query(
          'SELECT COUNT(*) AS value FROM content._voxel_phases',
        )).rows.single.getInt('value'),
        1,
      );
      expect(
        (await database.query('PRAGMA foreign_keys')).rows.single.getInt('foreign_keys'),
        1,
      );
      expect(
        (await database.query(
          "SELECT COUNT(*) AS value FROM content.sqlite_schema WHERE name LIKE '__voxel_rebuild_%'",
        )).rows.single.getInt('value'),
        0,
      );

      await database.execute('DELETE FROM content.children');
      await _insertCycle(database);
      await plan.applyPersistentScope(
        database,
        scope: 'content',
        fileIdentity: 'rebuild-file',
      );

      final parent = (await database.query(
        "SELECT name, favoriteChildId FROM content.parents WHERE tenant = 'acme' AND id = 'p1'",
      )).rows.single;
      expect(parent.getInt('name'), 7);
      expect(parent.getString('favoriteChildId'), 'c1');
      expect(
        (await database.query(
          "SELECT COUNT(*) AS value FROM content.sqlite_schema WHERE name = 'parents_name_unique'",
        )).rows.single.getInt('value'),
        1,
      );
      expect(
        (await database.query('PRAGMA foreign_keys')).rows.single.getInt('foreign_keys'),
        1,
      );
      expect(
        (await database.query(
          'SELECT COUNT(*) AS value FROM content._voxel_phases',
        )).rows.single.getInt('value'),
        2,
      );
    });
  });
}

Directory _fixtureDirectory() {
  final packageRelative = Directory('test/fixtures/rebuild_migrations');
  if (packageRelative.existsSync()) return packageRelative;
  return Directory('packages/database/voxel/test/fixtures/rebuild_migrations');
}

VoxelDatabaseSchema _runtimeSchema() {
  final column = VoxelColumn<String>(
    VoxelTextCodec(),
    declaredName: 'id',
  );
  final table = VoxelTableSchema<Object?, Object?>(
    schemaName: 'content',
    tableName: 'runtime_registration',
    definition: Object(),
    columns: [column as VoxelColumn<Object?>],
    columnNames: const ['id'],
    decode: (_, _) => Object(),
    definitionType: Object,
    rowType: Object,
  );
  return VoxelDatabaseSchema(name: 'rebuild_runtime', tables: [table]);
}

Future<void> _openAtInitial(
  TursoDatabase database,
  VoxelMigrationPlan plan,
  String initialMigrationId,
) async {
  await database.execute("ATTACH DATABASE ':memory:' AS content");
  await database.execute('PRAGMA foreign_keys=ON');
  await expectLater(
    plan.applyPersistentScope(
      database,
      scope: 'content',
      fileIdentity: 'rebuild-file',
      interrupt: (event) async {
        if (event.point == VoxelMigrationInterruptionPoint.afterPhaseCommit &&
            event.migrationId == initialMigrationId) {
          throw StateError('stop after initial migration');
        }
      },
    ),
    throwsStateError,
  );
}

Future<void> _insertCycle(TursoDatabase database) async {
  await database.execute(
    "INSERT INTO content.parents VALUES ('acme', 'p1', '7', NULL, NULL)",
  );
  await database.execute(
    "INSERT INTO content.children VALUES ('acme', 'c1', 'acme', 'p1')",
  );
  await database.execute(
    "UPDATE content.parents SET favoriteChildTenant = 'acme', favoriteChildId = 'c1' "
    "WHERE tenant = 'acme' AND id = 'p1'",
  );
}

VoxelMigrationBundle _bundle(Directory directory) {
  final journal = jsonDecode(
    File('${directory.path}/journal.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return VoxelMigrationBundle(
    databaseId: journal['databaseId']! as String,
    migrations: [
      for (final rawEntry in journal['entries']! as List<Object?>)
        _migration(directory, rawEntry! as Map<String, Object?>),
    ],
  );
}

VoxelBundledMigration _migration(Directory root, Map<String, Object?> entry) {
  final directory = '${root.path}/${entry['directory']}';
  return VoxelBundledMigration(
    directory: entry['directory']! as String,
    sql: File('$directory/migration.sql').readAsStringSync(),
    metadata:
        jsonDecode(File('$directory/migration.json').readAsStringSync()) as Map<String, Object?>,
    snapshot:
        jsonDecode(File('$directory/snapshot.json').readAsStringSync()) as Map<String, Object?>,
  );
}

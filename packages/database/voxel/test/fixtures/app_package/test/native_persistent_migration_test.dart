import 'dart:io';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/src/connection.dart' show VoxelDatabaseRuntime, VoxelStorage, VoxelTesting;
import 'package:voxel/src/migration.dart';
import 'package:voxel/src/migration_status.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/fixture_app.voxel_migrations.dart';

void main() {
  test('migration status should not create files and should report durable receipts', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'voxel-generated-status-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final schema = FixtureAppDatabaseVoxelSchema.build();
    final storage = VoxelStorage.directory(temporaryDirectory.path);

    final missing = await VoxelDatabaseRuntime.migrationStatus(
      schema: schema,
      bundle: FixtureAppDatabaseVoxelMigrations.bundle,
      storage: storage,
    );
    expect(
      missing.migrations.expand((migration) => migration.phases).map((phase) => phase.state),
      everyElement(VoxelMigrationPhaseState.pending),
    );
    expect(temporaryDirectory.listSync(), isEmpty);

    final database = await FixtureAppDatabase().open(storage: storage);
    await database.close();
    final applied = await VoxelDatabaseRuntime.migrationStatus(
      schema: schema,
      bundle: FixtureAppDatabaseVoxelMigrations.bundle,
      storage: storage,
    );
    expect(
      applied.migrations.expand((migration) => migration.phases).map((phase) => phase.state),
      everyElement(VoxelMigrationPhaseState.completed),
    );
  });

  test('resolve migration should reject a database without an active attempt', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'voxel-generated-resolve-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    await expectLater(
      VoxelDatabaseRuntime.resolveMigration(
        schema: FixtureAppDatabaseVoxelSchema.build(),
        bundle: FixtureAppDatabaseVoxelMigrations.bundle,
        migrationId: FixtureAppDatabaseVoxelMigrations.bundle.migrations.first.id,
        phaseId: '0',
        expectedChecksum: FixtureAppDatabaseVoxelMigrations.bundle.migrations.first.checksum,
        attemptId: 'missing',
        reason: 'operator verified state',
        resolution: VoxelMigrationResolution.completed,
        storage: VoxelStorage.directory(temporaryDirectory.path),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(temporaryDirectory.listSync(), isEmpty);
  });

  test('generated open creates and reopens its persistent main file', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'voxel-generated-persistent-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final created = await FixtureAppDatabase().open(
      storage: VoxelStorage.directory(temporaryDirectory.path),
    );
    expect(
      await VoxelTesting.scalarText(
        created,
        'SELECT database_id AS value FROM _voxel_identity',
      ),
      FixtureAppDatabaseVoxelMigrations.bundle.databaseId,
    );
    await created.close();

    final reopened = await FixtureAppDatabase().open(
      storage: VoxelStorage.directory(temporaryDirectory.path),
    );
    await reopened.close();
  });

  group('VoxelMigrationPlan persistent scope', () {
    late Directory temporaryDirectory;
    late VoxelMigrationPlan plan;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('voxel-persistent-');
      plan = VoxelMigrationPlan.validate(
        schema: FixtureAppDatabaseVoxelSchema.build(),
        bundle: FixtureAppDatabaseVoxelMigrations.bundle,
      );
    });

    tearDown(() => temporaryDirectory.delete(recursive: true));

    test('should roll back data and receipt when interrupted before commit', () async {
      final path = '${temporaryDirectory.path}/content.db';
      final database = await _openAttached(path);
      await expectLater(
        plan.applyPersistentScope(
          database,
          scope: 'content',
          fileIdentity: 'content-file',
          interrupt: (interruption) async {
            if (interruption.point == VoxelMigrationInterruptionPoint.beforePhaseCommit) {
              throw StateError('simulated crash');
            }
          },
        ),
        throwsStateError,
      );
      expect(
        (await database.query(
          "SELECT COUNT(*) AS value FROM content.sqlite_master WHERE name = 'authors'",
        )).rows.single.getInt('value'),
        0,
      );
      expect(
        (await database.query(
          'SELECT COUNT(*) AS value FROM content._voxel_phases',
        )).rows.single.getInt('value'),
        0,
      );
      await database.close();

      final reopened = await _openAttached(path);
      addTearDown(reopened.close);
      await plan.applyPersistentScope(
        reopened,
        scope: 'content',
        fileIdentity: 'content-file',
      );
      expect(
        (await reopened.query(
          'SELECT COUNT(*) AS value FROM content._voxel_phases',
        )).rows.single.getInt('value'),
        3,
      );
    });

    test('should preserve committed receipt and resume after interruption', () async {
      final path = '${temporaryDirectory.path}/content.db';
      final database = await _openAttached(path);
      await expectLater(
        plan.applyPersistentScope(
          database,
          scope: 'content',
          fileIdentity: 'content-file',
          interrupt: (interruption) async {
            if (interruption.point == VoxelMigrationInterruptionPoint.afterPhaseCommit) {
              throw StateError('simulated crash');
            }
          },
        ),
        throwsStateError,
      );
      expect(
        (await database.query(
          'SELECT COUNT(*) AS value FROM content._voxel_phases',
        )).rows.single.getInt('value'),
        1,
      );
      await database.close();

      final reopened = await _openAttached(path);
      addTearDown(reopened.close);
      await plan.applyPersistentScope(
        reopened,
        scope: 'content',
        fileIdentity: 'content-file',
      );
      expect(
        (await reopened.query(
          'SELECT COUNT(*) AS value FROM content._voxel_phases',
        )).rows.single.getInt('value'),
        3,
      );
      expect(
        (await reopened.query(
          "SELECT COUNT(*) AS value FROM content.sqlite_master WHERE name = 'posts'",
        )).rows.single.getInt('value'),
        1,
      );
    });

    test('should reject modified applied history', () async {
      final path = '${temporaryDirectory.path}/content.db';
      final database = await _openAttached(path);
      await plan.applyPersistentScope(
        database,
        scope: 'content',
        fileIdentity: 'content-file',
      );
      await database.execute(
        "UPDATE content._voxel_migrations SET checksum = 'modified' WHERE ordinal = 0",
      );
      await database.close();

      final reopened = await _openAttached(path);
      addTearDown(reopened.close);
      await expectLater(
        plan.applyPersistentScope(
          reopened,
          scope: 'content',
          fileIdentity: 'content-file',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Future<TursoDatabase> _openAttached(String path) async {
  final database = await TursoDatabase.open(TursoLocation.memory());
  await database.execute('ATTACH DATABASE ? AS content', parameters: [path]);
  await database.execute('PRAGMA foreign_keys=ON');
  return database;
}

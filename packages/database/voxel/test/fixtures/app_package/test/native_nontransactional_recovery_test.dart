import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/src/migration.dart';
import 'package:voxel/src/platform.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_schema/authors.dart';
import 'package:voxel_generator/src/migration/sealer.dart';
import 'package:voxel_generator/voxel_generator.dart';

void main() {
  group('Voxel nontransactional recovery', () {
    late Directory artifacts;
    late VoxelDatabaseSchema schema;
    late VoxelMigrationBundle bundle;

    setUp(() async {
      artifacts = await Directory.systemTemp.createTemp('voxel-recovery-artifacts-');
      schema = VoxelDatabaseSchema(
        name: 'recovery_fixture',
        tables: [Authors.db.buildSchema() as VoxelTableSchema<Object?, Object?>],
      );
      bundle = await _recoveryBundle(schema, artifacts);
    });

    tearDown(() => artifacts.delete(recursive: true));

    test('should audit completion after an interrupted completed effect', () async {
      final storage = await Directory.systemTemp.createTemp('voxel-recovery-complete-');
      addTearDown(() => storage.delete(recursive: true));

      await expectLater(
        _openWithInterruption(
          schema,
          bundle,
          storage.path,
          VoxelMigrationInterruptionPoint.beforePhaseCommit,
        ),
        throwsStateError,
      );
      final status = await _status(schema, bundle, storage.path);
      final phase = status.migrations.single.phases.single;
      expect(phase.state, VoxelMigrationPhaseState.completed);
      expect(phase.completionRecorded, isFalse);
      expect(phase.evidence!['current'], {
        'classification': 'completed',
        'observations': [false, true],
      });

      await expectLater(
        _resolve(
          schema,
          bundle,
          storage.path,
          phase,
          attemptId: 'stale-attempt',
          resolution: VoxelMigrationResolution.completed,
        ),
        throwsA(isA<FormatException>()),
      );
      await _resolve(
        schema,
        bundle,
        storage.path,
        phase,
        resolution: VoxelMigrationResolution.completed,
      );

      final opened = await VoxelDatabaseRuntime.open(
        schema: schema,
        bundle: bundle,
        storage: VoxelStorage.directory(storage.path),
      );
      addTearDown(opened.close);
      expect(
        await VoxelTesting.scalarInt(
          opened,
          'SELECT COUNT(*) AS value FROM content._voxel_migration_resolutions '
          "WHERE resolution = 'completed'",
        ),
        1,
      );
    });

    test('should audit retry and execute only after a proven unstarted effect', () async {
      final storage = await Directory.systemTemp.createTemp('voxel-recovery-retry-');
      addTearDown(() => storage.delete(recursive: true));

      await expectLater(
        _openWithInterruption(
          schema,
          bundle,
          storage.path,
          VoxelMigrationInterruptionPoint.afterPhaseStarted,
        ),
        throwsStateError,
      );
      final phase = (await _status(schema, bundle, storage.path)).migrations.single.phases.single;
      expect(phase.state, VoxelMigrationPhaseState.started);
      expect(phase.completionRecorded, isFalse);
      await _resolve(
        schema,
        bundle,
        storage.path,
        phase,
        resolution: VoxelMigrationResolution.retry,
      );

      final opened = await VoxelDatabaseRuntime.open(
        schema: schema,
        bundle: bundle,
        storage: VoxelStorage.directory(storage.path),
      );
      addTearDown(opened.close);
      expect(
        await VoxelTesting.scalarInt(
          opened,
          'SELECT COUNT(*) AS value FROM content._voxel_migration_resolutions '
          "WHERE resolution = 'retry'",
        ),
        1,
      );
      final completed = (await _status(
        schema,
        bundle,
        storage.path,
      )).migrations.single.phases.single;
      expect(completed.state, VoxelMigrationPhaseState.completed);
      expect(completed.completionRecorded, isTrue);
    });

    test('should report mixed recovery evidence as uncertain', () async {
      final storage = await Directory.systemTemp.createTemp('voxel-recovery-uncertain-');
      addTearDown(() => storage.delete(recursive: true));
      await expectLater(
        _openWithInterruption(
          schema,
          bundle,
          storage.path,
          VoxelMigrationInterruptionPoint.afterPhaseStarted,
        ),
        throwsStateError,
      );
      final plan = VoxelMigrationPlan.validate(schema: schema, bundle: bundle);
      final content = plan.scopes.singleWhere((scope) => scope.name == 'content');
      final resource = resolveVoxelNativeAttachmentResource(
        databaseName: schema.name,
        schemaId: content.id,
        directory: storage.path,
      );
      final database = await TursoDatabase.open(TursoLocation.file(resource.path));
      await database.execute('CREATE TABLE authors (different TEXT)');
      await database.close();

      final phase = (await _status(schema, bundle, storage.path)).migrations.single.phases.single;
      expect(phase.state, VoxelMigrationPhaseState.uncertain);
      expect(phase.completionRecorded, isFalse);
      expect(phase.evidence!['current'], {
        'classification': 'uncertain',
        'observations': [false, false],
      });
    });

    test('should include platform-inapplicable phases as skipped', () async {
      final browserArtifacts = await Directory.systemTemp.createTemp(
        'voxel-browser-only-artifacts-',
      );
      final storage = await Directory.systemTemp.createTemp('voxel-skipped-status-');
      addTearDown(() => browserArtifacts.delete(recursive: true));
      addTearDown(() => storage.delete(recursive: true));
      final browserBundle = await _recoveryBundle(
        schema,
        browserArtifacts,
        platforms: const ['browser'],
      );

      final phase = (await _status(
        schema,
        browserBundle,
        storage.path,
      )).migrations.single.phases.single;
      expect(phase.state, VoxelMigrationPhaseState.skipped);
      expect(phase.completionRecorded, isFalse);
      expect(storage.listSync(), isEmpty);
    });

    test('should consume an audited manual retry with a fresh attempt', () async {
      final manualArtifacts = await Directory.systemTemp.createTemp(
        'voxel-manual-artifacts-',
      );
      final storage = await Directory.systemTemp.createTemp('voxel-manual-retry-');
      addTearDown(() => manualArtifacts.delete(recursive: true));
      addTearDown(() => storage.delete(recursive: true));
      final manualBundle = await _recoveryBundle(schema, manualArtifacts, manual: true);
      await expectLater(
        _openWithInterruption(
          schema,
          manualBundle,
          storage.path,
          VoxelMigrationInterruptionPoint.afterPhaseStarted,
        ),
        throwsStateError,
      );
      final phase = (await _status(
        schema,
        manualBundle,
        storage.path,
      )).migrations.single.phases.single;
      await _resolve(
        schema,
        manualBundle,
        storage.path,
        phase,
        resolution: VoxelMigrationResolution.retry,
      );

      final opened = await VoxelDatabaseRuntime.open(
        schema: schema,
        bundle: manualBundle,
        storage: VoxelStorage.directory(storage.path),
      );
      addTearDown(opened.close);
      expect(
        await VoxelTesting.scalarInt(
          opened,
          'SELECT COUNT(*) AS value FROM content._voxel_migration_resolutions '
          "WHERE resolution = 'retry'",
        ),
        1,
      );
      expect(
        await VoxelTesting.scalarInt(
          opened,
          'SELECT COUNT(*) AS value FROM content._voxel_phase_attempts a '
          'JOIN content._voxel_migration_resolutions r '
          'ON a.migration_id = r.migration_id AND a.phase_id = r.phase_id '
          'WHERE a.attempt_id != r.attempt_id AND a.retry_authorized = 0',
        ),
        1,
      );
    });
  });
}

Future<VoxelMigrationBundle> _recoveryBundle(
  VoxelDatabaseSchema schema,
  Directory directory, {
  List<String> platforms = const ['native', 'browser'],
  bool manual = false,
}) async {
  final migrationId = (await const VoxelMigrationGenerator().generate(
    schema: schema,
    directory: directory,
    name: 'initial',
  ))!;
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
  final migrationDirectory = Directory('${directory.path}/${entry['directory']}');
  final metadataFile = File('${migrationDirectory.path}/migration.json');
  final metadata = jsonDecode(metadataFile.readAsStringSync()) as Map<String, Object?>;
  final sql = File('${migrationDirectory.path}/migration.sql').readAsStringSync();
  final phase = (metadata['phases']! as List<Object?>).single! as Map<String, Object?>;
  final storedSql = await _storedCreateSql(
    sql,
    phase['statements']! as List<Object?>,
  );
  phase
    ..['mode'] = 'nontransactional'
    ..['platforms'] = platforms
    ..['recovery'] = manual
        ? {
            'kind': 'manual',
            'operationId': '11111111111111111111111111111111',
            'before': {'schema': 'content', 'table': 'authors', 'exists': false},
            'after': {'schema': 'content', 'table': 'authors', 'sql': storedSql},
          }
        : {
            'kind': 'catalog',
            'operationId': '11111111111111111111111111111111',
            'before': {'schema': 'content', 'table': 'authors', 'exists': false},
            'after': {'schema': 'content', 'table': 'authors', 'sql': storedSql},
            'checks': [
              {
                'sql': '''
SELECT NOT EXISTS (
  SELECT 1 FROM "content".sqlite_schema
  WHERE type = ? AND name = ? AND tbl_name = ?
)
''',
                'parameters': [
                  {'type': 'string', 'value': 'table'},
                  {'type': 'string', 'value': 'authors'},
                  {'type': 'string', 'value': 'authors'},
                ],
                'expected': false,
              },
              {
                'sql': '''
SELECT EXISTS (
  SELECT 1 FROM "content".sqlite_schema
  WHERE type = ? AND name = ? AND tbl_name = ? AND sql = ?
)
''',
                'parameters': [
                  {'type': 'string', 'value': 'table'},
                  {'type': 'string', 'value': 'authors'},
                  {'type': 'string', 'value': 'authors'},
                  {'type': 'string', 'value': storedSql},
                ],
                'expected': true,
              },
            ],
          };
  metadataFile.writeAsStringSync(jsonEncode(metadata));
  await VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId);
  final sealedMetadata = jsonDecode(metadataFile.readAsStringSync()) as Map<String, Object?>;
  final snapshot = jsonDecode(
    File('${migrationDirectory.path}/snapshot.json').readAsStringSync(),
  ) as Map<String, Object?>;
  return VoxelMigrationBundle(
    databaseId: journal['databaseId']! as String,
    migrations: [
      VoxelBundledMigration(
        directory: entry['directory']! as String,
        sql: sql,
        metadata: sealedMetadata,
        snapshot: snapshot,
      ),
    ],
  );
}

Future<String> _storedCreateSql(String sql, List<Object?> statements) async {
  final database = await TursoDatabase.open(TursoLocation.memory());
  try {
    await database.execute("ATTACH DATABASE ':memory:' AS content");
    final bytes = Uint8List.fromList(utf8.encode(sql));
    for (final raw in statements) {
      final range = raw! as Map<String, Object?>;
      await database.execute(
        utf8.decode(
          bytes.sublist(range['startByte']! as int, range['endByte']! as int),
        ),
      );
    }
    return (await database.query(
      "SELECT sql FROM content.sqlite_schema WHERE type = 'table' AND name = 'authors'",
    )).rows.single.getString('sql');
  } finally {
    await database.close();
  }
}

Future<TursoDatabase> _openWithInterruption(
  VoxelDatabaseSchema schema,
  VoxelMigrationBundle bundle,
  String directory,
  VoxelMigrationInterruptionPoint point,
) {
  final plan = VoxelMigrationPlan.validate(schema: schema, bundle: bundle);
  return openVoxelPersistentDatabase(
    databaseName: schema.name,
    directory: directory,
    migrations: plan,
    lockTimeout: const Duration(seconds: 1),
    encryptionCipher: null,
    encryptionKey: null,
    schemaDirectories: {'content': null},
    schemaEncryptionCiphers: {'content': null},
    schemaEncryptionKeys: {'content': null},
    interrupt: (interruption) async {
      if (interruption.point == point) throw StateError('simulated interruption');
    },
  );
}

Future<VoxelMigrationStatus> _status(
  VoxelDatabaseSchema schema,
  VoxelMigrationBundle bundle,
  String directory,
) => VoxelDatabaseRuntime.migrationStatus(
  schema: schema,
  bundle: bundle,
  storage: VoxelStorage.directory(directory),
);

Future<void> _resolve(
  VoxelDatabaseSchema schema,
  VoxelMigrationBundle bundle,
  String directory,
  VoxelMigrationPhaseStatus phase, {
  required VoxelMigrationResolution resolution,
  String? attemptId,
}) => VoxelDatabaseRuntime.resolveMigration(
  schema: schema,
  bundle: bundle,
  migrationId: bundle.migrations.single.id,
  phaseId: phase.id,
  expectedChecksum: bundle.migrations.single.checksum,
  attemptId: attemptId ?? phase.attemptId!,
  reason: 'operator inspected the catalog',
  resolution: resolution,
  storage: VoxelStorage.directory(directory),
);

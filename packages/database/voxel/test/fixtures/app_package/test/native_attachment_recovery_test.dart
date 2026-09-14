import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/src/connection.dart';
import 'package:voxel/src/migration.dart';
import 'package:voxel/src/migration_status.dart';
import 'package:voxel/src/platform_native.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/fixture_app.voxel_migrations.dart';

void main() {
  group('native attached-file recovery', () {
    late Directory storage;
    late VoxelMigrationPlan plan;
    late VoxelMigrationScope content;

    setUp(() async {
      storage = await Directory.systemTemp.createTemp('voxel-attachments-');
      plan = VoxelMigrationPlan.validate(
        schema: FixtureAppDatabaseVoxelSchema.build(),
        bundle: FixtureAppDatabaseVoxelMigrations.bundle,
      );
      content = plan.scopes.singleWhere((scope) => scope.name == 'content');
    });

    tearDown(() => storage.delete(recursive: true));

    test('should persist attached data, identity, registry, and receipts', () async {
      final database = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
      );
      await VoxelTesting.execute(
        database,
        "INSERT INTO content.authors VALUES ('author-1', 'Ada')",
      );
      await database.close();

      final attachment = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      final inspected = await TursoDatabase.open(TursoLocation.file(attachment.path));
      expect(
        (await inspected.query('SELECT COUNT(*) AS value FROM authors')).rows.single.getInt(
          'value',
        ),
        1,
      );
      expect(
        (await inspected.query('SELECT COUNT(*) AS value FROM _voxel_phases')).rows.single
            .getInt('value'),
        3,
      );
      expect(
        (await inspected.query(
          "SELECT COUNT(*) AS value FROM _voxel_file_bootstrap WHERE status = 'completed'",
        )).rows.single.getInt('value'),
        1,
      );
      expect(
        (await inspected.query(
          'SELECT COUNT(*) AS value FROM sqlite_master '
          "WHERE name IN ('_voxel_files', '_voxel_phase_summaries')",
        )).rows.single.getInt('value'),
        0,
      );
      await inspected.close();

      final reopened = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
      );
      expect(
        await VoxelTesting.scalarInt(
          reopened,
          'SELECT COUNT(*) AS value FROM content.authors',
        ),
        1,
      );
      expect(
        await VoxelTesting.scalarText(
          reopened,
          "SELECT state AS value FROM main._voxel_files WHERE schema_id = '${content.id}'",
        ),
        'initialized',
      );
      await reopened.close();
    });

    test('should reject a missing initialized attachment', () async {
      final database = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
      );
      await database.close();
      final attachment = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      await File(attachment.path).delete();

      final status = await VoxelDatabaseRuntime.migrationStatus(
        schema: FixtureAppDatabaseVoxelSchema.build(),
        bundle: FixtureAppDatabaseVoxelMigrations.bundle,
        storage: VoxelStorage.directory(storage.path),
      );
      expect(
        status.migrations
            .expand((migration) => migration.phases)
            .where((phase) => phase.scopeId == content.id)
            .map((phase) => phase.state),
        everyElement(VoxelMigrationPhaseState.uncertain),
      );
      expect(File(attachment.path).existsSync(), isFalse);

      await expectLater(
        FixtureAppDatabase().open(storage: VoxelStorage.directory(storage.path)),
        throwsA(isA<FormatException>()),
      );
      expect(File(attachment.path).existsSync(), isFalse);
    });

    test('should reject an unregistered preexisting attachment', () async {
      final attachment = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      final unrelated = await TursoDatabase.open(TursoLocation.file(attachment.path));
      await unrelated.execute('CREATE TABLE unrelated (id INTEGER PRIMARY KEY)');
      await unrelated.close();

      await expectLater(
        FixtureAppDatabase().open(storage: VoxelStorage.directory(storage.path)),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject a mismatched attachment bootstrap receipt', () async {
      final created = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
      );
      await created.close();
      final attachment = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      final tampered = await TursoDatabase.open(TursoLocation.file(attachment.path));
      await tampered.execute(
        "UPDATE _voxel_file_bootstrap SET file_identity = 'replacement'",
      );
      await tampered.close();

      await expectLater(
        FixtureAppDatabase().open(storage: VoxelStorage.directory(storage.path)),
        throwsA(isA<FormatException>()),
      );
    });

    test('should accept only a same-identity relocation', () async {
      final created = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
      );
      await created.close();
      final original = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      final relocatedDirectory = Directory('${storage.path}/relocated')..createSync();
      final relocated = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: relocatedDirectory.path,
      );
      for (final suffix in ['', '-wal', '-shm']) {
        final source = File('${original.path}$suffix');
        if (source.existsSync()) {
          await source.rename('${relocated.path}$suffix');
        }
      }
      final moved = await TursoDatabase.open(TursoLocation.file(relocated.path));
      expect(
        (await moved.query('SELECT file_identity FROM _voxel_identity')).rows.single.getString(
          'file_identity',
        ),
        isNotEmpty,
      );
      await moved.close();

      final reopened = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
        schemaStorage: {'content': VoxelStorage.directory(relocatedDirectory.path)},
      );
      await reopened.close();

      await File(relocated.path).delete();
      final replacement = await TursoDatabase.open(TursoLocation.file(relocated.path));
      await replacement.close();
      await expectLater(
        FixtureAppDatabase().open(
          storage: VoxelStorage.directory(storage.path),
          schemaStorage: {'content': VoxelStorage.directory(relocatedDirectory.path)},
        ),
        throwsA(anything),
      );
    });

    test('should reconcile crashes at every file-creation boundary', () async {
      for (final point in [
        VoxelMigrationInterruptionPoint.afterCreationPrepared,
        VoxelMigrationInterruptionPoint.afterFileBootstrap,
        VoxelMigrationInterruptionPoint.afterRegistryInitialized,
      ]) {
        final caseDirectory = Directory('${storage.path}/${point.name}')..createSync();
        var interrupted = false;
        await expectLater(
          _openPlan(
            plan,
            caseDirectory.path,
            interrupt: (event) async {
              if (!interrupted && event.point == point) {
                interrupted = true;
                throw StateError('simulated ${point.name} crash');
              }
            },
          ),
          throwsStateError,
        );
        if (point == VoxelMigrationInterruptionPoint.afterCreationPrepared) {
          final attachment = resolveVoxelNativeAttachmentResource(
            databaseName: 'fixture_app',
            schemaId: content.id,
            directory: caseDirectory.path,
          );
          await File(attachment.path).create();
        }
        final recovered = await _openPlan(plan, caseDirectory.path);
        expect(
          (await recovered.query(
            'SELECT COUNT(*) AS value FROM content._voxel_phases',
          )).rows.single.getInt('value'),
          3,
        );
        await recovered.close();
      }
    });

    test('should reject substitution at a prepared path', () async {
      var interrupted = false;
      await expectLater(
        _openPlan(
          plan,
          storage.path,
          interrupt: (event) async {
            if (!interrupted &&
                event.point == VoxelMigrationInterruptionPoint.afterCreationPrepared) {
              interrupted = true;
              throw StateError('simulated prepared crash');
            }
          },
        ),
        throwsStateError,
      );
      final attachment = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      final unrelated = await TursoDatabase.open(TursoLocation.file(attachment.path));
      await unrelated.execute('CREATE TABLE unrelated (id INTEGER PRIMARY KEY)');
      await unrelated.close();

      await expectLater(
        _openPlan(plan, storage.path),
        throwsA(isA<FormatException>()),
      );
    });

    test('status should leave a prepared attachment pending without creating it', () async {
      await expectLater(
        _openPlan(
          plan,
          storage.path,
          interrupt: (event) async {
            if (event.point == VoxelMigrationInterruptionPoint.afterCreationPrepared) {
              throw StateError('simulated prepared crash');
            }
          },
        ),
        throwsStateError,
      );
      final attachment = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      expect(File(attachment.path).existsSync(), isFalse);

      final status = await VoxelDatabaseRuntime.migrationStatus(
        schema: FixtureAppDatabaseVoxelSchema.build(),
        bundle: FixtureAppDatabaseVoxelMigrations.bundle,
        storage: VoxelStorage.directory(storage.path),
      );
      expect(
        status.migrations
            .expand((migration) => migration.phases)
            .where((phase) => phase.scopeId == content.id)
            .map((phase) => phase.state),
        everyElement(VoxelMigrationPhaseState.pending),
      );
      expect(File(attachment.path).existsSync(), isFalse);
    });

    test('should recover attachment commit and main-summary interruptions', () async {
      for (final point in [
        VoxelMigrationInterruptionPoint.afterPhaseCommit,
        VoxelMigrationInterruptionPoint.beforeMainSummary,
        VoxelMigrationInterruptionPoint.afterMainSummary,
      ]) {
        final caseDirectory = Directory('${storage.path}/${point.name}')..createSync();
        var interrupted = false;
        await expectLater(
          _openPlan(
            plan,
            caseDirectory.path,
            interrupt: (event) async {
              if (!interrupted && event.point == point) {
                interrupted = true;
                throw StateError('simulated ${point.name} crash');
              }
            },
          ),
          throwsStateError,
        );
        final recovered = await _openPlan(plan, caseDirectory.path);
        expect(
          (await recovered.query(
            'SELECT COUNT(*) AS value FROM content._voxel_phases',
          )).rows.single.getInt('value'),
          3,
        );
        expect(
          (await recovered.query(
            'SELECT COUNT(*) AS value FROM main._voxel_phase_summaries',
          )).rows.single.getInt('value'),
          3,
        );
        await recovered.close();
      }
    });

    test('should support inherited, separate, and plaintext attachment encryption', () async {
      final mainKey = _key(1);
      final contentKey = _key(33);
      final inheritedDirectory = Directory('${storage.path}/inherited')..createSync();
      final inherited = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(inheritedDirectory.path),
        encryption: VoxelEncryption(cipher: VoxelCipher.aegis256, key: mainKey),
      );
      await inherited.close();
      await expectLater(
        FixtureAppDatabase().open(
          storage: VoxelStorage.directory(inheritedDirectory.path),
          encryption: VoxelEncryption(cipher: VoxelCipher.aegis256, key: mainKey),
          schemaEncryption: {'content': null},
        ),
        throwsA(anything),
      );

      final separateDirectory = Directory('${storage.path}/separate')..createSync();
      final separate = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(separateDirectory.path),
        encryption: VoxelEncryption(cipher: VoxelCipher.aes256gcm, key: mainKey),
        schemaEncryption: {
          'content': VoxelEncryption(cipher: VoxelCipher.aegis256, key: contentKey),
        },
      );
      await separate.close();
      final wrongContentKey = Uint8List.fromList(contentKey)..[0] ^= 0xff;
      Object? wrongKeyFailure;
      try {
        await FixtureAppDatabase().open(
          storage: VoxelStorage.directory(separateDirectory.path),
          encryption: VoxelEncryption(cipher: VoxelCipher.aes256gcm, key: mainKey),
          schemaEncryption: {
            'content': VoxelEncryption(
              cipher: VoxelCipher.aegis256,
              key: wrongContentKey,
            ),
          },
        );
      } on Object catch (error) {
        wrongKeyFailure = error;
      }
      expect(wrongKeyFailure, isNotNull);
      expect(wrongKeyFailure.toString(), isNot(contains(_hex(wrongContentKey))));
      final reopened = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(separateDirectory.path),
        encryption: VoxelEncryption(cipher: VoxelCipher.aes256gcm, key: mainKey),
        schemaEncryption: {
          'content': VoxelEncryption(cipher: VoxelCipher.aegis256, key: contentKey),
        },
      );
      await reopened.close();

      final plaintextDirectory = Directory('${storage.path}/plaintext')..createSync();
      final plaintext = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(plaintextDirectory.path),
        encryption: VoxelEncryption(cipher: VoxelCipher.aegis256, key: mainKey),
        schemaEncryption: {'content': null},
      );
      await plaintext.close();
      final attachment = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: plaintextDirectory.path,
      );
      final direct = await TursoDatabase.open(TursoLocation.file(attachment.path));
      await direct.close();
    });

    test('should reject unknown and incompatible schema options before creating files', () async {
      await expectLater(
        FixtureAppDatabase().open(
          storage: VoxelStorage.directory(storage.path),
          schemaStorage: {'unknown': VoxelStorage.directory(storage.path)},
        ),
        throwsArgumentError,
      );
      await expectLater(
        FixtureAppDatabase().open(
          storage: VoxelStorage.directory(storage.path),
          schemaStorage: {'content': const VoxelStorage.memory()},
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(storage.listSync(), isEmpty);
    });

    test('should release planned locks when registry-set reacquisition times out', () async {
      final created = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
      );
      await created.close();
      final original = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: storage.path,
      );
      final owner = await VoxelNativeMigrationCoordinator.acquire(
        [original],
        timeout: Duration.zero,
      );
      final relocatedDirectory = Directory('${storage.path}/relocated')..createSync();

      await expectLater(
        openVoxelPersistentDatabase(
          databaseName: 'fixture_app',
          directory: storage.path,
          migrations: plan,
          lockTimeout: const Duration(milliseconds: 30),
          encryptionCipher: null,
          encryptionKey: null,
          schemaDirectories: {'content': relocatedDirectory.path},
          schemaEncryptionCiphers: {'content': null},
          schemaEncryptionKeys: {'content': null},
        ),
        throwsA(isA<TimeoutException>()),
      );
      owner.release();

      final main = await resolveVoxelNativeMainResource(
        databaseName: 'fixture_app',
        directory: storage.path,
      );
      final planned = resolveVoxelNativeAttachmentResource(
        databaseName: 'fixture_app',
        schemaId: content.id,
        directory: relocatedDirectory.path,
      );
      final available = await VoxelNativeMigrationCoordinator.acquire(
        [main, original, planned],
        timeout: Duration.zero,
      );
      available.release();
    });

    test('should reject a missing main while its attachment remains', () async {
      final created = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(storage.path),
      );
      await created.close();
      final main = await resolveVoxelNativeMainResource(
        databaseName: 'fixture_app',
        directory: storage.path,
      );
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('${main.path}$suffix');
        if (file.existsSync()) await file.delete();
      }

      await expectLater(
        FixtureAppDatabase().open(storage: VoxelStorage.directory(storage.path)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Future<TursoDatabase> _openPlan(
  VoxelMigrationPlan plan,
  String directory, {
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
}) => openVoxelPersistentDatabase(
  databaseName: 'fixture_app',
  directory: directory,
  migrations: plan,
  lockTimeout: const Duration(seconds: 1),
  encryptionCipher: null,
  encryptionKey: null,
  schemaDirectories: {'content': null},
  schemaEncryptionCiphers: {'content': null},
  schemaEncryptionKeys: {'content': null},
  interrupt: interrupt,
);

Uint8List _key(int offset) => Uint8List.fromList(
  List<int>.generate(32, (index) => (index + offset) & 0xff),
);

String _hex(Uint8List value) => value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

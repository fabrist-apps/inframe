import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/src/connection.dart' show VoxelStorage;
import 'package:voxel/src/migration.dart';
import 'package:voxel/src/platform_native.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/fixture_app.voxel_migrations.dart';

void main() {
  group('Voxel native platform', () {
    test('should require configured storage in plain Dart', () async {
      await expectLater(
        resolveVoxelNativeStorageDirectory(null),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('should use a registered default and let an explicit directory override it', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('voxel-default-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final defaultDirectory = Directory('${temporaryDirectory.path}/default');
      final explicitDirectory = Directory('${temporaryDirectory.path}/explicit');
      registerVoxelNativeDefaultStorage(() async => defaultDirectory.path);

      final defaultDatabase = await FixtureAppDatabase().open();
      await defaultDatabase.close();
      expect(defaultDirectory.listSync().whereType<File>(), isNotEmpty);

      final explicitDatabase = await FixtureAppDatabase().open(
        storage: VoxelStorage.directory(explicitDirectory.path),
      );
      await explicitDatabase.close();
      expect(explicitDirectory.listSync().whereType<File>(), isNotEmpty);
    });

    test('should safely namespace names inside a canonical explicit directory', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('voxel-native-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final nested = '${temporaryDirectory.path}/parent/../database';

      final resource = await resolveVoxelNativeMainResource(
        databaseName: '../customer/records',
        directory: nested,
      );
      final canonicalDirectory = await Directory(nested).resolveSymbolicLinks();

      expect(File(resource.path).parent.path, canonicalDirectory);
      expect(resource.path, isNot(contains('../customer')));
      expect(resource.path, endsWith('.db'));
    });

    test('should convert both encryption ciphers and copy key material', () {
      final source = Uint8List.fromList(List<int>.generate(32, (index) => index));
      final aegis = voxelNativeEncryption(cipher: 'aegis256', key: source);
      final aes = voxelNativeEncryption(cipher: 'aes256gcm', key: source);
      source[0] = 255;

      expect(aegis.cipher, TursoCipher.aegis256);
      expect(aes.cipher, TursoCipher.aes256gcm);
      expect(aegis.key.first, 0);
    });

    for (final cipher in ['aegis256', 'aes256gcm']) {
      test('should create and reopen an encrypted $cipher main file', () async {
        final temporaryDirectory = await Directory.systemTemp.createTemp('voxel-encrypted-');
        addTearDown(() => temporaryDirectory.delete(recursive: true));
        final resource = await resolveVoxelNativeMainResource(
          databaseName: 'encrypted-app',
          directory: temporaryDirectory.path,
        );
        final plan = VoxelMigrationPlan.validate(
          schema: FixtureAppDatabaseVoxelSchema.build(),
          bundle: FixtureAppDatabaseVoxelMigrations.bundle,
        );
        final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
        final encryption = voxelNativeEncryption(cipher: cipher, key: key);

        final created = await openVoxelNativePersistentMain(
          resource: resource,
          migrations: plan,
          lockTimeout: const Duration(seconds: 1),
          encryption: encryption,
        );
        await created.close();
        final reopened = await openVoxelNativePersistentMain(
          resource: resource,
          migrations: plan,
          lockTimeout: const Duration(seconds: 1),
          encryption: encryption,
        );
        await reopened.close();

        final wrongKey = Uint8List.fromList(key)..[0] ^= 0xff;
        await expectLater(
          openVoxelNativePersistentMain(
            resource: resource,
            migrations: plan,
            lockTimeout: const Duration(seconds: 1),
            encryption: voxelNativeEncryption(cipher: cipher, key: wrongKey),
          ),
          throwsA(anything),
        );
      });
    }
  });

  group('VoxelNativeMigrationCoordinator', () {
    test('should acquire canonical paths in sorted order', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('voxel-lock-order-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final attempts = <String>[];
      final lease = await VoxelNativeMigrationCoordinator.acquire(
        [
          VoxelNativeResource('${temporaryDirectory.path}/z.db'),
          VoxelNativeResource('${temporaryDirectory.path}/a.db'),
        ],
        timeout: Duration.zero,
        tryLock: (path) {
          attempts.add(path);
          return _FakeLock();
        },
      );
      addTearDown(lease.release);

      expect(attempts, orderedEquals([...attempts]..sort()));
    });

    test('should make one immediate attempt and release partial ownership', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('voxel-lock-timeout-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final acquired = _FakeLock();
      var attempts = 0;

      await expectLater(
        VoxelNativeMigrationCoordinator.acquire(
          [
            VoxelNativeResource('${temporaryDirectory.path}/a.db'),
            VoxelNativeResource('${temporaryDirectory.path}/b.db'),
          ],
          timeout: Duration.zero,
          tryLock: (_) => ++attempts == 1 ? acquired : null,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(attempts, 2);
      expect(acquired.released, isTrue);
    });

    test('should reject aliases of one physical path', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('voxel-lock-alias-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final real = Directory('${temporaryDirectory.path}/real')..createSync();
      final alias = Link('${temporaryDirectory.path}/alias')..createSync(real.path);

      await expectLater(
        VoxelNativeMigrationCoordinator.acquire(
          [
            VoxelNativeResource('${real.path}/app.db'),
            VoxelNativeResource('${alias.path}/app.db'),
          ],
          timeout: Duration.zero,
          tryLock: (_) => _FakeLock(),
        ),
        throwsArgumentError,
      );
    });

    test('should exclude a second real native owner and release on timeout', () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp('voxel-real-lock-');
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final resource = VoxelNativeResource('${temporaryDirectory.path}/app.db');
      final owner = await VoxelNativeMigrationCoordinator.acquire(
        [resource],
        timeout: Duration.zero,
      );

      await expectLater(
        VoxelNativeMigrationCoordinator.acquire(
          [resource],
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      owner.release();

      final nextOwner = await VoxelNativeMigrationCoordinator.acquire(
        [resource],
        timeout: Duration.zero,
      );
      nextOwner.release();
    });
  });
}

final class _FakeLock implements VoxelNativeLockHandle {
  bool released = false;

  @override
  void release() => released = true;
}

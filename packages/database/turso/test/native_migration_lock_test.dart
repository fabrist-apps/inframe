@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:turso/native_migration_lock.dart';

void main() {
  group('NativeMigrationLock', () {
    late Directory temporaryDirectory;
    late String lockPath;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'turso-native-lock-',
      );
      lockPath = '${temporaryDirectory.path}/database.turso.lock';
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test('excludes independent handles and keeps the sidecar file', () {
      final owner = NativeMigrationLock.tryAcquire(lockPath);
      expect(owner, isNotNull);

      for (var attempt = 0; attempt < 50; attempt += 1) {
        expect(NativeMigrationLock.tryAcquire(lockPath), isNull);
      }
      owner!.release();
      owner.release();

      final nextOwner = NativeMigrationLock.tryAcquire(lockPath);
      expect(nextOwner, isNotNull);
      nextOwner!.release();
      expect(File(lockPath).existsSync(), isTrue);
    });

    test('reports sidecar open failures explicitly', () {
      expect(
        () => NativeMigrationLock.tryAcquire('$lockPath/missing/lock'),
        throwsA(
          isA<NativeMigrationLockException>()
              .having(
                (error) => error.operation,
                'operation',
                Platform.isWindows ? 'CreateFileW' : 'open',
              )
              .having((error) => error.path, 'path', '$lockPath/missing/lock'),
        ),
      );
    });

    test('excludes a competing Dart isolate', () async {
      final owner = NativeMigrationLock.tryAcquire(lockPath);
      expect(owner, isNotNull);

      expect(await Isolate.run(() => _canAcquire(lockPath)), isFalse);
      owner!.release();

      expect(await Isolate.run(() => _canAcquire(lockPath)), isTrue);
    });

    test('process termination releases ownership', () async {
      final process = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'test/support/native_migration_lock_holder.dart', lockPath],
        workingDirectory: _packageDirectory.path,
      );
      addTearDown(process.kill);
      final output = process.stdout
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      final errorOutput = process.stderr.transform(systemEncoding.decoder).join();

      expect(await output.first.timeout(const Duration(seconds: 20)), 'acquired');
      expect(NativeMigrationLock.tryAcquire(lockPath), isNull);

      process.kill();
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), isNotNull);
      final nextOwner = NativeMigrationLock.tryAcquire(lockPath);
      if (nextOwner == null) {
        fail('Lock remained held after child exit. stderr: ${await errorOutput}');
      }
      nextOwner.release();
    });
  });
}

bool _canAcquire(String path) {
  final lock = NativeMigrationLock.tryAcquire(path);
  lock?.release();
  return lock != null;
}

Directory get _packageDirectory {
  final current = Directory.current;
  if (File('${current.path}/pubspec.yaml').readAsStringSync().contains('name: turso')) {
    return current;
  }
  return Directory('${current.path}/packages/database/turso');
}

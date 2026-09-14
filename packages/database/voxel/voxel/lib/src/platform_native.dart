// Platform selection helpers are internal to the Voxel connection owner.
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:turso/native_migration_lock.dart';
import 'package:turso/turso.dart';

import 'package:voxel/src/migration.dart';

const voxelPlatform = 'native';

TursoWebOptions? voxelWebOptions() => null;

typedef VoxelNativeDefaultStorage = Future<String> Function();

VoxelNativeDefaultStorage? _defaultStorage;

/// Registers the Flutter application's application-support directory resolver.
void registerVoxelNativeDefaultStorage(VoxelNativeDefaultStorage resolver) {
  _defaultStorage = resolver;
}

Future<String> resolveVoxelNativeStorageDirectory(String? explicitDirectory) async {
  final selected = explicitDirectory ?? await _resolveDefaultStorage();
  if (selected.trim().isEmpty || selected.contains('\u0000')) {
    throw ArgumentError.value(selected, 'directory', 'must identify a native directory');
  }
  final directory = await Directory(selected).absolute.create(recursive: true);
  return directory.resolveSymbolicLinks();
}

Future<String> _resolveDefaultStorage() async {
  final resolver = _defaultStorage;
  if (resolver == null) {
    throw UnsupportedError(
      'Plain Dart requires storage: VoxelStorage.directory(path). '
      'Flutter applications must register an application-support directory resolver.',
    );
  }
  return resolver();
}

Future<VoxelNativeResource> resolveVoxelNativeMainResource({
  required String databaseName,
  String? directory,
}) async {
  if (databaseName.isEmpty) {
    throw ArgumentError.value(databaseName, 'databaseName', 'must not be empty');
  }
  final parent = await resolveVoxelNativeStorageDirectory(directory);
  final encodedName = base64Url.encode(utf8.encode(databaseName)).replaceAll('=', '');
  final path = '$parent${Platform.pathSeparator}voxel-$encodedName.db';
  return VoxelNativeResource(path);
}

final class VoxelNativeResource {
  VoxelNativeResource(String path)
    : path = File(path).absolute.path,
      lockPath = '${File(path).absolute.path}.migration-lock';

  final String path;
  final String lockPath;
}

Future<TursoDatabase> openVoxelNativePersistentMain({
  required VoxelNativeResource resource,
  required VoxelMigrationPlan migrations,
  required Duration lockTimeout,
  TursoEncryption? encryption,
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
}) async {
  final lease = await VoxelNativeMigrationCoordinator.acquire(
    [resource],
    timeout: lockTimeout,
  );
  TursoDatabase? database;
  try {
    database = await TursoDatabase.open(
      TursoLocation.file(lease.paths.single),
      encryption: encryption,
    );
    await database.execute('PRAGMA foreign_keys=ON');
    await migrations.applyPersistentScope(
      database,
      scope: 'main',
      fileIdentity: 'main:${migrations.bundle.databaseId}',
      interrupt: interrupt,
    );
    final foreignKeys = (await database.query('PRAGMA foreign_keys')).rows.single.getInt(
      'foreign_keys',
    );
    if (foreignKeys != 1) {
      throw StateError('Voxel could not enable foreign-key enforcement.');
    }
    lease.release();
    return database;
  } on Object catch (error, stackTrace) {
    if (database != null) {
      try {
        await database.close();
      } on Object {
        // Preserve the initialization failure as the primary error.
      }
    }
    try {
      lease.release();
    } on Object {
      // Preserve the initialization failure as the primary error.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<TursoDatabase> openVoxelPersistentMain({
  required String databaseName,
  required String? directory,
  required VoxelMigrationPlan migrations,
  required Duration lockTimeout,
  required String? encryptionCipher,
  required Uint8List? encryptionKey,
}) async {
  final resource = await resolveVoxelNativeMainResource(
    databaseName: databaseName,
    directory: directory,
  );
  final encryption = encryptionCipher == null
      ? null
      : voxelNativeEncryption(cipher: encryptionCipher, key: encryptionKey!);
  return openVoxelNativePersistentMain(
    resource: resource,
    migrations: migrations,
    lockTimeout: lockTimeout,
    encryption: encryption,
  );
}

TursoEncryption voxelNativeEncryption({required String cipher, required Uint8List key}) {
  final tursoCipher = switch (cipher) {
    'aegis256' => TursoCipher.aegis256,
    'aes256gcm' => TursoCipher.aes256gcm,
    _ => throw UnsupportedError('Unsupported Voxel encryption cipher: $cipher.'),
  };
  return TursoEncryption(cipher: tursoCipher, key: key);
}

abstract interface class VoxelNativeLockHandle {
  void release();
}

typedef VoxelNativeTryLock = VoxelNativeLockHandle? Function(String path);

final class VoxelNativeMigrationLease {
  VoxelNativeMigrationLease._(this.paths, this._locks);

  final List<String> paths;
  final List<VoxelNativeLockHandle> _locks;
  var _released = false;

  void release() {
    if (_released) return;
    _released = true;
    Object? firstFailure;
    StackTrace? firstStackTrace;
    for (final lock in _locks.reversed) {
      try {
        lock.release();
      } on Object catch (error, stackTrace) {
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStackTrace!);
    }
  }
}

abstract final class VoxelNativeMigrationCoordinator {
  static Future<VoxelNativeMigrationLease> acquire(
    Iterable<VoxelNativeResource> resources, {
    required Duration timeout,
    VoxelNativeTryLock tryLock = _tryNativeLock,
  }) async {
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }
    final originalPaths = resources.map((resource) => resource.path).toList();
    final canonicalPaths = <String>[];
    for (final path in originalPaths) {
      canonicalPaths.add(_canonicalPersistentPath(path));
    }
    final keys = <String>{};
    for (final path in canonicalPaths) {
      final key = Platform.isWindows ? path.toLowerCase() : path;
      if (!keys.add(key)) {
        throw ArgumentError.value(
          originalPaths,
          'resources',
          'contains duplicate physical paths',
        );
      }
    }
    canonicalPaths.sort();

    final stopwatch = Stopwatch()..start();
    final locks = <VoxelNativeLockHandle>[];
    try {
      for (final path in canonicalPaths) {
        final lockPath = '$path.migration-lock';
        while (true) {
          final lock = tryLock(lockPath);
          if (lock != null) {
            locks.add(lock);
            break;
          }
          final remaining = timeout - stopwatch.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException(
              'Timed out acquiring Voxel migration coordination.',
              timeout,
            );
          }
          final pause = remaining < const Duration(milliseconds: 10)
              ? remaining
              : const Duration(milliseconds: 10);
          await Future<void>.delayed(pause);
        }
      }
      return VoxelNativeMigrationLease._(
        List.unmodifiable(canonicalPaths),
        List.unmodifiable(locks),
      );
    } on Object {
      for (final lock in locks.reversed) {
        try {
          lock.release();
        } on Object {
          // Preserve the acquisition failure.
        }
      }
      rethrow;
    }
  }
}

String _canonicalPersistentPath(String path) {
  final absolute = File(path).absolute;
  if (absolute.existsSync()) return absolute.resolveSymbolicLinksSync();
  final parent = absolute.parent..createSync(recursive: true);
  final canonicalParent = parent.resolveSymbolicLinksSync();
  return '$canonicalParent${Platform.pathSeparator}${absolute.uri.pathSegments.last}';
}

VoxelNativeLockHandle? _tryNativeLock(String path) {
  final lock = NativeMigrationLock.tryAcquire(path);
  return lock == null ? null : _NativeLockHandle(lock);
}

final class _NativeLockHandle implements VoxelNativeLockHandle {
  const _NativeLockHandle(this._lock);

  final NativeMigrationLock _lock;

  @override
  void release() => _lock.release();
}

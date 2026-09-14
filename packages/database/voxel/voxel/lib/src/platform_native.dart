// Platform selection helpers are internal to the Voxel connection owner.
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

List<VoxelNativeResource> uniqueVoxelNativeMigrationResources(
  Iterable<VoxelNativeResource> resources,
) {
  final byPath = <String, VoxelNativeResource>{};
  for (final resource in resources) {
    final canonical = _canonicalPersistentPath(resource.path);
    byPath.putIfAbsent(_pathKey(canonical), () => VoxelNativeResource(canonical));
  }
  return List.unmodifiable(byPath.values);
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

Future<TursoDatabase> openVoxelPersistentDatabase({
  required String databaseName,
  required String? directory,
  required VoxelMigrationPlan migrations,
  required Duration lockTimeout,
  required String? encryptionCipher,
  required Uint8List? encryptionKey,
  required Map<String, String?> schemaDirectories,
  required Map<String, String?> schemaEncryptionCiphers,
  required Map<String, Uint8List?> schemaEncryptionKeys,
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
}) async {
  final deadline = VoxelNativeMigrationDeadline(lockTimeout);
  final main = await resolveVoxelNativeMainResource(
    databaseName: databaseName,
    directory: directory,
  );
  final mainDirectory = File(main.path).parent.path;
  final attachments = <String, _PlannedAttachment>{};
  for (final scope in migrations.scopes.where((scope) => scope.name != 'main')) {
    final selectedDirectory = schemaDirectories[scope.name];
    final parent = selectedDirectory == null
        ? mainDirectory
        : await resolveVoxelNativeStorageDirectory(selectedDirectory);
    final resource = resolveVoxelNativeAttachmentResource(
      databaseName: databaseName,
      schemaId: scope.id,
      directory: parent,
    );
    attachments[scope.name] = _PlannedAttachment(
      scope: scope,
      resource: resource,
      encryption: _optionalEncryption(
        schemaEncryptionCiphers[scope.name],
        schemaEncryptionKeys[scope.name],
      ),
    );
  }
  final plannedResources = uniqueVoxelNativeMigrationResources([
    main,
    ...attachments.values.map((entry) => entry.resource),
  ]);
  var lease = await VoxelNativeMigrationCoordinator.acquire(
    plannedResources,
    timeout: lockTimeout,
    deadline: deadline,
  );
  TursoDatabase? database;
  late String mainFileIdentity;
  try {
    final mainExisted = File(main.path).existsSync();
    final knownAttachmentPaths = <String>{
      for (final attachment in attachments.values) attachment.resource.path,
      for (final scope in migrations.scopes.where((scope) => scope.name != 'main'))
        resolveVoxelNativeAttachmentResource(
          databaseName: databaseName,
          schemaId: scope.id,
          directory: mainDirectory,
        ).path,
    };
    if (!mainExisted && knownAttachmentPaths.any((path) => File(path).existsSync())) {
      throw const FormatException(
        'The Voxel main file is missing while known attachment paths still exist.',
      );
    }
    database = await _openMain(
      lease.paths.firstWhere((path) => _samePath(path, main.path)),
      _optionalEncryption(encryptionCipher, encryptionKey),
    );
    mainFileIdentity = await _resolveMainFileIdentity(
      database,
      databaseId: migrations.bundle.databaseId,
      existedBeforeOpen: mainExisted,
    );
    await migrations.bootstrapPersistentScope(
      database,
      scope: 'main',
      schemaId: migrations.mainSchemaId,
      fileIdentity: mainFileIdentity,
    );
    await database.execute(
      '''
UPDATE main._voxel_files
SET location_identity = ?, state = 'initialized'
WHERE schema_id = ?
''',
      parameters: [_canonicalPersistentPath(main.path), migrations.mainSchemaId],
    );

    var registry = await _readRegistry(database);
    final discovered = registry.values
        .where((entry) => entry.schemaId != migrations.mainSchemaId)
        .map((entry) => VoxelNativeResource(entry.locationIdentity))
        .toList();
    final currentKeys = lease.paths.map(_pathKey).toSet();
    final completeResources = uniqueVoxelNativeMigrationResources([
      ...plannedResources,
      ...discovered,
    ]);
    final completeKeys = completeResources
        .map((entry) => _pathKey(_canonicalPersistentPath(entry.path)))
        .toSet();
    if (!currentKeys.containsAll(completeKeys)) {
      await database.close();
      database = null;
      lease.release();
      lease = await VoxelNativeMigrationCoordinator.acquire(
        completeResources,
        timeout: lockTimeout,
        deadline: deadline,
      );
      database = await _openMain(
        lease.paths.firstWhere((path) => _samePath(path, main.path)),
        _optionalEncryption(encryptionCipher, encryptionKey),
      );
      await migrations.bootstrapPersistentScope(
        database,
        scope: 'main',
        schemaId: migrations.mainSchemaId,
        fileIdentity: mainFileIdentity,
      );
      registry = await _readRegistry(database);
    }

    final fileIdentities = <String, String>{
      'main': mainFileIdentity,
    };
    for (final attachment in attachments.values) {
      final target = _canonicalPersistentPath(attachment.resource.path);
      var registered = registry[attachment.scope.id];
      if (registered == null) {
        if (File(target).existsSync()) {
          throw FormatException(
            'Schema `${attachment.scope.name}` has an unregistered preexisting file.',
          );
        }
        final fileIdentity = _newFileIdentity();
        await database.execute(
          '''
INSERT INTO main._voxel_files
  (schema_id, file_identity, location_identity, introduced_migration_id,
   introduced_phase_id, state)
VALUES (?, ?, ?, ?, ?, 'prepared')
''',
          parameters: [
            attachment.scope.id,
            fileIdentity,
            target,
            attachment.scope.introducedMigrationId,
            attachment.scope.introducedPhaseId,
          ],
        );
        registered = _RegisteredFile(
          schemaId: attachment.scope.id,
          fileIdentity: fileIdentity,
          locationIdentity: target,
          state: 'prepared',
        );
        await interrupt?.call(
          VoxelMigrationInterruption(
            point: VoxelMigrationInterruptionPoint.afterCreationPrepared,
            migrationId: attachment.scope.introducedMigrationId,
            phaseId: attachment.scope.introducedPhaseId,
          ),
        );
      }

      if (registered.locationIdentity != target) {
        if (registered.state != 'initialized' ||
            File(registered.locationIdentity).existsSync() ||
            !File(target).existsSync()) {
          throw FormatException(
            'Schema `${attachment.scope.name}` storage changed without a valid relocation.',
          );
        }
      } else if (registered.state == 'initialized' && !File(target).existsSync()) {
        throw FormatException('Schema `${attachment.scope.name}` is missing its initialized file.');
      }

      await _attach(database, attachment.scope.name, target, attachment.encryption);
      if (registered.state == 'initialized') {
        await _verifyAttachedIdentity(
          database,
          scope: attachment.scope.name,
          databaseId: migrations.bundle.databaseId,
          schemaId: attachment.scope.id,
          fileIdentity: registered.fileIdentity,
        );
      } else if (registered.state == 'prepared') {
        final objects = (await database.query(
          '''
SELECT name
FROM ${_quoteIdentifier(attachment.scope.name)}.sqlite_master
WHERE name NOT LIKE 'sqlite_%'
''',
        )).rows;
        final hasIdentity = objects.any(
          (row) => row.getString('name') == '_voxel_identity',
        );
        if (!hasIdentity && objects.isNotEmpty) {
          throw FormatException(
            'Schema `${attachment.scope.name}` prepared path contains an unrelated file.',
          );
        }
      }
      await migrations.bootstrapPersistentScope(
        database,
        scope: attachment.scope.name,
        schemaId: attachment.scope.id,
        fileIdentity: registered.fileIdentity,
      );
      await interrupt?.call(
        VoxelMigrationInterruption(
          point: VoxelMigrationInterruptionPoint.afterFileBootstrap,
          migrationId: attachment.scope.introducedMigrationId,
          phaseId: attachment.scope.introducedPhaseId,
        ),
      );
      await database.execute(
        '''
UPDATE main._voxel_files
SET location_identity = ?, state = 'initialized'
WHERE schema_id = ? AND file_identity = ?
''',
        parameters: [target, attachment.scope.id, registered.fileIdentity],
      );
      await interrupt?.call(
        VoxelMigrationInterruption(
          point: VoxelMigrationInterruptionPoint.afterRegistryInitialized,
          migrationId: attachment.scope.introducedMigrationId,
          phaseId: attachment.scope.introducedPhaseId,
        ),
      );
      fileIdentities[attachment.scope.name] = registered.fileIdentity;
    }

    await database.execute('PRAGMA foreign_keys=ON');
    await migrations.applyPersistentScopes(
      database,
      fileIdentities: fileIdentities,
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
        // Preserve the initialization or recovery failure.
      }
    }
    try {
      lease.release();
    } on Object {
      // Preserve the initialization or recovery failure.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<T?> withVoxelPersistentMaintenance<T>({
  required String databaseName,
  required String? directory,
  required VoxelMigrationPlan migrations,
  required Duration lockTimeout,
  required String? encryptionCipher,
  required Uint8List? encryptionKey,
  required Map<String, String?> schemaDirectories,
  required Map<String, String?> schemaEncryptionCiphers,
  required Map<String, Uint8List?> schemaEncryptionKeys,
  required bool allowMissingAttachments,
  required Future<T> Function(
    TursoDatabase database,
    Set<String> availableScopes,
    Set<String> uncertainScopes,
  )
  operation,
}) async {
  final selected = directory ?? await _resolveDefaultStorage();
  final parent = Directory(selected).absolute;
  if (!parent.existsSync()) return null;
  final canonicalParent = parent.resolveSymbolicLinksSync();
  final encodedName = base64Url.encode(utf8.encode(databaseName)).replaceAll('=', '');
  final main = VoxelNativeResource(
    '$canonicalParent${Platform.pathSeparator}voxel-$encodedName.db',
  );
  if (!File(main.path).existsSync()) return null;
  final attachments = <String, _PlannedAttachment>{};
  for (final scope in migrations.scopes.where((entry) => entry.name != 'main')) {
    final selectedDirectory = schemaDirectories[scope.name];
    final attachmentParent = selectedDirectory == null
        ? canonicalParent
        : Directory(selectedDirectory).absolute.path;
    final resource = resolveVoxelNativeAttachmentResource(
      databaseName: databaseName,
      schemaId: scope.id,
      directory: attachmentParent,
    );
    attachments[scope.name] = _PlannedAttachment(
      scope: scope,
      resource: resource,
      encryption: _optionalEncryption(
        schemaEncryptionCiphers[scope.name],
        schemaEncryptionKeys[scope.name],
      ),
    );
  }
  final resources = [main, ...attachments.values.map((entry) => entry.resource)];
  final lease = await VoxelNativeMigrationCoordinator.acquire(resources, timeout: lockTimeout);
  TursoDatabase? database;
  try {
    if (!File(main.path).existsSync()) return null;
    database = await _openMain(
      main.path,
      _optionalEncryption(encryptionCipher, encryptionKey),
    );
    final registry = await _readRegistry(database);
    final availableScopes = <String>{'main'};
    final uncertainScopes = <String>{};
    for (final attachment in attachments.values) {
      final registered = registry[attachment.scope.id];
      if (registered == null ||
          (registered.state == 'prepared' && !File(attachment.resource.path).existsSync())) {
        if (allowMissingAttachments) continue;
        throw FormatException(
          'Schema `${attachment.scope.name}` has no initialized persistent file.',
        );
      }
      if (!_samePath(registered.locationIdentity, attachment.resource.path) ||
          !File(attachment.resource.path).existsSync()) {
        if (allowMissingAttachments && registered.state == 'initialized') {
          uncertainScopes.add(attachment.scope.name);
          continue;
        }
        throw FormatException(
          'Schema `${attachment.scope.name}` is missing or configured at another location.',
        );
      }
      await _attach(
        database,
        attachment.scope.name,
        attachment.resource.path,
        attachment.encryption,
      );
      await _verifyAttachedIdentity(
        database,
        scope: attachment.scope.name,
        databaseId: migrations.bundle.databaseId,
        schemaId: attachment.scope.id,
        fileIdentity: registered.fileIdentity,
      );
      availableScopes.add(attachment.scope.name);
    }
    return await operation(database, availableScopes, uncertainScopes);
  } finally {
    await database?.close();
    lease.release();
  }
}

Future<String> _resolveMainFileIdentity(
  TursoDatabase database, {
  required String databaseId,
  required bool existedBeforeOpen,
}) async {
  if (!existedBeforeOpen) return _newFileIdentity();
  final objects = (await database.query(
    "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
  )).rows;
  if (objects.isEmpty) return _newFileIdentity();
  if (!objects.any((row) => row.getString('name') == '_voxel_identity')) {
    throw const FormatException('The Voxel main path contains an unrelated database.');
  }
  try {
    final identity = (await database.query(
      'SELECT database_id, file_identity FROM main._voxel_identity',
    )).rows.single;
    if (identity.getString('database_id') != databaseId) {
      throw const FormatException('The Voxel main file has a different database identity.');
    }
    return identity.getString('file_identity');
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException('The Voxel main file has incomplete identity metadata.');
  }
}

Future<void> _verifyAttachedIdentity(
  TursoDatabase database, {
  required String scope,
  required String databaseId,
  required String schemaId,
  required String fileIdentity,
}) async {
  try {
    final identity = (await database.query(
      'SELECT database_id, schema_id, file_identity '
      'FROM ${_quoteIdentifier(scope)}._voxel_identity',
    )).rows.single;
    final bootstrap = (await database.query(
      'SELECT database_id, schema_id, file_identity, status '
      'FROM ${_quoteIdentifier(scope)}._voxel_file_bootstrap',
    )).rows.single;
    if (identity.getString('database_id') != databaseId ||
        identity.getString('schema_id') != schemaId ||
        identity.getString('file_identity') != fileIdentity ||
        bootstrap.getString('database_id') != databaseId ||
        bootstrap.getString('schema_id') != schemaId ||
        bootstrap.getString('file_identity') != fileIdentity ||
        bootstrap.getString('status') != 'completed') {
      throw const FormatException('Attached Voxel file identity does not match its registry.');
    }
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException(
      'Initialized Voxel attachment is missing its identity or bootstrap receipt.',
    );
  }
}

VoxelNativeResource resolveVoxelNativeAttachmentResource({
  required String databaseName,
  required String schemaId,
  required String directory,
}) {
  final encodedDatabase = base64Url.encode(utf8.encode(databaseName)).replaceAll('=', '');
  return VoxelNativeResource(
    '$directory${Platform.pathSeparator}voxel-$encodedDatabase-schema-$schemaId.db',
  );
}

TursoEncryption? _optionalEncryption(String? cipher, Uint8List? key) {
  if (cipher == null) return null;
  if (key == null) throw ArgumentError('Encryption key is required.', 'key');
  return voxelNativeEncryption(cipher: cipher, key: key);
}

Future<TursoDatabase> _openMain(String path, TursoEncryption? encryption) async {
  return TursoDatabase.open(TursoLocation.file(path), encryption: encryption);
}

Future<void> _attach(
  TursoDatabase database,
  String scope,
  String path,
  TursoEncryption? encryption,
) async {
  final location = encryption == null ? path : _encryptedAttachmentUri(path, encryption);
  try {
    await database.execute(
      'ATTACH DATABASE ? AS ${_quoteIdentifier(scope)}',
      parameters: [location],
    );
  } on Object {
    throw StateError('Could not attach Voxel schema `$scope` with its configured storage.');
  }
}

String _encryptedAttachmentUri(String path, TursoEncryption encryption) {
  final cipher = encryption.cipher.name;
  final key = encryption.key.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${Uri.file(path)}?mode=rwc&cipher=$cipher&hexkey=$key';
}

Future<Map<String, _RegisteredFile>> _readRegistry(TursoDatabase database) async {
  final rows = (await database.query(
    '''
SELECT schema_id, file_identity, location_identity, state
FROM main._voxel_files
''',
  )).rows;
  final registry = <String, _RegisteredFile>{};
  for (final row in rows) {
    final schemaId = row.getString('schema_id');
    final fileIdentity = row.getString('file_identity');
    final locationIdentity = row.getString('location_identity');
    final state = row.getString('state');
    if (schemaId.isEmpty ||
        fileIdentity.isEmpty ||
        locationIdentity.isEmpty ||
        (state != 'prepared' && state != 'initialized')) {
      throw const FormatException('The Voxel file registry contains invalid state.');
    }
    registry[schemaId] = _RegisteredFile(
      schemaId: schemaId,
      fileIdentity: fileIdentity,
      locationIdentity: locationIdentity,
      state: state,
    );
  }
  return registry;
}

String _newFileIdentity() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String _quoteIdentifier(String identifier) => '"${identifier.replaceAll('"', '""')}"';

String _pathKey(String path) => Platform.isWindows ? path.toLowerCase() : path;

bool _samePath(String left, String right) =>
    _pathKey(_canonicalPersistentPath(left)) == _pathKey(_canonicalPersistentPath(right));

final class _PlannedAttachment {
  const _PlannedAttachment({
    required this.scope,
    required this.resource,
    required this.encryption,
  });

  final VoxelMigrationScope scope;
  final VoxelNativeResource resource;
  final TursoEncryption? encryption;
}

final class _RegisteredFile {
  const _RegisteredFile({
    required this.schemaId,
    required this.fileIdentity,
    required this.locationIdentity,
    required this.state,
  });

  final String schemaId;
  final String fileIdentity;
  final String locationIdentity;
  final String state;
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

final class VoxelNativeMigrationDeadline {
  VoxelNativeMigrationDeadline(this.timeout) : _stopwatch = Stopwatch()..start() {
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }
  }

  final Duration timeout;
  final Stopwatch _stopwatch;
  var _setsStarted = 0;

  Duration get remaining => timeout - _stopwatch.elapsed;

  bool beginSet() => _setsStarted++ == 0;
}

abstract final class VoxelNativeMigrationCoordinator {
  static Future<VoxelNativeMigrationLease> acquire(
    Iterable<VoxelNativeResource> resources, {
    required Duration timeout,
    VoxelNativeMigrationDeadline? deadline,
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

    final acquisitionDeadline = deadline ?? VoxelNativeMigrationDeadline(timeout);
    final isFirstSet = acquisitionDeadline.beginSet();
    if (!isFirstSet && acquisitionDeadline.remaining <= Duration.zero) {
      throw TimeoutException(
        'Timed out reacquiring Voxel migration coordination.',
        acquisitionDeadline.timeout,
      );
    }
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
          final remaining = acquisitionDeadline.remaining;
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

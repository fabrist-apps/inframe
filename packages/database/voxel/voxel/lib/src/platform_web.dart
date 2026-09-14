// Platform selection helpers are internal to the Voxel connection owner.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:turso/turso.dart';

import 'package:voxel/src/migration.dart';
import 'package:voxel/src/web_migration_lock.dart';

const voxelPlatform = 'browser';

TursoWebOptions voxelWebOptions() => TursoWebOptions(
  moduleUri: Uri.parse('turso/turso_bridge.js'),
);

void registerVoxelNativeDefaultStorage(Future<String> Function() resolver) {
  throw UnsupportedError('Native default storage is unavailable in browsers.');
}

Future<TursoDatabase> openVoxelPersistentMain({
  required String databaseName,
  required String? directory,
  required VoxelMigrationPlan migrations,
  required Duration lockTimeout,
  required String? encryptionCipher,
  required Object? encryptionKey,
}) => openVoxelPersistentDatabase(
  databaseName: databaseName,
  directory: directory,
  migrations: migrations,
  lockTimeout: lockTimeout,
  encryptionCipher: encryptionCipher,
  encryptionKey: encryptionKey as Uint8List?,
  schemaDirectories: const {},
  schemaEncryptionCiphers: const {},
  schemaEncryptionKeys: const {},
);

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
  final options = voxelWebOptions();
  final deadline = VoxelWebMigrationDeadline.start(lockTimeout);
  final coordinator = VoxelWebMigrationCoordinator(
    requester: createVoxelBrowserLockRequester(),
    lockName: (path) => voxelWebMigrationLockName(_browserOrigin, path),
  );
  final main = resolveVoxelWebMainResource(
    databaseName: databaseName,
    directory: directory,
  );
  final mainDirectory = main.parentDirectory;
  final attachments = <String, _PlannedAttachment>{};
  for (final scope in migrations.scopes.where((scope) => scope.name != 'main')) {
    final resource = resolveVoxelWebAttachmentResource(
      databaseName: databaseName,
      schemaId: scope.id,
      directory: schemaDirectories[scope.name] ?? mainDirectory,
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

  final plannedPaths = [main.path, ...attachments.values.map((entry) => entry.resource.path)];
  var lease = await coordinator.acquire(plannedPaths, deadline);
  TursoDatabase? database;
  late String mainFileIdentity;
  try {
    final mainExisted = await _exists(main, options);
    final knownAttachmentPaths = <String>{
      for (final attachment in attachments.values) attachment.resource.path,
      for (final scope in migrations.scopes.where((scope) => scope.name != 'main'))
        resolveVoxelWebAttachmentResource(
          databaseName: databaseName,
          schemaId: scope.id,
          directory: mainDirectory,
        ).path,
    };
    if (!mainExisted && await _anyExists(knownAttachmentPaths, options)) {
      throw const FormatException(
        'The Voxel main file is missing while known attachment paths still exist.',
      );
    }
    database = await _openMain(
      main.path,
      _optionalEncryption(encryptionCipher, encryptionKey),
      options,
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
      parameters: [main.path, migrations.mainSchemaId],
    );

    var registry = await _readRegistry(database);
    final discoveredPaths = registry.values
        .where((entry) => entry.schemaId != migrations.mainSchemaId)
        .map((entry) => _canonicalRegisteredPath(entry.locationIdentity))
        .toList();
    final completePaths = {...plannedPaths, ...discoveredPaths}.toList();
    if (!lease.paths.toSet().containsAll(completePaths)) {
      await database.close();
      database = null;
      await lease.release();
      lease = await coordinator.acquire(completePaths, deadline);
      database = await _openMain(
        main.path,
        _optionalEncryption(encryptionCipher, encryptionKey),
        options,
      );
      await migrations.bootstrapPersistentScope(
        database,
        scope: 'main',
        schemaId: migrations.mainSchemaId,
        fileIdentity: mainFileIdentity,
      );
      registry = await _readRegistry(database);
    }

    final fileIdentities = <String, String>{'main': mainFileIdentity};
    for (final attachment in attachments.values) {
      final target = attachment.resource.path;
      var registered = registry[attachment.scope.id];
      if (registered == null) {
        if (await _exists(attachment.resource, options)) {
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

      final registeredPath = _canonicalRegisteredPath(registered.locationIdentity);
      final registeredExists = await TursoDatabase.browserFileExists(
        TursoBrowserLocation(registeredPath),
        web: options,
      );
      final targetExists = registeredPath == target
          ? registeredExists
          : await _exists(attachment.resource, options);
      if (registeredPath != target) {
        if (registered.state != 'initialized' || registeredExists || !targetExists) {
          throw FormatException(
            'Schema `${attachment.scope.name}` storage changed without a valid relocation.',
          );
        }
      } else if (registered.state == 'initialized' && !targetExists) {
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
        final hasIdentity = objects.any((row) => row.getString('name') == '_voxel_identity');
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
    await lease.release();
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
      await lease.release();
    } on Object {
      // Preserve the initialization or recovery failure.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

final class VoxelWebResource {
  VoxelWebResource(String path) : path = TursoBrowserLocation(path).path {
    if (this.path != path) {
      throw ArgumentError.value(path, 'path', 'must already be a normalized OPFS path');
    }
  }

  final String path;

  String? get parentDirectory {
    final separator = path.lastIndexOf('/');
    return separator == -1 ? null : path.substring(0, separator);
  }
}

VoxelWebResource resolveVoxelWebMainResource({
  required String databaseName,
  String? directory,
}) {
  if (databaseName.isEmpty) {
    throw ArgumentError.value(databaseName, 'databaseName', 'must not be empty');
  }
  return VoxelWebResource(_inDirectory(directory, 'voxel-${_encodeName(databaseName)}.db'));
}

VoxelWebResource resolveVoxelWebAttachmentResource({
  required String databaseName,
  required String schemaId,
  String? directory,
}) => VoxelWebResource(
  _inDirectory(directory, 'voxel-${_encodeName(databaseName)}-schema-$schemaId.db'),
);

String _inDirectory(String? directory, String fileName) {
  if (directory == null) return fileName;
  if (directory.isEmpty) {
    throw ArgumentError.value(directory, 'directory', 'must not be empty');
  }
  return '$directory/$fileName';
}

String _encodeName(String value) => base64Url.encode(utf8.encode(value)).replaceAll('=', '');

String _canonicalRegisteredPath(String path) {
  final canonical = TursoBrowserLocation(path).path;
  if (canonical != path) {
    throw const FormatException('The Voxel file registry contains a non-canonical OPFS path.');
  }
  return canonical;
}

Future<bool> _exists(VoxelWebResource resource, TursoWebOptions options) =>
    TursoDatabase.browserFileExists(TursoBrowserLocation(resource.path), web: options);

Future<bool> _anyExists(Iterable<String> paths, TursoWebOptions options) async {
  for (final path in paths) {
    if (await TursoDatabase.browserFileExists(TursoBrowserLocation(path), web: options)) {
      return true;
    }
  }
  return false;
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

TursoEncryption? _optionalEncryption(String? cipher, Uint8List? key) {
  if (cipher == null) return null;
  if (key == null) throw ArgumentError('Encryption key is required.', 'key');
  final tursoCipher = switch (cipher) {
    'aegis256' => TursoCipher.aegis256,
    'aes256gcm' => TursoCipher.aes256gcm,
    _ => throw UnsupportedError('Unsupported Voxel encryption cipher: $cipher.'),
  };
  return TursoEncryption(cipher: tursoCipher, key: key);
}

Future<TursoDatabase> _openMain(
  String path,
  TursoEncryption? encryption,
  TursoWebOptions options,
) => TursoDatabase.open(
  TursoLocation.browser(path),
  encryption: encryption,
  web: options,
);

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
  return 'file:${Uri.encodeComponent(path)}?mode=rwc&cipher=$cipher&hexkey=$key';
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

final class _PlannedAttachment {
  const _PlannedAttachment({
    required this.scope,
    required this.resource,
    required this.encryption,
  });

  final VoxelMigrationScope scope;
  final VoxelWebResource resource;
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

@JS('location.origin')
external String get _browserOrigin;

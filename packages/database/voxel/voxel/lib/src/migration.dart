// Runtime plan internals are reached only through generated database open code.
// ignore_for_file: prefer_constructors_over_static_methods, public_member_api_docs

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:turso/turso.dart';

import 'package:voxel/src/platform.dart';
import 'package:voxel/src/schema.dart';

/// Checked migration history embedded in generated application code.
final class VoxelMigrationBundle {
  /// Creates a bundle in journal order.
  const VoxelMigrationBundle({
    required this.databaseId,
    required this.migrations,
  });

  /// Stable identity shared by every migration artifact in this history.
  final String databaseId;

  /// Checked artifacts in their explicit journal order.
  final List<VoxelBundledMigration> migrations;
}

/// One checked migration and its exact source artifacts.
final class VoxelBundledMigration {
  /// Creates an immutable generated migration record.
  const VoxelBundledMigration({
    required this.directory,
    required this.sql,
    required this.metadata,
    required this.snapshot,
  });

  /// Source directory recorded by the journal.
  final String directory;

  /// Exact UTF-8 migration SQL after review and sealing.
  final String sql;

  /// Complete `migration.json`, including phases and integrity metadata.
  final Map<String, Object?> metadata;

  /// Complete resulting `snapshot.json`.
  final Map<String, Object?> snapshot;

  /// Stable migration identity.
  String get id => metadata['id']! as String;

  /// Stable parent identity, or null for the first migration.
  String? get parentId => metadata['parentId'] as String?;

  /// Integrity checksum covering this record's source artifacts.
  String get checksum => metadata['checksum']! as String;
}

/// A resource-free, validated execution plan for one bundled history.
final class VoxelMigrationPlan {
  VoxelMigrationPlan._(this.bundle, this.schemaNames, this._scopeNames);

  final VoxelMigrationBundle bundle;
  final List<String> schemaNames;
  final List<Map<String, String>> _scopeNames;

  /// Validates every artifact before a database connection is acquired.
  static VoxelMigrationPlan validate({
    required VoxelDatabaseSchema schema,
    required VoxelMigrationBundle bundle,
  }) {
    _id(bundle.databaseId, 'bundle databaseId');
    if (bundle.migrations.isEmpty) {
      throw const FormatException('A Voxel migration bundle must not be empty.');
    }
    final registeredSchemas = schema.tables
        .map((table) => table.schemaName)
        .where((name) => name.isNotEmpty)
        .toSet();
    final scopesByMigration = <Map<String, String>>[];
    String? parentId;
    final migrationIds = <String>{};
    for (final (ordinal, migration) in bundle.migrations.indexed) {
      final metadata = migration.metadata;
      final snapshot = migration.snapshot;
      _record(
        metadata,
        'migration metadata',
        const {
          'formatVersion',
          'dialect',
          'databaseId',
          'id',
          'parentId',
          'checksum',
          'phases',
        },
      );
      _record(
        snapshot,
        'migration snapshot',
        const {
          'formatVersion',
          'dialect',
          'databaseId',
          'migrationId',
          'schemas',
          'tables',
          'enums',
          'requirements',
        },
      );
      if (metadata['formatVersion'] != 1 ||
          snapshot['formatVersion'] != 1 ||
          metadata['dialect'] != 'voxel' ||
          snapshot['dialect'] != 'voxel') {
        throw const FormatException('Voxel migration artifacts use an unsupported format.');
      }
      if (_list(snapshot['requirements'], 'snapshot requirements').isNotEmpty) {
        throw UnsupportedError(
          'This Voxel runtime does not support migration capability requirements yet.',
        );
      }
      final migrationId = _id(metadata['id'], 'migration id');
      if (!migrationIds.add(migrationId)) {
        throw FormatException('Duplicate migration ID `$migrationId`.');
      }
      if (metadata['databaseId'] != bundle.databaseId ||
          snapshot['databaseId'] != bundle.databaseId ||
          snapshot['migrationId'] != migrationId) {
        throw FormatException('Migration $migrationId has inconsistent artifact identities.');
      }
      if (metadata['parentId'] != parentId) {
        throw FormatException('Migration $migrationId has a broken parent chain.');
      }
      final expectedDirectoryPrefix = ordinal.toString().padLeft(4, '0');
      if (!migration.directory.startsWith('${expectedDirectoryPrefix}_') ||
          !migration.directory.endsWith('_$migrationId') ||
          migration.directory.contains('/') ||
          migration.directory.contains(r'\')) {
        throw FormatException('Migration $migrationId has an invalid journal directory.');
      }
      final checksum = _migrationChecksum(migration);
      if (metadata['checksum'] != checksum) {
        throw FormatException('Migration $migrationId checksum does not match its artifacts.');
      }

      final scopeNames = <String, String>{};
      for (final rawSchema in _list(snapshot['schemas'], 'snapshot schemas')) {
        final schemaEntry = _map(rawSchema, 'snapshot schema');
        final scopeId = _id(schemaEntry['id'], 'schema id');
        final name = schemaEntry['name'];
        if (name is! String || name.isEmpty || !registeredSchemas.contains(name)) {
          throw FormatException('Migration $migrationId references unknown schema `$name`.');
        }
        if (scopeNames[scopeId] != null || scopeNames.containsValue(name)) {
          throw FormatException('Migration $migrationId has duplicate schema identities.');
        }
        scopeNames[scopeId] = name;
      }
      _validatePhases(migration, scopeNames);
      scopesByMigration.add(Map.unmodifiable(scopeNames));
      parentId = migrationId;
    }
    final finalSchemas = scopesByMigration.last.values.toSet();
    if (!finalSchemas.containsAll(registeredSchemas) ||
        !registeredSchemas.containsAll(finalSchemas)) {
      throw const FormatException(
        'The final migration snapshot does not match the registered schema attachments.',
      );
    }
    return VoxelMigrationPlan._(
      bundle,
      (registeredSchemas.toList()..sort()).toList(growable: false),
      scopesByMigration,
    );
  }

  Future<void> apply(TursoDatabase database) async {
    for (final schemaName in schemaNames) {
      final scopeId = _scopeNames.last.entries
          .singleWhere(
            (entry) => entry.value == schemaName,
          )
          .key;
      await _bootstrap(database, schemaName, bundle.databaseId, scopeId);
    }
    for (final (migrationIndex, migration) in bundle.migrations.indexed) {
      final phases = _list(migration.metadata['phases'], 'migration phases');
      for (final rawPhase in phases) {
        final phase = _map(rawPhase, 'migration phase');
        final platforms = _list(phase['platforms'], 'phase platforms').cast<String>();
        if (!platforms.contains(voxelPlatform)) continue;
        if (phase['mode'] != 'transactional') {
          throw UnsupportedError(
            'Voxel memory bootstrap does not support ${phase['mode']} migration phases.',
          );
        }
        final scope = _scopeNames[migrationIndex][phase['scopeId']]!;
        if (await _phaseCompleted(database, scope, migration, phase)) continue;
        final rebuild = phase['rebuild'] as Map<String, Object?>?;
        if (rebuild != null) await database.execute('PRAGMA foreign_keys=OFF');
        Object? primaryFailure;
        StackTrace? primaryStackTrace;
        try {
          await database.transaction<void>((transaction) async {
            for (final rawRange in _list(phase['statements'], 'phase statements')) {
              final range = _map(rawRange, 'statement range');
              await transaction.execute(
                utf8.decode(
                  utf8
                      .encode(migration.sql)
                      .sublist(
                        range['startByte']! as int,
                        range['endByte']! as int,
                      ),
                ),
              );
            }
            if (rebuild != null) {
              for (final rawValidation in _list(
                rebuild['validations'],
                'rebuild validations',
              )) {
                final validation = _map(rawValidation, 'rebuild validation');
                final row = (await transaction.query(validation['sql']! as String)).rows.single;
                if (row.getInt('valid') != 1) {
                  throw StateError(
                    'Migration ${migration.id} phase ${phase['id']} failed validation.',
                  );
                }
              }
            }
            await transaction.execute(
              '''
INSERT INTO ${_qualified(scope, '_voxel_migrations')}
  (migration_id, parent_id, checksum, ordinal)
VALUES (?, ?, ?, ?)
ON CONFLICT (migration_id) DO NOTHING
''',
              parameters: [migration.id, migration.parentId, migration.checksum, migrationIndex],
            );
            await transaction.execute(
              '''
INSERT INTO ${_qualified(scope, '_voxel_phases')}
  (migration_id, phase_id, checksum, platform, status)
VALUES (?, ?, ?, ?, 'completed')
''',
              parameters: [
                migration.id,
                phase['id'],
                migration.checksum,
                voxelPlatform,
              ],
            );
          });
        } on Object catch (error, stackTrace) {
          primaryFailure = error;
          primaryStackTrace = stackTrace;
        }
        if (rebuild != null) {
          try {
            await database.execute('PRAGMA foreign_keys=ON');
          } on Object {
            if (primaryFailure == null) rethrow;
          }
        }
        if (primaryFailure != null) {
          Error.throwWithStackTrace(primaryFailure, primaryStackTrace!);
        }
      }
    }
  }

  /// Applies one persistent physical scope with durable attempt and completion
  /// receipts in that same file.
  Future<void> applyPersistentScope(
    TursoDatabase database, {
    required String scope,
    required String fileIdentity,
    Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
  }) async {
    final schemaId = scope == 'main'
        ? 'main'
        : _scopeNames.last.entries
              .singleWhere(
                (entry) => entry.value == scope,
                orElse: () => throw ArgumentError.value(
                  scope,
                  'scope',
                  'is not registered by the migration bundle',
                ),
              )
              .key;
    await _bootstrapPersistent(
      database,
      scope,
      bundle.databaseId,
      schemaId,
      fileIdentity,
    );
    final scopedMigrations =
        <
          ({
            int ordinal,
            VoxelBundledMigration migration,
            List<Map<String, Object?>> phases,
          })
        >[];
    for (final (ordinal, migration) in bundle.migrations.indexed) {
      final phases = <Map<String, Object?>>[];
      for (final rawPhase in _list(migration.metadata['phases'], 'migration phases')) {
        final phase = _map(rawPhase, 'migration phase');
        if (!(phase['platforms']! as List<Object?>).contains(voxelPlatform)) continue;
        if (_scopeNames[ordinal][phase['scopeId']] == scope) phases.add(phase);
      }
      if (phases.isNotEmpty) {
        scopedMigrations.add((ordinal: ordinal, migration: migration, phases: phases));
      }
    }
    await _validatePersistentHistory(database, scope, scopedMigrations);
    for (final entry in scopedMigrations) {
      for (final phase in entry.phases) {
        await _applyPersistentPhase(
          database,
          scope,
          entry.ordinal,
          entry.migration,
          phase,
          interrupt,
        );
      }
    }
  }
}

enum VoxelMigrationInterruptionPoint { beforePhaseCommit, afterPhaseCommit }

final class VoxelMigrationInterruption {
  const VoxelMigrationInterruption({
    required this.point,
    required this.migrationId,
    required this.phaseId,
  });

  final VoxelMigrationInterruptionPoint point;
  final String migrationId;
  final String phaseId;
}

void _validatePhases(VoxelBundledMigration migration, Map<String, String> scopes) {
  final parsedRanges = _parseSqlStatements(migration.sql);
  final bytes = utf8.encode(migration.sql);
  final covered = <({int start, int end})>[];
  final phaseIds = <String>{};
  for (final (phaseIndex, rawPhase) in _list(
    migration.metadata['phases'],
    'migration phases',
  ).indexed) {
    final phase = _map(rawPhase, 'migration phase');
    _record(
      phase,
      'migration phase',
      const {'id', 'scopeId', 'mode', 'platforms', 'statements', 'recovery'},
      optional: const {'rebuild'},
    );
    final phaseId = phase['id'];
    if (phaseId != '$phaseIndex' || !phaseIds.add(phaseId! as String)) {
      throw const FormatException('Migration phase IDs must be unique and ordered.');
    }
    if (!scopes.containsKey(phase['scopeId'])) {
      throw FormatException('Migration phase $phaseId references an unknown schema scope.');
    }
    if (phase['mode'] != 'transactional' && phase['mode'] != 'nontransactional') {
      throw FormatException('Migration phase $phaseId has an unsupported execution mode.');
    }
    final platforms = _list(phase['platforms'], 'phase platforms');
    if (platforms.isEmpty ||
        platforms.any((value) => value != 'native' && value != 'browser') ||
        platforms.toSet().length != platforms.length) {
      throw FormatException('Migration phase $phaseId has invalid platforms.');
    }
    if (phase['mode'] == 'transactional' && phase['recovery'] != null) {
      throw FormatException('Transactional migration phase $phaseId has recovery metadata.');
    }
    if (phase['mode'] == 'nontransactional' && platforms.contains(voxelPlatform)) {
      throw UnsupportedError(
        'Applicable nontransactional migration phase $phaseId is not supported yet.',
      );
    }
    for (final rawRange in _list(phase['statements'], 'phase statements')) {
      final range = _map(rawRange, 'statement range');
      _record(range, 'statement range', const {'startByte', 'endByte'});
      final start = range['startByte'];
      final end = range['endByte'];
      if (start is! int || end is! int || start < 0 || end <= start || end > bytes.length) {
        throw FormatException('Migration phase $phaseId has an invalid statement range.');
      }
      covered.add((start: start, end: end));
    }
  }
  if (covered.length != parsedRanges.length) {
    throw const FormatException('Migration phases do not cover every SQL statement.');
  }
  for (var index = 0; index < covered.length; index++) {
    if (covered[index] != parsedRanges[index]) {
      throw const FormatException('Migration statement ranges are invalid or out of order.');
    }
  }
}

Future<void> _bootstrap(
  TursoDatabase database,
  String scope,
  String databaseId,
  String schemaId,
) async {
  await database.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_identity')} (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  database_id TEXT NOT NULL,
  schema_id TEXT NOT NULL
)
''');
  await database.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_files')} (
  schema_id TEXT NOT NULL PRIMARY KEY,
  file_identity TEXT NOT NULL UNIQUE
)
''');
  await database.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_migrations')} (
  migration_id TEXT NOT NULL PRIMARY KEY,
  parent_id TEXT,
  checksum TEXT NOT NULL,
  ordinal INTEGER NOT NULL UNIQUE
)
''');
  await database.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_phases')} (
  migration_id TEXT NOT NULL,
  phase_id TEXT NOT NULL,
  checksum TEXT NOT NULL,
  platform TEXT NOT NULL,
  status TEXT NOT NULL,
  PRIMARY KEY (migration_id, phase_id),
  FOREIGN KEY (migration_id) REFERENCES _voxel_migrations (migration_id)
)
''');
  await database.execute(
    '''
INSERT INTO ${_qualified(scope, '_voxel_identity')}
  (singleton, database_id, schema_id)
VALUES (1, ?, ?)
ON CONFLICT (singleton) DO NOTHING
''',
    parameters: [databaseId, schemaId],
  );
  final identity = (await database.query(
    'SELECT database_id, schema_id FROM ${_qualified(scope, '_voxel_identity')}',
  )).rows.single;
  if (identity.getString('database_id') != databaseId ||
      identity.getString('schema_id') != schemaId) {
    throw FormatException('Schema `$scope` has a different Voxel database identity.');
  }
}

Future<void> _bootstrapPersistent(
  TursoDatabase database,
  String scope,
  String databaseId,
  String schemaId,
  String fileIdentity,
) async {
  await database.transaction<void>((transaction) async {
    await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_identity')} (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  database_id TEXT NOT NULL,
  schema_id TEXT NOT NULL
)
''');
    await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_files')} (
  schema_id TEXT NOT NULL PRIMARY KEY,
  file_identity TEXT NOT NULL UNIQUE
)
''');
    await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_migrations')} (
  migration_id TEXT NOT NULL PRIMARY KEY,
  parent_id TEXT,
  checksum TEXT NOT NULL,
  ordinal INTEGER NOT NULL UNIQUE
)
''');
    await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_phases')} (
  migration_id TEXT NOT NULL,
  phase_id TEXT NOT NULL,
  checksum TEXT NOT NULL,
  platform TEXT NOT NULL,
  status TEXT NOT NULL,
  PRIMARY KEY (migration_id, phase_id),
  FOREIGN KEY (migration_id) REFERENCES _voxel_migrations (migration_id)
)
''');
    await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_phase_attempts')} (
  migration_id TEXT NOT NULL,
  phase_id TEXT NOT NULL,
  checksum TEXT NOT NULL,
  platform TEXT NOT NULL,
  PRIMARY KEY (migration_id, phase_id)
)
''');
    await transaction.execute(
      '''
INSERT INTO ${_qualified(scope, '_voxel_identity')}
  (singleton, database_id, schema_id)
VALUES (1, ?, ?)
ON CONFLICT (singleton) DO NOTHING
''',
      parameters: [databaseId, schemaId],
    );
    await transaction.execute(
      '''
INSERT INTO ${_qualified(scope, '_voxel_files')} (schema_id, file_identity)
VALUES (?, ?)
ON CONFLICT (schema_id) DO NOTHING
''',
      parameters: [schemaId, fileIdentity],
    );
  });
  final identity = (await database.query(
    'SELECT database_id, schema_id FROM ${_qualified(scope, '_voxel_identity')}',
  )).rows.single;
  final file = (await database.query(
    'SELECT file_identity FROM ${_qualified(scope, '_voxel_files')} WHERE schema_id = ?',
    parameters: [schemaId],
  )).rows.single;
  if (identity.getString('database_id') != databaseId ||
      identity.getString('schema_id') != schemaId ||
      file.getString('file_identity') != fileIdentity) {
    throw FormatException('Schema `$scope` has a different Voxel file identity.');
  }
}

Future<void> _validatePersistentHistory(
  TursoDatabase database,
  String scope,
  List<
    ({
      int ordinal,
      VoxelBundledMigration migration,
      List<Map<String, Object?>> phases,
    })
  >
  expected,
) async {
  final applied = (await database.query(
    '''
SELECT migration_id, parent_id, checksum, ordinal
FROM ${_qualified(scope, '_voxel_migrations')}
ORDER BY ordinal
''',
  )).rows;
  if (applied.length > expected.length) {
    throw const FormatException('Applied Voxel history is not a prefix of the bundle.');
  }
  for (final (index, row) in applied.indexed) {
    final bundled = expected[index];
    if (row.getString('migration_id') != bundled.migration.id ||
        row.value('parent_id') != bundled.migration.parentId ||
        row.getString('checksum') != bundled.migration.checksum ||
        row.getInt('ordinal') != bundled.ordinal) {
      throw const FormatException('Applied Voxel history is not an unchanged bundle prefix.');
    }
  }

  final attempts = (await database.query(
    '''
SELECT migration_id, phase_id, checksum, platform
FROM ${_qualified(scope, '_voxel_phase_attempts')}
''',
  )).rows;
  final expectedPhases = <String, ({String checksum, Set<String> phaseIds})>{
    for (final entry in expected)
      entry.migration.id: (
        checksum: entry.migration.checksum,
        phaseIds: entry.phases.map((phase) => phase['id']! as String).toSet(),
      ),
  };
  final appliedIds = applied.map((row) => row.getString('migration_id')).toSet();
  final receipts = (await database.query(
    '''
SELECT migration_id, phase_id, checksum, platform, status
FROM ${_qualified(scope, '_voxel_phases')}
''',
  )).rows;
  for (final receipt in receipts) {
    final migrationId = receipt.getString('migration_id');
    final phaseId = receipt.getString('phase_id');
    final bundled = expectedPhases[migrationId];
    if (!appliedIds.contains(migrationId) ||
        bundled == null ||
        !bundled.phaseIds.contains(phaseId) ||
        receipt.getString('checksum') != bundled.checksum ||
        receipt.getString('platform') != voxelPlatform ||
        receipt.getString('status') != 'completed') {
      throw FormatException('Migration $migrationId has inconsistent durable receipts.');
    }
  }
  for (final attempt in attempts) {
    final migrationId = attempt.getString('migration_id');
    final phaseId = attempt.getString('phase_id');
    final bundled = expectedPhases[migrationId];
    if (bundled == null ||
        !bundled.phaseIds.contains(phaseId) ||
        attempt.getString('checksum') != bundled.checksum ||
        attempt.getString('platform') != voxelPlatform) {
      throw FormatException('Started migration $migrationId has changed in the bundle.');
    }
  }
}

Future<void> _applyPersistentPhase(
  TursoDatabase database,
  String scope,
  int ordinal,
  VoxelBundledMigration migration,
  Map<String, Object?> phase,
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
) async {
  if (phase['mode'] != 'transactional') {
    throw UnsupportedError(
      'Persistent native migration does not support ${phase['mode']} phases yet.',
    );
  }
  if (await _phaseCompleted(database, scope, migration, phase)) return;
  await database.execute(
    '''
INSERT INTO ${_qualified(scope, '_voxel_phase_attempts')}
  (migration_id, phase_id, checksum, platform)
VALUES (?, ?, ?, ?)
ON CONFLICT (migration_id, phase_id) DO NOTHING
''',
    parameters: [migration.id, phase['id'], migration.checksum, voxelPlatform],
  );
  final bytes = utf8.encode(migration.sql);
  await database.transaction<void>((transaction) async {
    for (final rawRange in _list(phase['statements'], 'phase statements')) {
      final range = _map(rawRange, 'statement range');
      await transaction.execute(
        utf8.decode(
          bytes.sublist(range['startByte']! as int, range['endByte']! as int),
        ),
      );
    }
    await transaction.execute(
      '''
INSERT INTO ${_qualified(scope, '_voxel_migrations')}
  (migration_id, parent_id, checksum, ordinal)
VALUES (?, ?, ?, ?)
ON CONFLICT (migration_id) DO NOTHING
''',
      parameters: [migration.id, migration.parentId, migration.checksum, ordinal],
    );
    await transaction.execute(
      '''
INSERT INTO ${_qualified(scope, '_voxel_phases')}
  (migration_id, phase_id, checksum, platform, status)
VALUES (?, ?, ?, ?, 'completed')
''',
      parameters: [migration.id, phase['id'], migration.checksum, voxelPlatform],
    );
    await interrupt?.call(
      VoxelMigrationInterruption(
        point: VoxelMigrationInterruptionPoint.beforePhaseCommit,
        migrationId: migration.id,
        phaseId: phase['id']! as String,
      ),
    );
  });
  await interrupt?.call(
    VoxelMigrationInterruption(
      point: VoxelMigrationInterruptionPoint.afterPhaseCommit,
      migrationId: migration.id,
      phaseId: phase['id']! as String,
    ),
  );
}

Future<bool> _phaseCompleted(
  TursoDatabase database,
  String scope,
  VoxelBundledMigration migration,
  Map<String, Object?> phase,
) async {
  final result = await database.query(
    '''
SELECT checksum, platform, status
FROM ${_qualified(scope, '_voxel_phases')}
WHERE migration_id = ? AND phase_id = ?
''',
    parameters: [migration.id, phase['id']],
  );
  if (result.rows.isEmpty) return false;
  final row = result.rows.single;
  if (row.getString('checksum') != migration.checksum ||
      row.getString('platform') != voxelPlatform ||
      row.getString('status') != 'completed') {
    throw FormatException('Migration ${migration.id} has inconsistent durable phase history.');
  }
  return true;
}

String _migrationChecksum(VoxelBundledMigration migration) {
  final metadata = Map<String, Object?>.from(migration.metadata)..remove('checksum');
  return sha256
      .convert(
        utf8.encode(
          _canonicalJson({
            'metadata': metadata,
            'snapshot': migration.snapshot,
            'sql': migration.sql,
          }),
        ),
      )
      .toString();
}

String _canonicalJson(Object? value) => switch (value) {
  null || bool() || String() => jsonEncode(value),
  int() => value.toString(),
  double() when value.isFinite =>
    value == 0 ? '0' : jsonEncode(value).replaceFirst(RegExp(r'\.0$'), ''),
  List<Object?>() => '[${value.map(_canonicalJson).join(',')}]',
  Map<String, Object?>() => _canonicalMap(value),
  _ => throw FormatException('Value ${value.runtimeType} is not canonical JSON.'),
};

String _canonicalMap(Map<String, Object?> value) {
  final keys = value.keys.toList()..sort();
  return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
}

List<({int start, int end})> _parseSqlStatements(String sql) {
  final ranges = <({int start, int end})>[];
  var statementStart = _skipWhitespace(sql, 0);
  var index = statementStart;
  var blockDepth = 0;
  var quote = 0;
  while (index < sql.length) {
    if (blockDepth > 0) {
      if (sql.startsWith('/*', index)) {
        blockDepth++;
        index += 2;
      } else if (sql.startsWith('*/', index)) {
        blockDepth--;
        index += 2;
      } else {
        index++;
      }
      continue;
    }
    if (quote != 0) {
      if (sql.codeUnitAt(index) == quote) {
        if (index + 1 < sql.length && sql.codeUnitAt(index + 1) == quote) {
          index += 2;
        } else {
          quote = 0;
          index++;
        }
      } else {
        index++;
      }
      continue;
    }
    if (sql.startsWith('--', index)) {
      final newline = sql.indexOf('\n', index + 2);
      index = newline < 0 ? sql.length : newline + 1;
      continue;
    }
    if (sql.startsWith('/*', index)) {
      blockDepth = 1;
      index += 2;
      continue;
    }
    final unit = sql.codeUnitAt(index);
    if (unit == 0x27 || unit == 0x22) {
      quote = unit;
      index++;
    } else if (unit == 0x3b) {
      ranges.add((
        start: utf8.encode(sql.substring(0, statementStart)).length,
        end: utf8.encode(sql.substring(0, index + 1)).length,
      ));
      statementStart = _skipWhitespace(sql, index + 1);
      index = statementStart;
    } else {
      index++;
    }
  }
  if (quote != 0 || blockDepth != 0 || sql.substring(statementStart).trim().isNotEmpty) {
    throw const FormatException('Migration SQL contains an incomplete statement.');
  }
  return ranges;
}

int _skipWhitespace(String value, int start) {
  var index = start;
  while (index < value.length && const {0x20, 0x09, 0x0a, 0x0d}.contains(value.codeUnitAt(index))) {
    index++;
  }
  return index;
}

void _record(
  Map<String, Object?> value,
  String label,
  Set<String> required, {
  Set<String> optional = const {},
}) {
  final keys = value.keys.toSet();
  if (!keys.containsAll(required) || !required.union(optional).containsAll(keys)) {
    throw FormatException('$label has missing or unknown fields.');
  }
}

String _id(Object? value, String label) {
  if (value is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(value)) {
    throw FormatException('$label must be a lowercase 128-bit hexadecimal identity.');
  }
  return value;
}

List<Object?> _list(Object? value, String label) {
  if (value is! List<Object?>) throw FormatException('$label must be a JSON array.');
  return value;
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map<String, Object?>) throw FormatException('$label must be a JSON object.');
  return value;
}

String _qualified(String schema, String table) => '${_quote(schema)}.${_quote(table)}';

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

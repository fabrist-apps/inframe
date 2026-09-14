// Runtime plan internals are reached only through generated database open code.
// ignore_for_file: prefer_constructors_over_static_methods, public_member_api_docs

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:turso/turso.dart';

import 'package:voxel/src/migration_recovery.dart';
import 'package:voxel/src/migration_status.dart';
import 'package:voxel/src/platform.dart';
import 'package:voxel/src/rebuild_catalog_validator.dart';
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
  VoxelMigrationPlan._(this.bundle, this.scopes, this._scopeNames);

  final VoxelMigrationBundle bundle;
  final List<VoxelMigrationScope> scopes;
  final List<Map<String, String>> _scopeNames;

  List<String> get schemaNames => ([for (final scope in scopes) scope.name]..sort()).toList(
    growable: false,
  );

  String get mainSchemaId =>
      scopes.where((scope) => scope.name == 'main').firstOrNull?.id ?? 'main';

  /// Returns the checked history with every applicable phase pending.
  VoxelMigrationStatus pendingStatus() => VoxelMigrationStatus(
    databaseId: bundle.databaseId,
    migrations: [
      for (final (ordinal, migration) in bundle.migrations.indexed)
        VoxelMigrationStatusEntry(
          id: migration.id,
          checksum: migration.checksum,
          ordinal: ordinal,
          phases: [
            for (final rawPhase in _list(migration.metadata['phases'], 'migration phases'))
              VoxelMigrationPhaseStatus(
                id: _map(rawPhase, 'migration phase')['id']! as String,
                scopeId: _map(rawPhase, 'migration phase')['scopeId']! as String,
                state:
                    (_map(rawPhase, 'migration phase')['platforms']! as List<Object?>).contains(
                      voxelPlatform,
                    )
                    ? VoxelMigrationPhaseState.pending
                    : VoxelMigrationPhaseState.skipped,
                attemptId: null,
                completionRecorded: false,
                evidence: null,
              ),
          ],
        ),
    ],
  );

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
        if (name is! String || name.isEmpty) {
          throw FormatException('Migration $migrationId has an invalid schema name.');
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
      [
        for (final entry in _scopeDescriptors(bundle, scopesByMigration)) entry,
      ],
      scopesByMigration,
    );
  }

  String scopeName(String schemaId) =>
      _scopeNames.last[schemaId] ??
      (throw ArgumentError.value(schemaId, 'schemaId', 'is not in the final snapshot'));

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
        final sourceScope = _scopeNames[migrationIndex][phase['scopeId']]!;
        final scope = scopeName(phase['scopeId']! as String);
        if (await _phaseCompleted(database, scope, migration, phase)) continue;
        await _runTransactionalPhase(
          database,
          scope,
          migrationIndex,
          migration,
          phase,
          previousSnapshot: migrationIndex == 0
              ? null
              : bundle.migrations[migrationIndex - 1].snapshot,
          sourceScope: sourceScope,
        );
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
        ? mainSchemaId
        : scopes
              .singleWhere(
                (entry) => entry.name == scope,
                orElse: () => throw ArgumentError.value(
                  scope,
                  'scope',
                  'is not registered by the migration bundle',
                ),
              )
              .id;
    await bootstrapPersistentScope(
      database,
      scope: scope,
      schemaId: schemaId,
      fileIdentity: fileIdentity,
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
        if (scopeName(phase['scopeId']! as String) == scope) phases.add(phase);
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
          previousSnapshot: entry.ordinal == 0
              ? null
              : bundle.migrations[entry.ordinal - 1].snapshot,
        );
      }
    }
  }

  Future<void> bootstrapPersistentScope(
    TursoDatabase database, {
    required String scope,
    required String schemaId,
    required String fileIdentity,
  }) => _bootstrapPersistent(
    database,
    scope,
    bundle.databaseId,
    schemaId,
    fileIdentity,
  );

  Future<void> applyPersistentScopes(
    TursoDatabase database, {
    required Map<String, String> fileIdentities,
    Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
  }) async {
    for (final entry in fileIdentities.entries) {
      final schemaId = entry.key == 'main'
          ? mainSchemaId
          : scopes.singleWhere((scope) => scope.name == entry.key).id;
      await bootstrapPersistentScope(
        database,
        scope: entry.key,
        schemaId: schemaId,
        fileIdentity: entry.value,
      );
    }
    for (final entry in fileIdentities.entries) {
      await _validatePersistentHistoryForScope(database, entry.key);
    }
    if (fileIdentities.containsKey('main')) await _validateMainSummaries(database);
    for (final (ordinal, migration) in bundle.migrations.indexed) {
      for (final rawPhase in _list(migration.metadata['phases'], 'migration phases')) {
        final phase = _map(rawPhase, 'migration phase');
        if (!(phase['platforms']! as List<Object?>).contains(voxelPlatform)) continue;
        final scope = scopeName(phase['scopeId']! as String);
        if (!fileIdentities.containsKey(scope)) continue;
        await _applyPersistentPhase(
          database,
          scope,
          ordinal,
          migration,
          phase,
          interrupt,
          previousSnapshot: ordinal == 0 ? null : bundle.migrations[ordinal - 1].snapshot,
          sourceScope: _scopeNames[ordinal][phase['scopeId']],
        );
        if (scope != 'main' && fileIdentities.containsKey('main')) {
          await interrupt?.call(
            VoxelMigrationInterruption(
              point: VoxelMigrationInterruptionPoint.beforeMainSummary,
              migrationId: migration.id,
              phaseId: phase['id']! as String,
            ),
          );
          await database.execute(
            '''
INSERT INTO main._voxel_phase_summaries
  (migration_id, phase_id, scope_id, checksum, status)
VALUES (?, ?, ?, ?, 'completed')
ON CONFLICT (migration_id, phase_id) DO UPDATE SET
  scope_id = excluded.scope_id,
  checksum = excluded.checksum,
  status = excluded.status
''',
            parameters: [
              migration.id,
              phase['id'],
              phase['scopeId'],
              migration.checksum,
            ],
          );
          await interrupt?.call(
            VoxelMigrationInterruption(
              point: VoxelMigrationInterruptionPoint.afterMainSummary,
              migrationId: migration.id,
              phaseId: phase['id']! as String,
            ),
          );
        }
      }
    }
  }

  Future<void> _validatePersistentHistoryForScope(
    TursoDatabase database,
    String scope,
  ) async {
    final expected =
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
        if ((phase['platforms']! as List<Object?>).contains(voxelPlatform) &&
            scopeName(phase['scopeId']! as String) == scope) {
          phases.add(phase);
        }
      }
      if (phases.isNotEmpty) {
        expected.add((ordinal: ordinal, migration: migration, phases: phases));
      }
    }
    await _validatePersistentHistory(database, scope, expected);
  }

  Future<void> _validateMainSummaries(TursoDatabase database) async {
    final summaries = (await database.query(
      '''
SELECT migration_id, phase_id, scope_id, checksum, status
FROM main._voxel_phase_summaries
''',
    )).rows;
    for (final summary in summaries) {
      final migrationId = summary.getString('migration_id');
      final phaseId = summary.getString('phase_id');
      final scopeId = summary.getString('scope_id');
      final migration = bundle.migrations.where((entry) => entry.id == migrationId).firstOrNull;
      if (migration == null ||
          summary.getString('checksum') != migration.checksum ||
          summary.getString('status') != 'completed') {
        throw const FormatException('Main migration summary does not match checked history.');
      }
      final scope = scopeName(scopeId);
      if (scope == 'main') {
        throw const FormatException('Main migration summary cannot summarize the main scope.');
      }
      final receipt = (await database.query(
        '''
SELECT checksum, platform, status
FROM ${_qualified(scope, '_voxel_phases')}
WHERE migration_id = ? AND phase_id = ?
''',
        parameters: [migrationId, phaseId],
      )).rows;
      if (receipt.length != 1 ||
          receipt.single.getString('checksum') != migration.checksum ||
          receipt.single.getString('platform') != voxelPlatform ||
          receipt.single.getString('status') != 'completed') {
        throw const FormatException(
          'Main migration summary is contradicted by its per-file phase receipt.',
        );
      }
    }
  }

  /// Reads receipt-derived state from already opened persistent scopes.
  Future<VoxelMigrationStatus> migrationStatus(
    TursoDatabase database, {
    Set<String>? availableScopes,
    Set<String> uncertainScopes = const {},
  }) async {
    final phaseStates = <String, VoxelMigrationPhaseStatus>{};
    for (final migration in bundle.migrations) {
      for (final rawPhase in _list(migration.metadata['phases'], 'migration phases')) {
        final phase = _map(rawPhase, 'migration phase');
        final applies = (phase['platforms']! as List<Object?>).contains(voxelPlatform);
        final scope = scopeName(phase['scopeId']! as String);
        phaseStates['${migration.id}:${phase['id']}'] = VoxelMigrationPhaseStatus(
          id: phase['id']! as String,
          scopeId: phase['scopeId']! as String,
          state: !applies
              ? VoxelMigrationPhaseState.skipped
              : uncertainScopes.contains(scope)
              ? VoxelMigrationPhaseState.uncertain
              : VoxelMigrationPhaseState.pending,
          attemptId: null,
          completionRecorded: false,
          evidence: null,
        );
      }
    }
    for (final scope in scopes.map((entry) => entry.name)) {
      if (availableScopes != null && !availableScopes.contains(scope)) continue;
      await _validatePersistentHistoryForScope(database, scope);
      final completed = (await database.query(
        'SELECT migration_id, phase_id FROM ${_qualified(scope, '_voxel_phases')}',
      )).rows;
      final completedKeys = {
        for (final row in completed)
          '${row.getString('migration_id')}:${row.getString('phase_id')}',
      };
      final attempts = (await database.query(
        'SELECT migration_id, phase_id, attempt_id, evidence, retry_authorized '
        'FROM ${_qualified(scope, '_voxel_phase_attempts')}',
      )).rows;
      final attemptsByKey = {
        for (final row in attempts)
          '${row.getString('migration_id')}:${row.getString('phase_id')}': row,
      };
      for (final migration in bundle.migrations) {
        for (final rawPhase in _list(migration.metadata['phases'], 'migration phases')) {
          final phase = _map(rawPhase, 'migration phase');
          if (!(phase['platforms']! as List<Object?>).contains(voxelPlatform) ||
              scopeName(phase['scopeId']! as String) != scope) {
            continue;
          }
          final key = '${migration.id}:${phase['id']}';
          final attempt = attemptsByKey[key];
          final completionRecorded = completedKeys.contains(key);
          final durableEvidence = attempt == null
              ? null
              : Map<String, Object?>.from(
                  jsonDecode(attempt.getString('evidence'))! as Map,
                );
          _RecoveryInspection? current;
          if (!completionRecorded && attempt != null && phase['mode'] == 'nontransactional') {
            final recovery = _map(phase['recovery'], 'nontransactional recovery');
            current = recovery['kind'] == 'manual'
                ? const _RecoveryInspection(
                    VoxelRecoveryClassification.uncertain,
                    <bool>[],
                  )
                : await _inspectRecovery(
                    database,
                    VoxelRecoveryCheckPlan.parse(recovery['checks'], scopeName: scope),
                  );
          }
          phaseStates[key] = VoxelMigrationPhaseStatus(
            id: phase['id']! as String,
            scopeId: phase['scopeId']! as String,
            state: completionRecorded
                ? VoxelMigrationPhaseState.completed
                : attempt == null
                ? VoxelMigrationPhaseState.pending
                : switch (current!.classification) {
                    VoxelRecoveryClassification.completed => VoxelMigrationPhaseState.completed,
                    VoxelRecoveryClassification.notStarted => VoxelMigrationPhaseState.started,
                    VoxelRecoveryClassification.uncertain => VoxelMigrationPhaseState.uncertain,
                  },
            attemptId: attempt?.getString('attempt_id'),
            completionRecorded: completionRecorded,
            evidence: durableEvidence == null
                ? null
                : {
                    ...durableEvidence,
                    if (current != null)
                      'current': {
                        'classification': current.classification.name,
                        'observations': current.observations,
                      },
                  },
          );
        }
      }
    }
    if (availableScopes == null || scopes.every((scope) => availableScopes.contains(scope.name))) {
      await _validateMainSummaries(database);
    }
    return VoxelMigrationStatus(
      databaseId: bundle.databaseId,
      migrations: [
        for (final (ordinal, migration) in bundle.migrations.indexed)
          VoxelMigrationStatusEntry(
            id: migration.id,
            checksum: migration.checksum,
            ordinal: ordinal,
            phases: [
              for (final rawPhase in _list(migration.metadata['phases'], 'migration phases'))
                phaseStates[_phaseKey(migration.id, rawPhase)]!,
            ],
          ),
      ],
    );
  }

  /// Appends an audited resolution for one active nontransactional attempt.
  Future<void> resolveMigration(
    TursoDatabase database, {
    required String migrationId,
    required String phaseId,
    required String expectedChecksum,
    required String attemptId,
    required String reason,
    required VoxelMigrationResolution resolution,
  }) async {
    final operatorReason = reason.trim();
    if (operatorReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'must not be empty');
    }
    final matches = bundle.migrations.indexed.where((entry) => entry.$2.id == migrationId);
    if (matches.length != 1) {
      throw const FormatException('Resolution migration ID is not in the checked history.');
    }
    final migrationEntry = matches.single;
    final migration = migrationEntry.$2;
    if (migration.checksum != expectedChecksum) {
      throw const FormatException('Resolution checksum does not match checked history.');
    }
    final phaseMatches = _list(
      migration.metadata['phases'],
      'migration phases',
    ).map((value) => _map(value, 'migration phase')).where((phase) => phase['id'] == phaseId);
    if (phaseMatches.length != 1) {
      throw const FormatException('Resolution phase ID is not in the migration.');
    }
    final phase = phaseMatches.single;
    if (phase['mode'] != 'nontransactional' ||
        !(phase['platforms']! as List<Object?>).contains(voxelPlatform)) {
      throw const FormatException('Resolution phase is not an applicable nontransactional phase.');
    }
    final scope = scopeName(phase['scopeId']! as String);
    await _validatePersistentHistoryForScope(database, scope);
    final rows = (await database.query(
      '''
SELECT attempt_id, evidence, retry_authorized
FROM ${_qualified(scope, '_voxel_phase_attempts')}
WHERE migration_id = ? AND phase_id = ? AND checksum = ? AND platform = ?
''',
      parameters: [migrationId, phaseId, expectedChecksum, voxelPlatform],
    )).rows;
    if (rows.length != 1 || rows.single.getString('attempt_id') != attemptId) {
      throw const FormatException('Resolution attempt is not the active started attempt.');
    }
    final recovery = _map(phase['recovery'], 'nontransactional recovery');
    final manual = recovery['kind'] == 'manual';
    final inspected = manual
        ? const _RecoveryInspection(VoxelRecoveryClassification.uncertain, <bool>[])
        : await _inspectRecovery(
            database,
            VoxelRecoveryCheckPlan.parse(recovery['checks'], scopeName: scope),
          );
    final agrees =
        manual ||
        switch (resolution) {
          VoxelMigrationResolution.completed =>
            inspected.classification == VoxelRecoveryClassification.completed,
          VoxelMigrationResolution.retry =>
            inspected.classification == VoxelRecoveryClassification.notStarted,
        };
    if (!agrees) {
      throw FormatException(
        'Current recovery evidence contradicts resolution `${resolution.name}`.',
      );
    }
    await database.transaction<void>((transaction) async {
      await transaction.execute(
        '''
INSERT INTO ${_qualified(scope, '_voxel_migration_resolutions')}
  (migration_id, phase_id, checksum, attempt_id, resolution, reason, evidence)
VALUES (?, ?, ?, ?, ?, ?, ?)
''',
        parameters: [
          migrationId,
          phaseId,
          expectedChecksum,
          attemptId,
          resolution.name,
          operatorReason,
          jsonEncode({'observations': inspected.observations}),
        ],
      );
      if (resolution == VoxelMigrationResolution.completed) {
        await _recordCompletedPhaseOn(
          transaction,
          scope,
          migrationEntry.$1,
          migration,
          phase,
        );
      } else {
        await transaction.execute(
          '''
UPDATE ${_qualified(scope, '_voxel_phase_attempts')}
SET retry_authorized = 1
WHERE migration_id = ? AND phase_id = ?
''',
          parameters: [migrationId, phaseId],
        );
      }
    });
  }
}

final class VoxelMigrationScope {
  const VoxelMigrationScope({
    required this.id,
    required this.name,
    required this.introducedMigrationId,
    required this.introducedPhaseId,
  });

  final String id;
  final String name;
  final String introducedMigrationId;
  final String introducedPhaseId;
}

enum VoxelMigrationInterruptionPoint {
  afterCreationPrepared,
  afterFileBootstrap,
  afterRegistryInitialized,
  afterPhaseStarted,
  beforePhaseCommit,
  afterPhaseCommit,
  beforeMainSummary,
  afterMainSummary,
}

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

Iterable<VoxelMigrationScope> _scopeDescriptors(
  VoxelMigrationBundle bundle,
  List<Map<String, String>> scopesByMigration,
) sync* {
  final introduced = <String, ({String migrationId, String phaseId})>{};
  for (final (index, migration) in bundle.migrations.indexed) {
    for (final schemaId in scopesByMigration[index].keys) {
      if (introduced.containsKey(schemaId)) continue;
      final phase = _list(migration.metadata['phases'], 'migration phases')
          .map((value) => _map(value, 'migration phase'))
          .where((phase) => phase['scopeId'] == schemaId)
          .firstOrNull;
      if (phase == null) {
        throw FormatException(
          'Schema $schemaId is introduced without a migration phase.',
        );
      }
      introduced[schemaId] = (
        migrationId: migration.id,
        phaseId: phase['id']! as String,
      );
    }
  }
  for (final entry in scopesByMigration.last.entries) {
    final origin = introduced[entry.key]!;
    yield VoxelMigrationScope(
      id: entry.key,
      name: entry.value,
      introducedMigrationId: origin.migrationId,
      introducedPhaseId: origin.phaseId,
    );
  }
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
      optional: const {'rebuild', 'writeScopeIds'},
    );
    final phaseId = phase['id'];
    if (phaseId != '$phaseIndex' || !phaseIds.add(phaseId! as String)) {
      throw const FormatException('Migration phase IDs must be unique and ordered.');
    }
    if (!scopes.containsKey(phase['scopeId'])) {
      throw FormatException('Migration phase $phaseId references an unknown schema scope.');
    }
    final writeScopeIds = phase['writeScopeIds'];
    if (writeScopeIds != null) {
      final writes = _list(writeScopeIds, 'phase writeScopeIds');
      if (writes.length != 1 || writes.single != phase['scopeId']) {
        throw FormatException(
          'Migration phase $phaseId must write only its receipt scope.',
        );
      }
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
    if (phase['mode'] == 'nontransactional') {
      final recovery = _map(phase['recovery'], 'nontransactional recovery');
      if (recovery['kind'] == 'catalog' && recovery['checks'] != null) {
        VoxelRecoveryCheckPlan.parse(
          recovery['checks'],
          scopeName: scopes[phase['scopeId']]!,
        );
      } else if (recovery['kind'] != 'manual') {
        throw const FormatException(
          'Voxel catalog recovery requires portable read-only checks.',
        );
      }
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
  schema_id TEXT NOT NULL,
  file_identity TEXT NOT NULL
)
''');
    if (scope == 'main') {
      await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_files')} (
  schema_id TEXT NOT NULL PRIMARY KEY,
  file_identity TEXT NOT NULL UNIQUE,
  location_identity TEXT NOT NULL DEFAULT '',
  introduced_migration_id TEXT,
  introduced_phase_id TEXT,
  state TEXT NOT NULL DEFAULT 'initialized'
)
''');
    }
    await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_file_bootstrap')} (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  database_id TEXT NOT NULL,
  schema_id TEXT NOT NULL,
  file_identity TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status = 'completed')
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
  attempt_id TEXT NOT NULL,
  evidence TEXT NOT NULL,
  retry_authorized INTEGER NOT NULL DEFAULT 0 CHECK (retry_authorized IN (0, 1)),
  PRIMARY KEY (migration_id, phase_id)
)
''');
    await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_migration_resolutions')} (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  migration_id TEXT NOT NULL,
  phase_id TEXT NOT NULL,
  checksum TEXT NOT NULL,
  attempt_id TEXT NOT NULL,
  resolution TEXT NOT NULL,
  reason TEXT NOT NULL,
  evidence TEXT NOT NULL
)
''');
    if (scope == 'main') {
      await transaction.execute('''
CREATE TABLE IF NOT EXISTS ${_qualified(scope, '_voxel_phase_summaries')} (
  migration_id TEXT NOT NULL,
  phase_id TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  checksum TEXT NOT NULL,
  status TEXT NOT NULL,
  PRIMARY KEY (migration_id, phase_id)
)
''');
    }
    await transaction.execute(
      '''
INSERT INTO ${_qualified(scope, '_voxel_identity')}
  (singleton, database_id, schema_id, file_identity)
VALUES (1, ?, ?, ?)
ON CONFLICT (singleton) DO NOTHING
''',
      parameters: [databaseId, schemaId, fileIdentity],
    );
    await transaction.execute(
      '''
INSERT INTO ${_qualified(scope, '_voxel_file_bootstrap')}
  (singleton, database_id, schema_id, file_identity, status)
VALUES (1, ?, ?, ?, 'completed')
ON CONFLICT (singleton) DO NOTHING
''',
      parameters: [databaseId, schemaId, fileIdentity],
    );
    if (scope == 'main') {
      await transaction.execute(
        '''
INSERT INTO ${_qualified(scope, '_voxel_files')} (schema_id, file_identity)
VALUES (?, ?)
ON CONFLICT (schema_id) DO NOTHING
''',
        parameters: [schemaId, fileIdentity],
      );
    }
  });
  final identity = (await database.query(
    'SELECT database_id, schema_id, file_identity '
    'FROM ${_qualified(scope, '_voxel_identity')}',
  )).rows.single;
  final bootstrap = (await database.query(
    'SELECT database_id, schema_id, file_identity, status '
    'FROM ${_qualified(scope, '_voxel_file_bootstrap')}',
  )).rows.single;
  final fileIdentityMatches =
      scope != 'main' ||
      (await database.query(
            'SELECT file_identity FROM ${_qualified(scope, '_voxel_files')} '
            'WHERE schema_id = ?',
            parameters: [schemaId],
          )).rows.single.getString('file_identity') ==
          fileIdentity;
  if (identity.getString('database_id') != databaseId ||
      identity.getString('schema_id') != schemaId ||
      identity.getString('file_identity') != fileIdentity ||
      bootstrap.getString('database_id') != databaseId ||
      bootstrap.getString('schema_id') != schemaId ||
      bootstrap.getString('file_identity') != fileIdentity ||
      bootstrap.getString('status') != 'completed' ||
      !fileIdentityMatches) {
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
SELECT migration_id, phase_id, checksum, platform, attempt_id, evidence, retry_authorized
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
  final receiptKeys = {
    for (final receipt in receipts)
      '${receipt.getString('migration_id')}:${receipt.getString('phase_id')}',
  };
  var missingSeen = false;
  for (final entry in expected) {
    var receiptsForMigration = 0;
    for (final phase in entry.phases) {
      final present = receiptKeys.contains('${entry.migration.id}:${phase['id']}');
      if (present) {
        receiptsForMigration++;
        if (missingSeen) {
          throw const FormatException(
            'Voxel phase receipts are not an ordered prefix of the checked history.',
          );
        }
      } else {
        missingSeen = true;
      }
    }
    if (appliedIds.contains(entry.migration.id) && receiptsForMigration == 0) {
      throw FormatException(
        'Applied migration ${entry.migration.id} has no durable phase receipt.',
      );
    }
  }
  for (final attempt in attempts) {
    final migrationId = attempt.getString('migration_id');
    final phaseId = attempt.getString('phase_id');
    final bundled = expectedPhases[migrationId];
    if (bundled == null ||
        !bundled.phaseIds.contains(phaseId) ||
        attempt.getString('checksum') != bundled.checksum ||
        attempt.getString('platform') != voxelPlatform ||
        attempt.getString('attempt_id').isEmpty ||
        (attempt.getInt('retry_authorized') != 0 && attempt.getInt('retry_authorized') != 1) ||
        !_isEvidence(attempt.getString('evidence'))) {
      throw FormatException('Started migration $migrationId has changed in the bundle.');
    }
    final attemptKey = '$migrationId:$phaseId';
    if (receiptKeys.contains(attemptKey)) continue;
    final firstMissing = expected
        .expand(
          (entry) => entry.phases.map((phase) => '${entry.migration.id}:${phase['id']}'),
        )
        .where((key) => !receiptKeys.contains(key))
        .firstOrNull;
    if (attemptKey != firstMissing) {
      throw const FormatException(
        'Started phase is not the next unfinished phase in checked history.',
      );
    }
  }
}

Future<void> _applyPersistentPhase(
  TursoDatabase database,
  String scope,
  int ordinal,
  VoxelBundledMigration migration,
  Map<String, Object?> phase,
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt, {
  required Map<String, Object?>? previousSnapshot,
  String? sourceScope,
}) async {
  if (await _phaseCompleted(database, scope, migration, phase)) return;
  if (phase['mode'] == 'nontransactional') {
    await _runNontransactionalPhase(
      database,
      scope,
      ordinal,
      migration,
      phase,
      sourceScope: sourceScope,
      interrupt: interrupt,
    );
    return;
  }
  await _runTransactionalPhase(
    database,
    scope,
    ordinal,
    migration,
    phase,
    previousSnapshot: previousSnapshot,
    sourceScope: sourceScope,
    interrupt: interrupt,
  );
}

Future<void> _runNontransactionalPhase(
  TursoDatabase database,
  String scope,
  int ordinal,
  VoxelBundledMigration migration,
  Map<String, Object?> phase, {
  String? sourceScope,
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
}) async {
  final recovery = _map(phase['recovery'], 'nontransactional recovery');
  final plan = recovery['kind'] == 'catalog'
      ? VoxelRecoveryCheckPlan.parse(recovery['checks'], scopeName: scope)
      : null;
  final existing = (await database.query(
    '''
SELECT attempt_id, evidence, retry_authorized
FROM ${_qualified(scope, '_voxel_phase_attempts')}
WHERE migration_id = ? AND phase_id = ?
''',
    parameters: [migration.id, phase['id']],
  )).rows;
  if (plan == null) {
    if (existing.isNotEmpty && existing.single.getInt('retry_authorized') != 1) {
      throw FormatException(
        'Migration ${migration.id} phase ${phase['id']} requires manual recovery.',
      );
    }
    if (existing.isEmpty) {
      await _recordStartedAttempt(
        database,
        scope,
        migration,
        phase,
        jsonEncode({'before': recovery['before']}),
      );
    } else {
      await _consumeRetryAuthorization(
        database,
        scope,
        migration,
        phase,
        jsonEncode({'before': recovery['before']}),
      );
    }
  } else if (existing.isEmpty) {
    final inspected = await _inspectRecovery(database, plan);
    if (inspected.classification != VoxelRecoveryClassification.notStarted) {
      throw FormatException(
        'Migration ${migration.id} phase ${phase['id']} has conflicting preexisting state.',
      );
    }
    await _recordStartedAttempt(
      database,
      scope,
      migration,
      phase,
      jsonEncode({'before': inspected.observations}),
    );
  } else {
    final inspected = await _inspectRecovery(database, plan);
    if (inspected.classification == VoxelRecoveryClassification.completed) {
      await _recordCompletedPhase(database, scope, ordinal, migration, phase);
      return;
    }
    if (inspected.classification != VoxelRecoveryClassification.notStarted) {
      throw FormatException(
        'Migration ${migration.id} phase ${phase['id']} has an uncertain outcome.',
      );
    }
    if (existing.single.getInt('retry_authorized') == 1) {
      await _consumeRetryAuthorization(
        database,
        scope,
        migration,
        phase,
        jsonEncode({'before': inspected.observations}),
      );
    }
  }
  await interrupt?.call(
    VoxelMigrationInterruption(
      point: VoxelMigrationInterruptionPoint.afterPhaseStarted,
      migrationId: migration.id,
      phaseId: phase['id']! as String,
    ),
  );

  final bytes = utf8.encode(migration.sql);
  for (final rawRange in _list(phase['statements'], 'phase statements')) {
    final range = _map(rawRange, 'statement range');
    await database.execute(
      _rewriteScope(
        utf8.decode(bytes.sublist(range['startByte']! as int, range['endByte']! as int)),
        sourceScope,
        scope,
      ),
    );
  }
  await interrupt?.call(
    VoxelMigrationInterruption(
      point: VoxelMigrationInterruptionPoint.beforePhaseCommit,
      migrationId: migration.id,
      phaseId: phase['id']! as String,
    ),
  );
  if (plan != null) {
    final after = await _inspectRecovery(database, plan);
    if (after.classification != VoxelRecoveryClassification.completed) {
      throw FormatException(
        'Migration ${migration.id} phase ${phase['id']} did not establish its postcondition.',
      );
    }
  }
  await _recordCompletedPhase(database, scope, ordinal, migration, phase);
  await interrupt?.call(
    VoxelMigrationInterruption(
      point: VoxelMigrationInterruptionPoint.afterPhaseCommit,
      migrationId: migration.id,
      phaseId: phase['id']! as String,
    ),
  );
}

Future<void> _recordStartedAttempt(
  TursoDatabase database,
  String scope,
  VoxelBundledMigration migration,
  Map<String, Object?> phase,
  String evidence,
) => database.execute(
  '''
INSERT INTO ${_qualified(scope, '_voxel_phase_attempts')}
  (migration_id, phase_id, checksum, platform, attempt_id, evidence, retry_authorized)
VALUES (?, ?, ?, ?, ?, ?, 0)
''',
  parameters: [
    migration.id,
    phase['id'],
    migration.checksum,
    voxelPlatform,
    _newAttemptId(),
    evidence,
  ],
);

Future<void> _consumeRetryAuthorization(
  TursoDatabase database,
  String scope,
  VoxelBundledMigration migration,
  Map<String, Object?> phase,
  String evidence,
) => database.execute(
  '''
UPDATE ${_qualified(scope, '_voxel_phase_attempts')}
SET attempt_id = ?, evidence = ?, retry_authorized = 0
WHERE migration_id = ? AND phase_id = ? AND retry_authorized = 1
''',
  parameters: [_newAttemptId(), evidence, migration.id, phase['id']],
);

final class _RecoveryInspection {
  const _RecoveryInspection(this.classification, this.observations);

  final VoxelRecoveryClassification classification;
  final List<bool> observations;
}

Future<_RecoveryInspection> _inspectRecovery(
  TursoDatabase database,
  VoxelRecoveryCheckPlan plan,
) async {
  final raw = <Object?>[];
  final observations = <bool>[];
  for (final check in plan.checks) {
    final result = await database.query(check.sql, parameters: check.parameters);
    if (result.rows.length != 1 || result.columns.length != 1) {
      return const _RecoveryInspection(VoxelRecoveryClassification.uncertain, <bool>[]);
    }
    final value = result.rows.single.valueAt(0);
    raw.add(value);
    switch (value) {
      case final bool value:
        observations.add(value);
      case final int value when value == 0 || value == 1:
        observations.add(value == 1);
      case final BigInt value when value == BigInt.zero || value == BigInt.one:
        observations.add(value == BigInt.one);
      default:
        return const _RecoveryInspection(VoxelRecoveryClassification.uncertain, <bool>[]);
    }
  }
  return _RecoveryInspection(plan.classify(raw), List.unmodifiable(observations));
}

Future<void> _recordCompletedPhase(
  TursoDatabase database,
  String scope,
  int ordinal,
  VoxelBundledMigration migration,
  Map<String, Object?> phase,
) => database.transaction<void>(
  (transaction) => _recordCompletedPhaseOn(
    transaction,
    scope,
    ordinal,
    migration,
    phase,
  ),
);

Future<void> _recordCompletedPhaseOn(
  TursoTransaction transaction,
  String scope,
  int ordinal,
  VoxelBundledMigration migration,
  Map<String, Object?> phase,
) async {
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
}

String _newAttemptId() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

bool _isEvidence(String value) {
  try {
    return jsonDecode(value) is Map;
  } on FormatException {
    return false;
  }
}

String _phaseKey(String migrationId, Object? rawPhase) =>
    '$migrationId:${(rawPhase! as Map<String, Object?>)['id']}';

Future<void> _runTransactionalPhase(
  TursoDatabase database,
  String scope,
  int ordinal,
  VoxelBundledMigration migration,
  Map<String, Object?> phase, {
  required Map<String, Object?>? previousSnapshot,
  String? sourceScope,
  Future<void> Function(VoxelMigrationInterruption interruption)? interrupt,
}) async {
  final rebuild = phase['rebuild'] as Map<String, Object?>?;
  Object? primaryFailure;
  StackTrace? primaryStackTrace;
  var foreignKeysMayBeDisabled = false;
  try {
    if (rebuild != null) {
      if (rebuild['tables'] != null) {
        if (previousSnapshot == null) {
          throw const FormatException('An initial migration cannot rebuild an existing table.');
        }
        await const VoxelRebuildCatalogValidator().validate(
          scopeName: scope,
          rebuild: rebuild,
          previousSnapshot: previousSnapshot,
          query: (sql) => _catalogRows(database.query(sql)),
        );
      }
      foreignKeysMayBeDisabled = true;
      await _setForeignKeys(database, enabled: false);
    }
    final bytes = utf8.encode(migration.sql);
    await database.transaction<void>((transaction) async {
      for (final rawRange in _list(phase['statements'], 'phase statements')) {
        final range = _map(rawRange, 'statement range');
        final statement = _rewriteScope(
          utf8.decode(
            bytes.sublist(range['startByte']! as int, range['endByte']! as int),
          ),
          sourceScope,
          scope,
        );
        await transaction.execute(statement);
      }
      if (rebuild != null) {
        await const VoxelRebuildCatalogValidator().validateFinalScope(
          scopeName: scope,
          scopeId: phase['scopeId']! as String,
          snapshot: migration.snapshot,
          query: (sql) => _catalogRows(transaction.query(sql)),
        );
        for (final rawValidation in _list(rebuild['validations'], 'rebuild validations')) {
          final validation = _map(rawValidation, 'rebuild validation');
          final sql = _rewriteScope(validation['sql']! as String, sourceScope, scope);
          final row = (await transaction.query(sql)).rows.single;
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
  } on Object catch (error, stackTrace) {
    primaryFailure = error;
    primaryStackTrace = stackTrace;
  }

  if (foreignKeysMayBeDisabled) {
    try {
      await _setForeignKeys(database, enabled: true);
    } on Object catch (restorationFailure, restorationStackTrace) {
      Error.throwWithStackTrace(restorationFailure, restorationStackTrace);
    }
  }
  if (primaryFailure != null) {
    Error.throwWithStackTrace(primaryFailure, primaryStackTrace!);
  }
  await interrupt?.call(
    VoxelMigrationInterruption(
      point: VoxelMigrationInterruptionPoint.afterPhaseCommit,
      migrationId: migration.id,
      phaseId: phase['id']! as String,
    ),
  );
}

Future<void> _setForeignKeys(TursoDatabase database, {required bool enabled}) async {
  await database.execute('PRAGMA foreign_keys=${enabled ? 'ON' : 'OFF'}');
  final actual = (await database.query('PRAGMA foreign_keys')).rows.single.getInt('foreign_keys');
  if ((actual == 1) != enabled) {
    throw StateError('Voxel could not ${enabled ? 'restore' : 'disable'} foreign-key enforcement.');
  }
}

String _rewriteScope(String sql, String? sourceScope, String targetScope) {
  if (sourceScope == null || sourceScope == targetScope) return sql;
  return sql.replaceAll('${_quote(sourceScope)}.', '${_quote(targetScope)}.');
}

Future<List<Map<String, Object?>>> _catalogRows(Future<TursoQueryResult> result) async {
  final resolved = await result;
  return [
    for (final row in resolved.rows)
      {
        for (var index = 0; index < resolved.columns.length; index++)
          resolved.columns[index].name: row.valueAt(index),
      },
  ];
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

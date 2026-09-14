import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart' as pg;

import 'package:rivet/src/connection.dart';
import 'package:rivet/src/errors.dart';
import 'package:rivet/src/migration/artifacts.dart';

final int _migrationLockKey = int.parse('1151101229740241950');

/// Applies checked Rivet artifacts through a dedicated PostgreSQL session.
///
/// Each operation validates the complete artifact directory before opening a
/// connection. Migration coordination covers history bootstrap, verification,
/// and execution. The owned direct connection is always closed when the
/// operation completes or fails.
final class RivetMigrator {
  /// Creates an explicit deployment migrator for [directory].
  RivetMigrator({
    required this.connection,
    required this.directory,
    this.lockTimeout = const Duration(seconds: 30),
  }) {
    if (lockTimeout.isNegative) {
      throw ArgumentError.value(lockTimeout, 'lockTimeout', 'must not be negative');
    }
  }

  /// Connection settings used for the owned direct session.
  final RivetConnection connection;

  /// Checked artifact directory containing `journal.json`.
  final Directory directory;

  /// Total time allowed for acquiring exclusive migration ownership.
  final Duration lockTimeout;

  /// Verifies durable history and applies every pending transactional migration.
  Future<void> migrate() async {
    final artifacts = RivetMigrationArtifacts.read(directory);
    await _withLockedConnection((session) async {
      await _bootstrap(session);
      final history = await _readHistory(session, artifacts.databaseId);
      _validateHistory(artifacts, history);
      for (final (migrationIndex, migration) in artifacts.migrations.indexed) {
        final completedPhases = migrationIndex < history.length
            ? history[migrationIndex].receipts.length
            : 0;
        for (var phaseIndex = 0; phaseIndex < migration.phases.length; phaseIndex++) {
          final receipt = phaseIndex < completedPhases
              ? history[migrationIndex].receipts[phaseIndex]
              : null;
          if (receipt?.status == 'completed') continue;
          final insertMigration = migrationIndex >= history.length && phaseIndex == 0;
          final phase = migration.phases[phaseIndex];
          if (phase.mode == RivetMigrationPhaseMode.transactional) {
            await _applyTransactionalPhase(
              session,
              artifacts.databaseId,
              migration,
              phaseIndex,
              insertMigration: insertMigration,
            );
          } else {
            await _applyNontransactionalPhase(
              session,
              artifacts.databaseId,
              migration,
              phase,
              receipt,
              insertMigration: insertMigration,
            );
          }
        }
      }
    });
  }

  Future<T> _withLockedConnection<T>(Future<T> Function(pg.Connection session) operation) async {
    pg.Connection? session;
    var locked = false;
    try {
      session = await _openConnection(connection);
      locked = await _acquireLock(session);
      if (!locked) {
        throw RivetMigrationException(
          'Timed out after ${lockTimeout.inMilliseconds}ms waiting for migration ownership.',
        );
      }
      return await operation(session);
    } on RivetException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw RivetMigrationException('PostgreSQL migration operation failed.', error);
    } finally {
      if (session != null) {
        if (locked && session.isOpen) {
          try {
            await session.execute(
              pg.Sql.named('SELECT pg_advisory_unlock(@key)'),
              parameters: {'key': _migrationLockKey},
            );
          } on Object {
            // Closing the owned session also releases a session advisory lock.
          }
        }
        try {
          await session.close(force: !session.isOpen);
        } on Object {
          // Preserve the operation failure; a closed session owns no lock.
        }
      }
    }
  }

  Future<bool> _acquireLock(pg.Connection session) async {
    final elapsed = Stopwatch()..start();
    while (true) {
      final result = await session.execute(
        pg.Sql.named('SELECT pg_try_advisory_lock(@key)'),
        parameters: {'key': _migrationLockKey},
      );
      if (result.single[0] == true) return true;
      final remaining = lockTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero) return false;
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 25) ? remaining : const Duration(milliseconds: 25),
      );
    }
  }
}

Future<void> _bootstrap(pg.Connection session) async {
  await session.execute('CREATE SCHEMA IF NOT EXISTS _rivet');
  await session.execute('''
    CREATE TABLE IF NOT EXISTS _rivet.migrations (
      "databaseId" text NOT NULL,
      id text NOT NULL,
      "parentId" text,
      checksum text NOT NULL,
      ordinal integer NOT NULL,
      PRIMARY KEY ("databaseId", id),
      UNIQUE ("databaseId", ordinal)
    )
  ''');
  await session.execute('''
    CREATE TABLE IF NOT EXISTS _rivet.phase_receipts (
      "databaseId" text NOT NULL,
      "migrationId" text NOT NULL,
      "phaseId" text NOT NULL,
      checksum text NOT NULL,
      "scopeId" text NOT NULL,
      status text NOT NULL CHECK (status IN ('started', 'completed')),
      "attemptId" text,
      evidence jsonb NOT NULL,
      PRIMARY KEY ("databaseId", "migrationId", "phaseId")
    )
  ''');
}

Future<List<_HistoryRecord>> _readHistory(pg.Connection session, String databaseId) async {
  final otherIdentities = await session.execute(
    pg.Sql.named('SELECT DISTINCT "databaseId" FROM _rivet.migrations WHERE "databaseId" <> @id'),
    parameters: {'id': databaseId},
  );
  if (otherIdentities.isNotEmpty) {
    throw const RivetMigrationException(
      'The database contains a different Rivet migration identity.',
    );
  }
  final rows = await session.execute(
    pg.Sql.named('''
      SELECT m.id, m."parentId", m.checksum, m.ordinal,
             r."phaseId", r.checksum, r."scopeId", r.status, r."attemptId", r.evidence
      FROM _rivet.migrations m
      LEFT JOIN _rivet.phase_receipts r
        ON r."databaseId" = m."databaseId" AND r."migrationId" = m.id
      WHERE m."databaseId" = @databaseId
      ORDER BY m.ordinal, r."phaseId"::integer
    '''),
    parameters: {'databaseId': databaseId},
  );
  final history = <_HistoryRecord>[];
  for (final row in rows) {
    final ordinal = row[3]! as int;
    while (history.length <= ordinal) {
      history.add(
        _HistoryRecord(
          id: row[0]! as String,
          parentId: row[1] as String?,
          checksum: row[2]! as String,
          ordinal: ordinal,
          receipts: [],
        ),
      );
    }
    if (row[4] != null) {
      history[ordinal].receipts.add(
        _Receipt(
          phaseId: row[4]! as String,
          checksum: row[5]! as String,
          scopeId: row[6]! as String,
          status: row[7]! as String,
          attemptId: row[8] as String?,
          evidence: row[9],
        ),
      );
    }
  }
  return history;
}

void _validateHistory(RivetMigrationArtifacts artifacts, List<_HistoryRecord> history) {
  if (history.length > artifacts.migrations.length) {
    throw const RivetMigrationException('Applied migrations are missing from supplied history.');
  }
  for (final (index, record) in history.indexed) {
    final migration = artifacts.migrations[index];
    if (record.ordinal != index ||
        record.id != migration.id ||
        record.parentId != migration.parentId ||
        record.checksum != migration.checksum) {
      throw RivetMigrationException('Applied migration history differs at ordinal $index.');
    }
    if (record.receipts.length > migration.phases.length ||
        (index < history.length - 1 && record.receipts.length != migration.phases.length)) {
      throw RivetMigrationException('Migration ${migration.id} has invalid phase receipt order.');
    }
    for (final (phaseIndex, receipt) in record.receipts.indexed) {
      final phase = migration.phases[phaseIndex];
      final transactional = phase.mode == RivetMigrationPhaseMode.transactional;
      if (receipt.phaseId != phase.id ||
          receipt.checksum != migration.checksum ||
          receipt.scopeId != phase.scopeId ||
          !const {'started', 'completed'}.contains(receipt.status) ||
          (transactional && (receipt.status != 'completed' || receipt.attemptId != null)) ||
          (!transactional && receipt.attemptId == null) ||
          (receipt.status == 'started' && phaseIndex != record.receipts.length - 1) ||
          receipt.evidence is! Map) {
        throw RivetMigrationException(
          'Migration ${migration.id} phase ${phase.id} has a mismatched receipt.',
        );
      }
    }
  }
}

Future<void> _applyNontransactionalPhase(
  pg.Connection connection,
  String databaseId,
  RivetMigrationArtifact migration,
  RivetMigrationPhase phase,
  _Receipt? receipt, {
  required bool insertMigration,
}) async {
  var attemptId = receipt?.attemptId;
  Map<String, Object?> beforeEvidence;
  if (receipt == null) {
    final before = await _inspectRecovery(connection, phase, null);
    if (before.classification != _RecoveryClassification.notStarted) {
      throw RivetMigrationException(
        'Migration ${migration.id} phase ${phase.id} does not match its declared precondition.',
      );
    }
    beforeEvidence = before.evidence;
    attemptId = _newAttemptId();
    await _recordStartedPhase(
      connection,
      databaseId,
      migration,
      phase,
      attemptId,
      beforeEvidence,
      insertMigration: insertMigration,
    );
  } else {
    beforeEvidence = Map<String, Object?>.from(receipt.evidence! as Map);
    final recovery = await _inspectRecovery(connection, phase, beforeEvidence);
    if (recovery.classification == _RecoveryClassification.completed) {
      await _recordCompletedPhase(
        connection,
        databaseId,
        migration,
        phase,
        attemptId!,
        beforeEvidence,
        recovery.evidence,
      );
      return;
    }
    if (recovery.classification != _RecoveryClassification.notStarted) {
      throw RivetMigrationException(
        'Migration ${migration.id} phase ${phase.id} has a partial or uncertain outcome.',
      );
    }
  }

  for (final statement in phase.statements) {
    await connection.execute(statement, queryMode: pg.QueryMode.simple);
  }
  final after = await _inspectRecovery(connection, phase, beforeEvidence);
  if (after.classification != _RecoveryClassification.completed) {
    throw RivetMigrationException(
      'Migration ${migration.id} phase ${phase.id} requires explicit recovery.',
    );
  }
  await _recordCompletedPhase(
    connection,
    databaseId,
    migration,
    phase,
    attemptId!,
    beforeEvidence,
    after.evidence,
  );
}

Future<void> _recordStartedPhase(
  pg.Connection connection,
  String databaseId,
  RivetMigrationArtifact migration,
  RivetMigrationPhase phase,
  String attemptId,
  Map<String, Object?> evidence, {
  required bool insertMigration,
}) async {
  await connection.runTx((transaction) async {
    if (insertMigration) {
      await _insertMigration(transaction, databaseId, migration);
    }
    await transaction.execute(
      pg.Sql.named('''
        INSERT INTO _rivet.phase_receipts
          ("databaseId", "migrationId", "phaseId", checksum, "scopeId", status,
           "attemptId", evidence)
        VALUES (@databaseId, @migrationId, @phaseId, @checksum, @scopeId,
                'started', @attemptId, CAST(@evidence AS jsonb))
      '''),
      parameters: {
        'databaseId': databaseId,
        'migrationId': migration.id,
        'phaseId': phase.id,
        'checksum': migration.checksum,
        'scopeId': phase.scopeId,
        'attemptId': attemptId,
        'evidence': jsonEncode(evidence),
      },
    );
  });
}

Future<void> _recordCompletedPhase(
  pg.Connection connection,
  String databaseId,
  RivetMigrationArtifact migration,
  RivetMigrationPhase phase,
  String attemptId,
  Map<String, Object?> before,
  Map<String, Object?> after,
) async {
  final result = await connection.execute(
    pg.Sql.named('''
      UPDATE _rivet.phase_receipts
      SET status = 'completed', evidence = CAST(@evidence AS jsonb)
      WHERE "databaseId" = @databaseId AND "migrationId" = @migrationId
        AND "phaseId" = @phaseId AND checksum = @checksum
        AND "attemptId" = @attemptId AND status = 'started'
    '''),
    parameters: {
      'databaseId': databaseId,
      'migrationId': migration.id,
      'phaseId': phase.id,
      'checksum': migration.checksum,
      'attemptId': attemptId,
      'evidence': jsonEncode({'before': before, 'after': after}),
    },
  );
  if (result.affectedRows != 1) {
    throw RivetMigrationException(
      'Migration ${migration.id} phase ${phase.id} changed while recording completion.',
    );
  }
}

Future<_RecoveryResult> _inspectRecovery(
  pg.Connection connection,
  RivetMigrationPhase phase,
  Map<String, Object?>? recordedBefore,
) async {
  final recovery = phase.recovery!;
  if (recovery['inspector'] == 'postgresql.index.v1') {
    return _inspectIndex(connection, recovery, recordedBefore);
  }
  if (recovery['checks'] case final List<Object?> checks) {
    return _inspectChecks(connection, checks);
  }
  return _RecoveryResult(
    recordedBefore == null ? _RecoveryClassification.notStarted : _RecoveryClassification.uncertain,
    {'kind': 'manual', 'declaredBefore': recovery['before']},
  );
}

Future<_RecoveryResult> _inspectChecks(
  pg.Connection connection,
  List<Object?> checks,
) async {
  var matchesAfter = true;
  var matchesBefore = true;
  final observations = <bool>[];
  for (final raw in checks) {
    final check = raw! as Map<String, Object?>;
    final parameters = <Object?>[];
    final types = <pg.Type>[];
    for (final rawParameter in check['parameters']! as List<Object?>) {
      final parameter = rawParameter! as Map<String, Object?>;
      parameters.add(parameter['value']);
      types.add(switch (parameter['type']) {
        'boolean' => pg.Type.boolean,
        'decimal' => pg.Type.numeric,
        'string' => pg.Type.text,
        _ => pg.Type.unspecified,
      });
    }
    final result = await connection.execute(
      pg.Sql(check['sql']! as String, types: types),
      parameters: parameters,
    );
    if (result.length != 1 || result.single.length != 1 || result.single.single is! bool) {
      return const _RecoveryResult(_RecoveryClassification.uncertain, {});
    }
    final observed = result.single.single! as bool;
    final expected = check['expected']! as bool;
    observations.add(observed);
    matchesAfter = matchesAfter && observed == expected;
    matchesBefore = matchesBefore && observed != expected;
  }
  return _RecoveryResult(
    matchesAfter
        ? _RecoveryClassification.completed
        : matchesBefore
        ? _RecoveryClassification.notStarted
        : _RecoveryClassification.uncertain,
    {'kind': 'checks', 'observed': observations},
  );
}

Future<_RecoveryResult> _inspectIndex(
  pg.Connection connection,
  Map<String, Object?> recovery,
  Map<String, Object?>? recordedBefore,
) async {
  final expected = recovery['after']! as Map<String, Object?>;
  final schema = expected['schema']! as String;
  final table = expected['table']! as String;
  final index = expected['index']! as String;
  final tableRows = await connection.execute(
    pg.Sql.named('''
      SELECT c.oid::bigint, c.relowner::bigint
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = @schema AND c.relname = @table
        AND c.relkind IN ('r', 'p')
    '''),
    parameters: {'schema': schema, 'table': table},
  );
  if (tableRows.length != 1) {
    return const _RecoveryResult(_RecoveryClassification.uncertain, {});
  }
  final tableEvidence = <String, Object?>{
    'kind': 'postgresql.index.v1',
    'schema': schema,
    'table': table,
    'index': index,
    'tableOid': tableRows.single[0],
    'tableOwnerOid': tableRows.single[1],
    'indexAbsent': true,
  };
  final indexRows = await connection.execute(
    pg.Sql.named('''
      SELECT i.oid::bigint, i.relowner::bigint, am.amname,
             x.indisunique, x.indisvalid, x.indisready,
             pg_get_expr(x.indpred, x.indrelid), i.reloptions,
             x.indnkeyatts, pg_get_indexdef(i.oid)
      FROM pg_class i
      JOIN pg_namespace n ON n.oid = i.relnamespace
      JOIN pg_index x ON x.indexrelid = i.oid
      JOIN pg_am am ON am.oid = i.relam
      WHERE n.nspname = @schema AND i.relname = @index
        AND x.indrelid = @tableOid
    '''),
    parameters: {
      'schema': schema,
      'index': index,
      'tableOid': tableRows.single[0],
    },
  );
  if (indexRows.isEmpty) {
    final unchanged =
        recordedBefore == null ||
        (recordedBefore['tableOid'] == tableEvidence['tableOid'] &&
            recordedBefore['tableOwnerOid'] == tableEvidence['tableOwnerOid'] &&
            recordedBefore['indexAbsent'] == true);
    return _RecoveryResult(
      unchanged ? _RecoveryClassification.notStarted : _RecoveryClassification.uncertain,
      tableEvidence,
    );
  }
  if (indexRows.length != 1) {
    return const _RecoveryResult(_RecoveryClassification.uncertain, {});
  }
  final row = indexRows.single;
  final termRows = await connection.execute(
    pg.Sql.named('''
      SELECT a.attname, (keys.option & 1) = 1, opc.opcname
      FROM pg_index x
      CROSS JOIN LATERAL unnest(
        x.indkey::smallint[], x.indoption::smallint[], x.indclass::oid[]
      ) WITH ORDINALITY AS keys(attnum, option, opclass_oid, ordinal)
      LEFT JOIN pg_attribute a
        ON a.attrelid = x.indrelid AND a.attnum = keys.attnum
      JOIN pg_opclass opc ON opc.oid = keys.opclass_oid
      WHERE x.indexrelid = @indexOid AND keys.ordinal <= x.indnkeyatts
      ORDER BY keys.ordinal
    '''),
    parameters: {'indexOid': row[0]},
  );
  final terms = [
    for (final term in termRows)
      {'column': term[0], 'descending': term[1], 'operatorClass': term[2]},
  ];
  final expectedTerms = (expected['terms']! as List<Object?>).cast<Map<String, Object?>>();
  final termsMatch =
      terms.length == expectedTerms.length &&
      terms.indexed.every(
        (entry) =>
            entry.$2['column'] == expectedTerms[entry.$1]['column'] &&
            entry.$2['descending'] == expectedTerms[entry.$1]['descending'],
      );
  final options = row[7] as List<Object?>?;
  final expectedOptions = expected['options']! as Map<String, Object?>;
  final evidence = <String, Object?>{
    ...tableEvidence,
    'indexAbsent': false,
    'indexOid': row[0],
    'indexOwnerOid': row[1],
    'method': row[2],
    'unique': row[3],
    'valid': row[4],
    'ready': row[5],
    'predicate': row[6],
    'options': options ?? <Object?>[],
    'terms': terms,
    'definition': row[9],
  };
  final matches =
      row[1] == tableEvidence['tableOwnerOid'] &&
      row[2] == expected['method'] &&
      row[3] == expected['unique'] &&
      row[4] == expected['valid'] &&
      row[5] == expected['ready'] &&
      _normalizedSql(row[6] as String?) == _normalizedSql(expected['predicate'] as String?) &&
      (options == null || options.isEmpty) &&
      expectedOptions.isEmpty &&
      termsMatch;
  return _RecoveryResult(
    matches ? _RecoveryClassification.completed : _RecoveryClassification.uncertain,
    evidence,
  );
}

Future<void> _insertMigration(
  pg.Session transaction,
  String databaseId,
  RivetMigrationArtifact migration,
) => transaction
    .execute(
      pg.Sql.named('''
    INSERT INTO _rivet.migrations
      ("databaseId", id, "parentId", checksum, ordinal)
    VALUES (@databaseId, @id, @parentId, @checksum, @ordinal)
  '''),
      parameters: {
        'databaseId': databaseId,
        'id': migration.id,
        'parentId': migration.parentId,
        'checksum': migration.checksum,
        'ordinal': migration.ordinal,
      },
    )
    .then((_) {});

String _newAttemptId() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String? _normalizedSql(String? value) => value?.replaceAll(RegExp(r'\s+'), ' ').trim();

enum _RecoveryClassification { completed, notStarted, uncertain }

final class _RecoveryResult {
  const _RecoveryResult(this.classification, this.evidence);

  final _RecoveryClassification classification;
  final Map<String, Object?> evidence;
}

Future<void> _applyTransactionalPhase(
  pg.Connection connection,
  String databaseId,
  RivetMigrationArtifact migration,
  int phaseIndex, {
  required bool insertMigration,
}) async {
  final phase = migration.phases[phaseIndex];
  await connection.runTx((transaction) async {
    for (final statement in phase.statements) {
      await transaction.execute(statement, queryMode: pg.QueryMode.simple);
    }
    if (insertMigration) {
      await _insertMigration(transaction, databaseId, migration);
    }
    await transaction.execute(
      pg.Sql.named('''
        INSERT INTO _rivet.phase_receipts
          ("databaseId", "migrationId", "phaseId", checksum, "scopeId", status,
           "attemptId", evidence)
        VALUES (@databaseId, @migrationId, @phaseId, @checksum, @scopeId,
                'completed', NULL, '{}'::jsonb)
      '''),
      parameters: {
        'databaseId': databaseId,
        'migrationId': migration.id,
        'phaseId': phase.id,
        'checksum': migration.checksum,
        'scopeId': phase.scopeId,
      },
    );
  });
}

final class _HistoryRecord {
  _HistoryRecord({
    required this.id,
    required this.parentId,
    required this.checksum,
    required this.ordinal,
    required this.receipts,
  });

  final String id;
  final String? parentId;
  final String checksum;
  final int ordinal;
  final List<_Receipt> receipts;
}

final class _Receipt {
  const _Receipt({
    required this.phaseId,
    required this.checksum,
    required this.scopeId,
    required this.status,
    required this.attemptId,
    required this.evidence,
  });

  final String phaseId;
  final String checksum;
  final String scopeId;
  final String status;
  final String? attemptId;
  final Object? evidence;
}

Future<pg.Connection> _openConnection(RivetConnection configuration) {
  final uri = Uri.parse(configuration.url);
  if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
    throw ArgumentError.value(uri.scheme, 'url scheme', 'must be postgres or postgresql');
  }
  final credentials = _credentials(uri.userInfo);
  return pg.Connection.open(
    pg.Endpoint(
      host: uri.host.isEmpty ? 'localhost' : uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isEmpty || uri.pathSegments.first.isEmpty
          ? 'postgres'
          : uri.pathSegments.first,
      username: credentials.$1,
      password: credentials.$2,
    ),
    settings: pg.ConnectionSettings(
      connectTimeout: configuration.connectTimeout,
      sslMode: switch (configuration.sslMode) {
        RivetSslMode.verifyFull => pg.SslMode.verifyFull,
        RivetSslMode.require => pg.SslMode.require,
        RivetSslMode.disable => pg.SslMode.disable,
      },
      securityContext: configuration.securityContext,
      queryTimeout: const Duration(days: 3650),
    ),
  );
}

(String?, String?) _credentials(String userInfo) {
  if (userInfo.isEmpty) return (null, null);
  final separator = userInfo.indexOf(':');
  if (separator == -1) return (Uri.decodeComponent(userInfo), null);
  return (
    Uri.decodeComponent(userInfo.substring(0, separator)),
    Uri.decodeComponent(userInfo.substring(separator + 1)),
  );
}

import 'dart:async';
import 'dart:io';

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
    for (final migration in artifacts.migrations) {
      if (migration.phases.any(
        (phase) => phase.mode != RivetMigrationPhaseMode.transactional,
      )) {
        throw const RivetMigrationException(
          'This runner revision does not support nontransactional phases.',
        );
      }
    }
    await _withLockedConnection((session) async {
      await _bootstrap(session);
      final history = await _readHistory(session, artifacts.databaseId);
      _validateHistory(artifacts, history);
      for (final (migrationIndex, migration) in artifacts.migrations.indexed) {
        final completedPhases = migrationIndex < history.length
            ? history[migrationIndex].receipts.length
            : 0;
        for (var phaseIndex = completedPhases; phaseIndex < migration.phases.length; phaseIndex++) {
          await _applyTransactionalPhase(
            session,
            artifacts.databaseId,
            migration,
            phaseIndex,
            insertMigration: migrationIndex >= history.length && phaseIndex == 0,
          );
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
      ORDER BY m.ordinal, r."phaseId"
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
      if (receipt.phaseId != phase.id ||
          receipt.checksum != migration.checksum ||
          receipt.scopeId != phase.scopeId ||
          receipt.status != 'completed' ||
          receipt.attemptId != null ||
          receipt.evidence is! Map) {
        throw RivetMigrationException(
          'Migration ${migration.id} phase ${phase.id} has a mismatched receipt.',
        );
      }
    }
  }
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
      await transaction.execute(
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
      );
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

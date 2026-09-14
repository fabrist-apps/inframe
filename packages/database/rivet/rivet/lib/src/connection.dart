// Lifecycle contracts are documented on their entry-point types and in the package README.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;

import 'package:rivet/src/errors.dart';
import 'package:rivet/src/query.dart';
import 'package:rivet/src/relation.dart';
import 'package:rivet/src/schema.dart';

enum RivetSslMode { verifyFull, require, disable }

/// Observes a compiled data statement without exposing bound values.
typedef RivetStatementObserver = void Function(String sql);

/// Driver-independent PostgreSQL connection configuration.
final class RivetConnection {
  RivetConnection.url(
    this.url, {
    this.connectTimeout = const Duration(seconds: 10),
    RivetSslMode? sslMode,
    this.securityContext,
    this.onStatement,
  }) : sslMode = _resolveSslMode(url, sslMode);

  final String url;
  final Duration connectTimeout;
  final RivetSslMode sslMode;
  final SecurityContext? securityContext;
  final RivetStatementObserver? onStatement;
}

/// Options for the pool owned by a [RivetDb].
final class RivetPoolOptions {
  const RivetPoolOptions({
    this.maxConnections = 10,
    this.acquireTimeout = const Duration(seconds: 30),
  });

  final int maxConnections;
  final Duration acquireTimeout;
}

/// An owned connection pool used by generated Rivet databases.
final class RivetDb implements RivetExecutor {
  RivetDb._(this._pool, this._connection, this.name, this.tables);

  final _RivetPool _pool;
  final RivetConnection _connection;
  final String name;
  final List<RivetTableSchema<Object?, Object?>> tables;
  bool _closing = false;
  int _acceptedWork = 0;
  Completer<void>? _drained;
  Future<void>? _closeFuture;

  static Future<RivetDb> open({
    required String name,
    required RivetConnection connection,
    required RivetPoolOptions pool,
    required List<RivetTableSchema<Object?, Object?>> tables,
  }) async {
    if (name.isEmpty || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name', 'must be non-empty and contain no NUL characters');
    }
    if (pool.maxConnections <= 0) {
      throw ArgumentError.value(pool.maxConnections, 'maxConnections', 'must be positive');
    }
    if (pool.acquireTimeout <= Duration.zero) {
      throw ArgumentError.value(pool.acquireTimeout, 'acquireTimeout', 'must be positive');
    }
    if (connection.connectTimeout <= Duration.zero) {
      throw ArgumentError.value(connection.connectTimeout, 'connectTimeout', 'must be positive');
    }
    final uri = _parseConnectionUrl(connection.url);
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      throw ArgumentError.value(uri.scheme, 'url scheme', 'must be postgres or postgresql');
    }
    _validateSchemas(tables);
    final credentials = _credentials(uri.userInfo);
    final driverPool = _RivetPool(
      endpoint: pg.Endpoint(
        host: uri.host.isEmpty ? 'localhost' : uri.host,
        port: uri.hasPort ? uri.port : 5432,
        database: uri.pathSegments.isEmpty || uri.pathSegments.first.isEmpty
            ? 'postgres'
            : uri.pathSegments.first,
        username: credentials.$1,
        password: credentials.$2,
      ),
      settings: pg.ConnectionSettings(
        connectTimeout: connection.connectTimeout,
        sslMode: switch (connection.sslMode) {
          RivetSslMode.verifyFull => pg.SslMode.verifyFull,
          RivetSslMode.require => pg.SslMode.require,
          RivetSslMode.disable => pg.SslMode.disable,
        },
        securityContext: connection.securityContext,
        queryTimeout: const Duration(days: 3650),
      ),
      maxConnections: pool.maxConnections,
      acquireTimeout: pool.acquireTimeout,
    );
    return RivetDb._(driverPool, connection, name, List.unmodifiable(tables));
  }

  @override
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  ) async {
    _rejectUseInsideOwnTransaction();
    _acceptWork();
    try {
      return await _executeWith(_pool.run, query, decode);
    } finally {
      _finishWork();
    }
  }

  @override
  Future<int> executeAffected(RivetCompiledQuery query) async {
    _rejectUseInsideOwnTransaction();
    _acceptWork();
    try {
      return await _executeAffectedWith(_pool.run, query);
    } finally {
      _finishWork();
    }
  }

  Future<T> transaction<T>(Future<T> Function(RivetTransaction transaction) callback) async {
    _acceptWork();
    Object? callbackFailure;
    late RivetTransaction transaction;
    try {
      final result = await _pool.withConnection(
        (connection) => connection.runTx((session) async {
          transaction = RivetTransaction._(session, _connection);
          try {
            return await runZoned(
              () async {
                try {
                  return await callback(transaction);
                } catch (error) {
                  callbackFailure = error;
                  rethrow;
                }
              },
              zoneValues: {_transactionDatabaseZoneKey: this},
            );
          } finally {
            transaction._expire();
          }
        }),
      );
      await _runAfterCommitCallbacks(this, transaction._callbacks);
      return result;
    } on RivetException {
      rethrow;
    } on Object catch (error) {
      if (identical(error, callbackFailure)) rethrow;
      throw RivetDatabaseException('PostgreSQL transaction failed.', error);
    } finally {
      _finishWork();
    }
  }

  Future<void> afterCommit(FutureOr<void> Function() callback) async {
    if (Zone.current[_transactionDatabaseZoneKey] == this) {
      throw const RivetExecutorClosedException(
        'Use transaction.afterCommit inside this database transaction.',
      );
    }
    _acceptWork();
    try {
      await runZoned(
        () => Future<void>.sync(callback),
        zoneValues: {_afterCommitDatabaseZoneKey: this},
      );
    } finally {
      _finishWork();
    }
  }

  void _rejectUseInsideOwnTransaction() {
    if (Zone.current[_transactionDatabaseZoneKey] == this) {
      throw const RivetExecutorClosedException(
        'Use the transaction executor inside this database transaction.',
      );
    }
  }

  void _acceptWork() {
    if (_closing) {
      throw const RivetExecutorClosedException('The database is closing or closed.');
    }
    _acceptedWork++;
  }

  void _finishWork() {
    _acceptedWork--;
    if (_closing && _acceptedWork == 0) _drained?.complete();
  }

  Future<List<Row>> _executeWith<Row>(
    Future<T> Function<T>(Future<T> Function(pg.Session session) operation) run,
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  ) async {
    try {
      _connection.onStatement?.call(query.sql);
      final result = await run(
        (session) => session.execute(
          pg.Sql(query.sql, types: List.filled(query.parameters.length, pg.Type.unspecified)),
          parameters: query.parameters,
        ),
      );
      return [
        for (final row in result)
          decode(
            row.toList(growable: false),
            [for (var index = 0; index < row.length; index++) row.isSqlNull(index)],
          ),
      ];
    } on RivetException {
      rethrow;
    } on pg.ServerException catch (error) {
      throw _vectorCapabilityError(query, error) ??
          RivetDatabaseException('PostgreSQL query failed.', error);
    } catch (error) {
      throw RivetDatabaseException('PostgreSQL query failed.', error);
    }
  }

  Future<int> _executeAffectedWith(
    Future<T> Function<T>(Future<T> Function(pg.Session session) operation) run,
    RivetCompiledQuery query,
  ) async {
    try {
      _connection.onStatement?.call(query.sql);
      final result = await run(
        (session) => session.execute(
          pg.Sql(query.sql, types: List.filled(query.parameters.length, pg.Type.unspecified)),
          parameters: query.parameters,
        ),
      );
      return result.affectedRows;
    } on RivetException {
      rethrow;
    } on pg.ServerException catch (error) {
      throw _vectorCapabilityError(query, error) ??
          RivetDatabaseException('PostgreSQL mutation failed.', error);
    } catch (error) {
      throw RivetDatabaseException('PostgreSQL mutation failed.', error);
    }
  }

  Future<void> close() {
    if (Zone.current[_transactionDatabaseZoneKey] == this ||
        Zone.current[_afterCommitDatabaseZoneKey] == this) {
      throw const RivetExecutorClosedException(
        'Cannot close a database from its own transaction callback.',
      );
    }
    return _closeFuture ??= _drainAndClose();
  }

  Future<void> _drainAndClose() async {
    _closing = true;
    if (_acceptedWork > 0) {
      _drained = Completer<void>();
      await _drained!.future;
    }
    await _pool.close();
  }
}

final _transactionDatabaseZoneKey = Object();
final _afterCommitDatabaseZoneKey = Object();

Future<void> _runAfterCommitCallbacks(
  RivetDb database,
  List<FutureOr<void> Function()> callbacks,
) async {
  final failures = <AfterCommitFailure>[];
  for (final callback in callbacks) {
    try {
      await runZoned(
        () => Future<void>.sync(callback),
        zoneValues: {_afterCommitDatabaseZoneKey: database},
      );
    } on Object catch (error, stackTrace) {
      failures.add(AfterCommitFailure(error, stackTrace));
    }
  }
  if (failures.isNotEmpty) {
    throw AfterCommitException(List.unmodifiable(failures), alreadyCommitted: true);
  }
}

final class RivetTransaction implements RivetExecutor {
  RivetTransaction._(this._session, this._connection);

  final pg.TxSession _session;
  final RivetConnection _connection;
  bool _active = true;
  final List<FutureOr<void> Function()> _callbacks = [];

  void afterCommit(FutureOr<void> Function() callback) {
    if (!_active) {
      throw const RivetExecutorClosedException('The transaction executor has expired.');
    }
    _callbacks.add(callback);
  }

  @override
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  ) async {
    if (!_active) {
      throw const RivetExecutorClosedException('The transaction executor has expired.');
    }
    try {
      _connection.onStatement?.call(query.sql);
      final result = await _session.execute(
        pg.Sql(query.sql, types: List.filled(query.parameters.length, pg.Type.unspecified)),
        parameters: query.parameters,
      );
      return [
        for (final row in result)
          decode(
            row.toList(growable: false),
            [for (var index = 0; index < row.length; index++) row.isSqlNull(index)],
          ),
      ];
    } on RivetException {
      rethrow;
    } on pg.ServerException catch (error) {
      throw _vectorCapabilityError(query, error) ??
          RivetDatabaseException('PostgreSQL transaction query failed.', error);
    } catch (error) {
      throw RivetDatabaseException('PostgreSQL transaction query failed.', error);
    }
  }

  @override
  Future<int> executeAffected(RivetCompiledQuery query) async {
    if (!_active) {
      throw const RivetExecutorClosedException('The transaction executor has expired.');
    }
    try {
      _connection.onStatement?.call(query.sql);
      final result = await _session.execute(
        pg.Sql(query.sql, types: List.filled(query.parameters.length, pg.Type.unspecified)),
        parameters: query.parameters,
      );
      return result.affectedRows;
    } on RivetException {
      rethrow;
    } on pg.ServerException catch (error) {
      throw _vectorCapabilityError(query, error) ??
          RivetDatabaseException('PostgreSQL transaction mutation failed.', error);
    } catch (error) {
      throw RivetDatabaseException('PostgreSQL transaction mutation failed.', error);
    }
  }

  void _expire() => _active = false;
}

RivetCapabilityException? _vectorCapabilityError(
  RivetCompiledQuery query,
  pg.ServerException error,
) {
  if (query.requiredExtensions.contains('vector') &&
      const {'42704', '42883'}.contains(error.code)) {
    return RivetCapabilityException(
      'Vector queries require a compatible pgvector extension and operator classes.',
      error,
    );
  }
  return null;
}

final class _PoolWaiter {
  final completer = Completer<pg.Connection>();
  bool active = true;
}

final class _RivetPool {
  _RivetPool({
    required this.endpoint,
    required this.settings,
    required this.maxConnections,
    required this.acquireTimeout,
  });

  final pg.Endpoint endpoint;
  final pg.ConnectionSettings settings;
  final int maxConnections;
  final Duration acquireTimeout;
  final Queue<_PoolWaiter> _waiters = Queue();
  final List<pg.Connection> _idle = [];
  int _connectionCount = 0;
  int _borrowed = 0;
  bool _closing = false;
  Completer<void>? _closeCompleter;
  (Object, StackTrace)? _closeFailure;

  Future<T> run<T>(Future<T> Function(pg.Session session) operation) async {
    return withConnection(operation);
  }

  Future<T> withConnection<T>(
    Future<T> Function(pg.Connection connection) operation,
  ) async {
    final connection = await _acquire();
    try {
      return await operation(connection);
    } finally {
      await _release(connection);
    }
  }

  Future<pg.Connection> _acquire() async {
    if (_closing) throw const RivetExecutorClosedException('The database is closing or closed.');
    while (_idle.isNotEmpty) {
      final connection = _idle.removeLast();
      if (connection.isOpen) {
        _borrowed++;
        return connection;
      }
      _connectionCount--;
    }
    if (_connectionCount < maxConnections) {
      return _openConnection();
    }
    final waiter = _PoolWaiter();
    _waiters.add(waiter);
    try {
      return await waiter.completer.future.timeout(acquireTimeout);
    } on TimeoutException {
      waiter.active = false;
      _waiters.remove(waiter);
      throw TimeoutException('Timed out waiting for a Rivet pool connection.', acquireTimeout);
    }
  }

  Future<pg.Connection> _openConnection() async {
    _connectionCount++;
    late pg.Connection connection;
    try {
      connection = await pg.Connection.open(endpoint, settings: settings);
    } catch (error) {
      _connectionCount--;
      _serviceWaiter();
      _completeCloseIfDrained();
      rethrow;
    }
    if (_closing) {
      try {
        await connection.close();
      } on Object catch (error, stackTrace) {
        _closeFailure ??= (error, stackTrace);
      } finally {
        _connectionCount--;
        _completeCloseIfDrained();
      }
      throw const RivetExecutorClosedException('The database is closing or closed.');
    }
    _borrowed++;
    return connection;
  }

  Future<void> _release(pg.Connection connection) async {
    _borrowed--;
    if (!connection.isOpen) {
      _connectionCount--;
      _serviceWaiter();
      _completeCloseIfDrained();
      return;
    }
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (waiter.active) {
        waiter.active = false;
        _borrowed++;
        waiter.completer.complete(connection);
        return;
      }
    }
    if (_closing) {
      try {
        await connection.close();
      } on Object catch (error, stackTrace) {
        _closeFailure ??= (error, stackTrace);
      } finally {
        _connectionCount--;
        _completeCloseIfDrained();
      }
    } else {
      _idle.add(connection);
    }
  }

  void _serviceWaiter() {
    if (_closing || _connectionCount >= maxConnections) return;
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.active) continue;
      unawaited(
        _openConnection().then<void>(
          (connection) async {
            if (waiter.active) {
              waiter.active = false;
              waiter.completer.complete(connection);
            } else {
              await _release(connection);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (waiter.active) {
              waiter.active = false;
              waiter.completer.completeError(error, stackTrace);
            }
          },
        ),
      );
      return;
    }
  }

  Future<void> close() {
    if (_closeCompleter != null) return _closeCompleter!.future;
    _closing = true;
    _closeCompleter = Completer<void>();
    for (final waiter in _waiters) {
      waiter.active = false;
      waiter.completer.completeError(
        const RivetExecutorClosedException('The database is closing or closed.'),
      );
    }
    _waiters.clear();
    final idle = List<pg.Connection>.of(_idle);
    _idle.clear();
    unawaited(_closeIdle(idle));
    _completeCloseIfDrained();
    return _closeCompleter!.future;
  }

  Future<void> _closeIdle(List<pg.Connection> connections) async {
    for (final connection in connections) {
      try {
        await connection.close();
      } on Object catch (error, stackTrace) {
        _closeFailure ??= (error, stackTrace);
      } finally {
        _connectionCount--;
      }
    }
    _completeCloseIfDrained();
  }

  void _completeCloseIfDrained() {
    if (_closing && _borrowed == 0 && _connectionCount == 0) {
      final completer = _closeCompleter;
      if (completer != null && !completer.isCompleted) {
        final failure = _closeFailure;
        if (failure == null) {
          completer.complete();
        } else {
          completer.completeError(failure.$1, failure.$2);
        }
      }
    }
  }
}

void _validateSchemas(List<RivetTableSchema<Object?, Object?>> tables) {
  final physicalNames = <String>{};
  final registeredTables = <Type, RivetTableSchema<Object?, Object?>>{};
  for (final table in tables) {
    final definition = table.definition;
    if (definition == null) {
      throw ArgumentError(
        'Rivet table ${table.schemaName}.${table.tableName} has a null definition.',
      );
    }
    if (!physicalNames.add('${table.schemaName}.${table.tableName}')) {
      throw ArgumentError(
        'Duplicate Rivet table registration: ${table.schemaName}.${table.tableName}.',
      );
    }
    final type = definition.runtimeType;
    if (registeredTables[type] != null) {
      throw ArgumentError('Duplicate Rivet table type registration: $type.');
    }
    registeredTables[type] = table;
  }
  for (final table in tables) {
    for (final column in table.columns) {
      final foreignKey = column.foreignKey;
      if (foreignKey == null) continue;
      final target = registeredTables[foreignKey.targetTable];
      if (target == null) {
        throw ArgumentError(
          'Foreign key ${table.schemaName}.${table.tableName}.${column.physicalName} targets '
          '${foreignKey.targetTable}, which is not registered.',
        );
      }
      final referencedColumn = foreignKey.reference(target.definition!);
      if (!target.columns.contains(referencedColumn)) {
        throw ArgumentError(
          'Foreign key ${table.schemaName}.${table.tableName}.${column.physicalName} selects '
          'a column outside ${target.schemaName}.${target.tableName}.',
        );
      }
      if (column.codec.cast != referencedColumn.codec.cast) {
        throw ArgumentError(
          'Foreign key ${table.schemaName}.${table.tableName}.${column.physicalName} has storage '
          'type ${column.codec.cast}, but ${target.schemaName}.${target.tableName}.'
          '${referencedColumn.physicalName} has ${referencedColumn.codec.cast}.',
        );
      }
      foreignKey.referencedColumn = referencedColumn;
    }
    for (final relation in table.relations.entries) {
      final descriptor = relation.value;
      final target = registeredTables[descriptor.targetTable];
      if (target == null) {
        throw ArgumentError(
          'Relation ${table.schemaName}.${table.tableName}.${relation.key} targets '
          '${descriptor.targetTable}, which is not registered.',
        );
      }
      if (descriptor.through case final through? when registeredTables[through] == null) {
        throw ArgumentError(
          'Relation ${table.schemaName}.${table.tableName}.${relation.key} uses through table '
          '$through, which is not registered.',
        );
      }
      if (descriptor is RivetManyThroughRelation<dynamic, dynamic, dynamic>) {
        final junction = registeredTables[descriptor.through]!;
        descriptor.resolveThrough(junction.definition);
        final sourceRelation = descriptor.sourceRelation!;
        final targetRelation = descriptor.targetRelation!;
        if (!junction.relations.values.contains(sourceRelation) ||
            !junction.relations.values.contains(targetRelation) ||
            sourceRelation.targetTable != table.definition.runtimeType ||
            targetRelation.targetTable != target.definition.runtimeType) {
          throw ArgumentError(
            'Through relation ${table.schemaName}.${table.tableName}.${relation.key} must select '
            'junction one-relations to its source and target.',
          );
        }
      }
      descriptor.resolve(target.definition);
      if (descriptor.kind == RivetRelationKind.many && descriptor.inverseRelation == null) {
        final candidates = target.relations.values
            .where(
              (candidate) =>
                  candidate.kind == RivetRelationKind.one &&
                  candidate.targetTable == table.definition.runtimeType,
            )
            .toList(growable: false);
        if (candidates.length != 1) {
          throw ArgumentError(
            'Relation ${table.schemaName}.${table.tableName}.${relation.key} requires exactly one '
            'inverse relation on ${target.schemaName}.${target.tableName}; found '
            '${candidates.length}. Supply relation: to disambiguate.',
          );
        }
        descriptor.inverseRelation = candidates.single;
      }
      if (descriptor.kind == RivetRelationKind.one) {
        if (descriptor.fields.isEmpty || descriptor.fields.length != descriptor.references.length) {
          throw ArgumentError(
            'Relation ${table.schemaName}.${table.tableName}.${relation.key} must map the same '
            'non-zero number of source and target columns.',
          );
        }
        if (descriptor.fields.any((column) => !table.columns.contains(column)) ||
            descriptor.references.any((column) => !target.columns.contains(column))) {
          throw ArgumentError(
            'Relation ${table.schemaName}.${table.tableName}.${relation.key} selects columns '
            'outside its source or target table.',
          );
        }
        for (var index = 0; index < descriptor.fields.length; index++) {
          final sourceColumn = descriptor.fields[index];
          final targetColumn = descriptor.references[index];
          if (sourceColumn.codec.cast != targetColumn.codec.cast) {
            throw ArgumentError(
              'Relation ${table.schemaName}.${table.tableName}.${relation.key} maps '
              '${sourceColumn.codec.cast} to incompatible ${targetColumn.codec.cast}.',
            );
          }
        }
      }
      final inverse = descriptor.inverseRelation;
      if (inverse != null &&
          (!target.relations.values.contains(inverse) ||
              inverse.targetTable != table.definition.runtimeType)) {
        throw ArgumentError(
          'Relation ${table.schemaName}.${table.tableName}.${relation.key} selects an inverse '
          'relation outside ${target.schemaName}.${target.tableName}.',
        );
      }
    }
  }
}

RivetSslMode? _sslModeFromUrl(String url) {
  final value = _parseConnectionUrl(url).queryParameters['sslmode'];
  return switch (value) {
    null => null,
    'verify-full' => RivetSslMode.verifyFull,
    'require' => RivetSslMode.require,
    'disable' => RivetSslMode.disable,
    _ => throw ArgumentError.value(value, 'sslmode', 'must be verify-full, require, or disable'),
  };
}

Uri _parseConnectionUrl(String url) {
  try {
    return Uri.parse(url);
  } on FormatException {
    throw ArgumentError('url must be a valid PostgreSQL URL.');
  }
}

RivetSslMode _resolveSslMode(String url, RivetSslMode? explicit) {
  final fromUrl = _sslModeFromUrl(url);
  return explicit ?? fromUrl ?? RivetSslMode.verifyFull;
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

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;

import 'errors.dart';
import 'query.dart';
import 'schema.dart';

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
  }) : sslMode = sslMode ?? _sslModeFromUrl(url) ?? RivetSslMode.verifyFull;

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
  RivetDb._(this._pool, this._connection, this.tables);

  final _RivetPool _pool;
  final RivetConnection _connection;
  final List<RivetTableSchema<Object?, Object?>> tables;
  bool _closed = false;

  static Future<RivetDb> open({
    required RivetConnection connection,
    required RivetPoolOptions pool,
    required List<RivetTableSchema<Object?, Object?>> tables,
  }) async {
    if (pool.maxConnections <= 0) {
      throw ArgumentError.value(pool.maxConnections, 'maxConnections', 'must be positive');
    }
    _validateSchemas(tables);
    final uri = Uri.parse(connection.url);
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      throw ArgumentError.value(connection.url, 'url', 'must use postgres or postgresql');
    }
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
    return RivetDb._(driverPool, connection, List.unmodifiable(tables));
  }

  @override
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  ) async {
    if (_closed) {
      throw const RivetExecutorClosedException('The database is closing or closed.');
    }
    try {
      _connection.onStatement?.call(query.sql);
      final result = await _pool.run(
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
    } catch (error) {
      throw RivetDatabaseException('PostgreSQL query failed.', error);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _pool.close();
  }
}

final class _PoolWaiter {
  final completer = Completer<pg.Connection>();
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

  Future<T> run<T>(Future<T> Function(pg.Session session) operation) async {
    final connection = await _acquire();
    try {
      return await operation(connection);
    } finally {
      await _release(connection);
    }
  }

  Future<pg.Connection> _acquire() async {
    if (_closing) throw const RivetExecutorClosedException('The database is closing or closed.');
    if (_idle.isNotEmpty) {
      _borrowed++;
      return _idle.removeLast();
    }
    if (_connectionCount < maxConnections) {
      _connectionCount++;
      try {
        final connection = await pg.Connection.open(endpoint, settings: settings);
        if (_closing) {
          await connection.close();
          _connectionCount--;
          throw const RivetExecutorClosedException('The database is closing or closed.');
        }
        _borrowed++;
        return connection;
      } catch (_) {
        if (_connectionCount > 0 && _borrowed < _connectionCount) _connectionCount--;
        rethrow;
      }
    }
    final waiter = _PoolWaiter();
    _waiters.add(waiter);
    try {
      return await waiter.completer.future.timeout(acquireTimeout);
    } on TimeoutException {
      _waiters.remove(waiter);
      throw TimeoutException('Timed out waiting for a Rivet pool connection.', acquireTimeout);
    }
  }

  Future<void> _release(pg.Connection connection) async {
    _borrowed--;
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (!waiter.completer.isCompleted) {
        _borrowed++;
        waiter.completer.complete(connection);
        return;
      }
    }
    if (_closing) {
      await connection.close();
      _connectionCount--;
      _completeCloseIfDrained();
    } else {
      _idle.add(connection);
    }
  }

  Future<void> close() {
    if (_closeCompleter != null) return _closeCompleter!.future;
    _closing = true;
    _closeCompleter = Completer<void>();
    for (final waiter in _waiters) {
      waiter.completer.completeError(
        const RivetExecutorClosedException('The database is closing or closed.'),
      );
    }
    _waiters.clear();
    final idle = List<pg.Connection>.of(_idle);
    _idle.clear();
    Future.wait(idle.map((connection) => connection.close())).then((_) {
      _connectionCount -= idle.length;
      _completeCloseIfDrained();
    });
    _completeCloseIfDrained();
    return _closeCompleter!.future;
  }

  void _completeCloseIfDrained() {
    if (_closing && _borrowed == 0 && _connectionCount == 0) {
      final completer = _closeCompleter;
      if (completer != null && !completer.isCompleted) completer.complete();
    }
  }
}

void _validateSchemas(List<RivetTableSchema<Object?, Object?>> tables) {
  final physicalNames = <String>{};
  final registeredTypes = tables.map((table) => table.definition.runtimeType).toSet();
  for (final table in tables) {
    if (!physicalNames.add('${table.schemaName}.${table.tableName}')) {
      throw ArgumentError(
        'Duplicate Rivet table registration: ${table.schemaName}.${table.tableName}.',
      );
    }
    for (final relation in table.relations.entries) {
      if (!registeredTypes.contains(relation.value.targetTable)) {
        throw ArgumentError(
          'Relation ${table.schemaName}.${table.tableName}.${relation.key} targets '
          '${relation.value.targetTable}, which is not registered among $registeredTypes.',
        );
      }
    }
  }
}

RivetSslMode? _sslModeFromUrl(String url) {
  final value = Uri.parse(url).queryParameters['sslmode'];
  return switch (value) {
    null => null,
    'verify-full' || 'verify-ca' => RivetSslMode.verifyFull,
    'require' => RivetSslMode.require,
    'disable' => RivetSslMode.disable,
    _ => throw ArgumentError.value(value, 'sslmode', 'must be verify-full, require, or disable'),
  };
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

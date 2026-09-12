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
  const RivetPoolOptions({this.maxConnections = 10});

  final int maxConnections;
}

/// An owned connection pool used by generated Rivet databases.
final class RivetDb implements RivetExecutor {
  RivetDb._(this._pool, this._connection, this.tables);

  final pg.Pool<void> _pool;
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
    final uri = Uri.parse(connection.url);
    if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
      throw ArgumentError.value(connection.url, 'url', 'must use postgres or postgresql');
    }
    final credentials = _credentials(uri.userInfo);
    final driverPool = pg.Pool<void>.withEndpoints(
      [
        pg.Endpoint(
          host: uri.host.isEmpty ? 'localhost' : uri.host,
          port: uri.hasPort ? uri.port : 5432,
          database: uri.pathSegments.isEmpty || uri.pathSegments.first.isEmpty
              ? 'postgres'
              : uri.pathSegments.first,
          username: credentials.$1,
          password: credentials.$2,
        ),
      ],
      settings: pg.PoolSettings(
        maxConnectionCount: pool.maxConnections,
        connectTimeout: connection.connectTimeout,
        sslMode: switch (connection.sslMode) {
          RivetSslMode.verifyFull => pg.SslMode.verifyFull,
          RivetSslMode.require => pg.SslMode.require,
          RivetSslMode.disable => pg.SslMode.disable,
        },
        securityContext: connection.securityContext,
      ),
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
      final result = await _pool.execute(
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

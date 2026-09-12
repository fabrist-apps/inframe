import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/protocol.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// A client for one externally managed standalone Redis or Valkey endpoint.
final class Runnel {
  Runnel._(this._connection, this._commandTimeout);

  final RedisConnection _connection;
  final Duration _commandTimeout;
  Future<void>? _closing;

  /// Connects and completes the configured authentication, protocol, and database handshake.
  static Future<Runnel> connect(
    String endpoint, {
    RedisProtocol protocol = RedisProtocol.resp3,
    SecurityContext? securityContext,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration commandTimeout = const Duration(seconds: 5),
    Duration shutdownTimeout = const Duration(seconds: 5),
    RunnelLimits limits = const RunnelLimits(),
  }) async {
    final configuration = _Endpoint.parse(endpoint, securityContext: securityContext);
    _positive(connectTimeout, 'connectTimeout');
    _positive(commandTimeout, 'commandTimeout');
    _positive(shutdownTimeout, 'shutdownTimeout');
    limits.validate();
    final deadline = _Deadline(connectTimeout);

    RedisConnection? connection;
    try {
      connection = await RedisConnection.openWithLimits(
        host: configuration.host,
        port: configuration.port,
        tls: configuration.tls,
        securityContext: securityContext,
        limits: limits,
        timeout: deadline.remaining,
      );
      final handshake = <RedisArgument>[
        RedisArgument.text('HELLO'),
        RedisArgument.text('${protocol.version}'),
        if (configuration.password case final password?) ...[
          RedisArgument.text('AUTH'),
          RedisArgument.text(configuration.username ?? 'default'),
          RedisArgument.text(password),
        ],
      ];
      await connection
          .execute(RedisCommand<Object?>(handshake, (reply) => reply))
          .timeout(deadline.remaining);
      if (configuration.database != 0) {
        await connection
            .execute(
              RedisCommand<Object?>([
                RedisArgument.text('SELECT'),
                RedisArgument.text('${configuration.database}'),
              ], (reply) => reply),
            )
            .timeout(deadline.remaining);
      }
      return Runnel._(connection, commandTimeout);
    } on Object {
      await connection?.close();
      rethrow;
    }
  }

  /// Executes a custom ordinary typed command.
  Future<T> execute<T>(RedisCommand<T> command, {Duration? timeout}) {
    final deadline = timeout ?? _commandTimeout;
    _positive(deadline, 'timeout');
    return _connection.execute(command).timeout(deadline);
  }

  /// Checks that Redis can process an ordinary command.
  Future<bool> ping({Duration? timeout}) => execute(
    RedisCommand<bool>([RedisArgument.text('PING')], (reply) => respText(reply) == 'PONG'),
    timeout: timeout,
  );

  /// Reads a strict UTF-8 string, returning null for a missing key.
  Future<String?> get(String key, {Duration? timeout}) => execute(
    RedisCommand<String?>(
      [
        RedisArgument.text('GET'),
        RedisArgument.text(key),
      ],
      (reply) => switch (reply) {
        const RespNull() => null,
        _ => respText(reply),
      },
    ),
    timeout: timeout,
  );

  /// Reads arbitrary bytes, returning null for a missing key.
  Future<Uint8List?> getBytes(String key, {Duration? timeout}) => execute(
    RedisCommand<Uint8List?>(
      [
        RedisArgument.text('GET'),
        RedisArgument.text(key),
      ],
      (reply) => switch (reply) {
        const RespNull() => null,
        RespBlobString(:final value) => Uint8List.fromList(value),
        _ => throw const FormatException('Expected a binary GET reply.'),
      },
    ),
    timeout: timeout,
  );

  /// Stores a UTF-8 string and reports whether Redis applied the write.
  Future<bool> set(String key, String value, {Duration? timeout}) => execute(
    _setCommand(key, RedisArgument.text(value)),
    timeout: timeout,
  );

  /// Stores owned arbitrary bytes and reports whether Redis applied the write.
  Future<bool> setBytes(String key, Uint8List value, {Duration? timeout}) {
    final command = _setCommand(key, RedisArgument.bytes(value));
    return execute(command, timeout: timeout);
  }

  RedisCommand<bool> _setCommand(String key, RedisArgument value) => RedisCommand<bool>([
    RedisArgument.text('SET'),
    RedisArgument.text(key),
    value,
  ], (reply) => respText(reply) == 'OK');

  /// Releases the owned connection. Repeated calls share the same cleanup.
  Future<void> close() => _closing ??= _connection.close();
}

final class _Endpoint {
  const _Endpoint({
    required this.host,
    required this.port,
    required this.tls,
    required this.database,
    required this.username,
    required this.password,
  });

  factory _Endpoint.parse(String endpoint, {required SecurityContext? securityContext}) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || (uri.scheme != 'redis' && uri.scheme != 'rediss') || uri.host.isEmpty) {
      throw ArgumentError.value(
        _redact(endpoint),
        'endpoint',
        'must be a redis:// or rediss:// URL',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        _redact(endpoint),
        'endpoint',
        'query and fragment are unsupported',
      );
    }
    final tls = uri.scheme == 'rediss';
    if (!tls && securityContext != null) {
      throw ArgumentError.value(securityContext, 'securityContext', 'requires rediss://');
    }
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length > 1 || (uri.path.isNotEmpty && uri.path != '/' && segments.isEmpty)) {
      throw ArgumentError.value(_redact(endpoint), 'endpoint', 'database path is malformed');
    }
    final database = segments.isEmpty ? 0 : int.tryParse(segments.single);
    if (database == null ||
        database < 0 ||
        (segments.isNotEmpty && '$database' != segments.single)) {
      throw ArgumentError.value(
        _redact(endpoint),
        'endpoint',
        'database must be a nonnegative decimal',
      );
    }
    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final separator = uri.userInfo.indexOf(':');
      if (separator < 0) {
        password = Uri.decodeComponent(uri.userInfo);
      } else {
        final rawUsername = uri.userInfo.substring(0, separator);
        username = rawUsername.isEmpty ? null : Uri.decodeComponent(rawUsername);
        password = Uri.decodeComponent(uri.userInfo.substring(separator + 1));
      }
    }
    return _Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 6379,
      tls: tls,
      database: database,
      username: username,
      password: password,
    );
  }

  final String host;
  final int port;
  final bool tls;
  final int database;
  final String? username;
  final String? password;

  static String _redact(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.userInfo.isEmpty) return endpoint;
    return uri.replace(userInfo: '').toString();
  }
}

void _positive(Duration value, String name) {
  if (value <= Duration.zero) throw ArgumentError.value(value, name, 'must be positive');
}

final class _Deadline {
  _Deadline(this.duration) : _stopwatch = Stopwatch()..start();

  final Duration duration;
  final Stopwatch _stopwatch;

  Duration get remaining {
    final value = duration - _stopwatch.elapsed;
    if (value <= Duration.zero) throw TimeoutException('The connection deadline expired.');
    return value;
  }
}

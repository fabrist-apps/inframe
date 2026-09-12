import 'dart:async';
import 'dart:io';

import 'package:runnel/src/batch.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/command_validation.dart';
import 'package:runnel/src/connection/reconnect_backoff.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/protocol.dart';
import 'package:runnel/src/resp/resp_value.dart';
import 'package:runnel/src/scripts.dart';

/// A client for one externally managed standalone Redis or Valkey endpoint.
final class Runnel {
  Runnel._(
    this._endpoint,
    this._protocol,
    this._securityContext,
    this._connectTimeout,
    this._commandTimeout,
    this._shutdownTimeout,
    this._limits,
  );

  final _Endpoint _endpoint;
  final RedisProtocol _protocol;
  final SecurityContext? _securityContext;
  final Duration _connectTimeout;
  final Duration _commandTimeout;
  final Duration _shutdownTimeout;
  final RunnelLimits _limits;
  final ReconnectBackoff _backoff = ReconnectBackoff();
  final Set<RedisConnection> _transactionConnections = {};

  RedisConnection? _connection;
  Timer? _reconnectTimer;
  Future<void>? _closing;
  _ClientState _state = _ClientState.connecting;

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
    final client = Runnel._(
      configuration,
      protocol,
      securityContext,
      connectTimeout,
      commandTimeout,
      shutdownTimeout,
      limits,
    );
    try {
      client._connection = await client._openPhysicalConnection();
      client._state = _ClientState.ready;
      return client;
    } on Object {
      client._state = _ClientState.closed;
      rethrow;
    }
  }

  Future<RedisConnection> _openPhysicalConnection({Duration? timeout}) async {
    final deadline = _Deadline(timeout ?? _connectTimeout);
    RedisConnection? connection;
    try {
      connection = await RedisConnection.open(
        host: _endpoint.host,
        port: _endpoint.port,
        tls: _endpoint.tls,
        securityContext: _securityContext,
        limits: _limits,
        timeout: deadline.remaining,
        onTerminated: _connectionTerminated,
      );
      await connection.execute(
        RedisCommand<Object?>([
          RedisArgument.text('HELLO'),
          RedisArgument.text('${_protocol.version}'),
          if (_endpoint.password case final password?) ...[
            RedisArgument.text('AUTH'),
            RedisArgument.text(_endpoint.username ?? 'default'),
            RedisArgument.text(password),
          ],
        ], (reply) => reply),
        timeout: deadline.remaining,
        enforceLimits: false,
      );
      if (_endpoint.database != 0) {
        await connection.execute(
          RedisCommand<Object?>([
            RedisArgument.text('SELECT'),
            RedisArgument.text('${_endpoint.database}'),
          ], (reply) => reply),
          timeout: deadline.remaining,
          enforceLimits: false,
        );
      }
      return connection;
    } on Object {
      await connection?.close(commandsAreUncertain: true);
      rethrow;
    }
  }

  void _connectionTerminated(RedisConnection connection, Object cause) {
    if (!identical(_connection, connection)) return;
    _connection = null;
    if (_state == _ClientState.closing || _state == _ClientState.closed) return;
    if (cause is RedisProtocolException) {
      _state = _ClientState.closed;
      return;
    }
    _state = _ClientState.reconnecting;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_state != _ClientState.reconnecting || _reconnectTimer != null) return;
    final delay = _backoff.next();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (_state != _ClientState.reconnecting) return;
    try {
      final replacement = await _openPhysicalConnection();
      if (_state != _ClientState.reconnecting) {
        await replacement.close(commandsAreUncertain: true);
        return;
      }
      _connection = replacement;
      _backoff.reset();
      _state = _ClientState.ready;
    } on Object catch (error) {
      if (_terminalConnectFailure(error)) {
        _state = _ClientState.closed;
        return;
      }
      _scheduleReconnect();
    }
  }

  /// Executes a custom ordinary typed command.
  Future<T> execute<T>(RedisCommand<T> command, {Duration? timeout}) {
    final deadline = timeout ?? _commandTimeout;
    _positive(deadline, 'timeout');
    try {
      validateOrdinaryCommand(command as RedisCommand<Object?>);
    } on Object catch (error, stackTrace) {
      return Future.error(error, stackTrace);
    }
    if (_state == _ClientState.reconnecting || _state == _ClientState.connecting) {
      return Future.error(
        const RedisTransportException(
          message: 'The Redis connection is reconnecting; offline queuing is disabled.',
          deliveryStatus: RedisDeliveryStatus.notSent,
        ),
      );
    }
    final connection = _connection;
    if (_state != _ClientState.ready || connection == null || connection.isClosed) {
      return Future.error(const RedisClosedException(message: 'The Runnel client is closed.'));
    }
    return connection.execute(command, timeout: deadline);
  }

  /// Executes a typed Lua script, falling back to source only after NOSCRIPT.
  ///
  /// Both attempts share one deadline. The fallback is a later command, so callers
  /// should await script dependencies before submitting independent work.
  Future<T> runScript<T>(
    RedisScript<T> script, {
    required List<String> keys,
    required List<RedisArgument> arguments,
    Duration? timeout,
  }) async {
    final duration = timeout ?? _commandTimeout;
    _positive(duration, 'timeout');
    final acceptedAt = Stopwatch()..start();
    final ownedKeys = List<String>.unmodifiable(keys);
    final ownedArguments = List<RedisArgument>.unmodifiable(arguments);
    try {
      return await execute(
        evalshaCommand(script, keys: ownedKeys, arguments: ownedArguments),
        timeout: _scriptTimeRemaining(duration, acceptedAt),
      );
    } on RedisServerException catch (error) {
      if (error.code.toUpperCase() != 'NOSCRIPT') rethrow;
    }
    return execute(
      evalCommand(script, keys: ownedKeys, arguments: ownedArguments),
      timeout: _scriptTimeRemaining(duration, acceptedAt),
    );
  }

  /// Creates a typed, ordered pipeline builder without performing I/O.
  RedisBatch pipeline() => RedisBatch.internal(
    maxCommands: _limits.maxPendingCommands,
    maxBytes: _limits.maxPendingBytes,
    reservedCommands: 0,
    reservedBytes: 0,
    defaultTimeout: _commandTimeout,
    executor: _executePipeline,
  );

  /// Creates a typed MULTI/EXEC builder backed by a dedicated connection.
  RedisBatch transaction() {
    final framing =
        encodeCommand(_transactionFrame('MULTI')).length +
        encodeCommand(_transactionFrame('EXEC')).length;
    return RedisBatch.internal(
      maxCommands: _limits.maxPendingCommands,
      maxBytes: _limits.maxPendingBytes,
      reservedCommands: 2,
      reservedBytes: framing,
      defaultTimeout: _commandTimeout,
      executor: _executeTransaction,
    );
  }

  Future<List<BatchOutcome<Object?>>> _executePipeline(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
  ) async {
    final connection = _readyConnection();
    return settleBatch(connection.executeBatch(commands, timeout: timeout));
  }

  Future<List<BatchOutcome<Object?>>> _executeTransaction(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
  ) async {
    _readyConnection();
    final deadline = _Deadline(timeout);
    final connection = await _openPhysicalConnection(timeout: deadline.remaining);
    if (_state != _ClientState.ready) {
      await connection.close(commandsAreUncertain: true);
      throw const RedisClosedException(message: 'The Runnel client is closing.');
    }
    _transactionConnections.add(connection);
    try {
      final wireCommands = <RedisCommand<Object?>>[
        _transactionFrame('MULTI'),
        for (final command in commands) _queuedCommand(command),
        _transactionFrame('EXEC'),
      ];
      final replies = await settleBatch(
        connection.executeBatch(wireCommands, timeout: deadline.remaining),
      );
      _requireTransactionSuccess(replies.first, 'MULTI was rejected.');
      for (var index = 0; index < commands.length; index++) {
        _requireTransactionSuccess(replies[index + 1], 'A transaction command was rejected.');
      }
      final execReply = _requireTransactionSuccess(replies.last, 'EXEC was rejected.');
      if (execReply is RespNull) {
        throw const RedisTransactionException('EXEC did not commit the transaction.');
      }
      if (execReply is! RespArray || execReply.values.length != commands.length) {
        throw const RedisProtocolException(message: 'EXEC returned an invalid result array.');
      }
      return List.generate(commands.length, (index) {
        final reply = execReply.values[index];
        if (reply case RespError(:final code, :final message)) {
          return BatchFailure<Object?>(
            RedisServerException(code: code, message: message),
            StackTrace.current,
          );
        }
        try {
          return BatchSuccess<Object?>(commands[index].decode(reply));
        } on Object catch (error, stackTrace) {
          return BatchFailure<Object?>(error, stackTrace);
        }
      }, growable: false);
    } finally {
      _transactionConnections.remove(connection);
      await connection.close(commandsAreUncertain: !connection.isIdle);
    }
  }

  RedisConnection _readyConnection() {
    final connection = _connection;
    if (_state == _ClientState.reconnecting || _state == _ClientState.connecting) {
      throw const RedisTransportException(
        message: 'The Redis connection is reconnecting; offline queuing is disabled.',
        deliveryStatus: RedisDeliveryStatus.notSent,
      );
    }
    if (_state != _ClientState.ready || connection == null || connection.isClosed) {
      throw const RedisClosedException(message: 'The Runnel client is closed.');
    }
    return connection;
  }

  /// Checks that Redis can process an ordinary command.
  Future<bool> ping({Duration? timeout}) => execute(
    RedisCommand<bool>([RedisArgument.text('PING')], (reply) => respText(reply) == 'PONG'),
    timeout: timeout,
  );

  /// Drains accepted ordinary commands within the shutdown deadline, then releases resources.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_state == _ClientState.closed) return;
    _state = _ClientState.closing;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final connection = _connection;
    _connection = null;
    final transactions = List<RedisConnection>.of(_transactionConnections);
    _transactionConnections.clear();
    await Future.wait(
      transactions.map((transaction) => transaction.close(commandsAreUncertain: true)),
    );
    if (connection != null && !connection.isClosed) {
      try {
        await connection.waitUntilIdle().timeout(_shutdownTimeout);
        await connection.close();
      } on TimeoutException {
        await connection.close(commandsAreUncertain: true);
      }
    }
    _state = _ClientState.closed;
  }
}

Duration _scriptTimeRemaining(Duration timeout, Stopwatch stopwatch) {
  final remaining = timeout - stopwatch.elapsed;
  if (remaining <= Duration.zero) {
    throw const RedisTimeoutException(
      message: 'The Redis script deadline expired before submission.',
      deliveryStatus: RedisDeliveryStatus.notSent,
    );
  }
  return remaining;
}

RedisCommand<Object?> _transactionFrame(String name) => RedisCommand<Object?>(
  [RedisArgument.text(name)],
  (reply) => reply,
);

RedisCommand<Object?> _queuedCommand(RedisCommand<Object?> command) => RedisCommand<Object?>(
  command.arguments,
  (reply) => reply,
);

Object? _requireTransactionSuccess(BatchOutcome<Object?> outcome, String message) {
  return switch (outcome) {
    BatchSuccess<Object?>(:final value) => value,
    BatchFailure<Object?>(:final error, :final stackTrace) => Error.throwWithStackTrace(
      error is RunnelException ? error : RedisTransactionException(message, cause: error),
      stackTrace,
    ),
  };
}

enum _ClientState { connecting, ready, reconnecting, closing, closed }

bool _terminalConnectFailure(Object error) =>
    error is RedisServerException || error is RedisProtocolException || error is HandshakeException;

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

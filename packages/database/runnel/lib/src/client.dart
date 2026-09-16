import 'dart:async';
import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:runnel/src/batch.dart';
import 'package:runnel/src/blocking.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/command_validation.dart';
import 'package:runnel/src/connection/configuration.dart';
import 'package:runnel/src/connection/connection_attempt.dart';
import 'package:runnel/src/connection/legacy_errors.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/connection/reconnect_backoff.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/deadline.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/pubsub.dart';
import 'package:runnel/src/resp/resp_value.dart';
import 'package:runnel/src/scripts.dart';
import 'package:runnel/src/transaction.dart';

/// A client for one externally managed standalone Redis or Valkey endpoint.
final class Runnel {
  Runnel._(
    this._endpoint,
    this._connectTimeout,
    this._commandTimeout,
    this._shutdownTimeout,
    this._limits,
  );

  final ConnectionConfiguration _endpoint;
  final Duration _connectTimeout;
  final Duration _commandTimeout;
  final Duration _shutdownTimeout;
  final RunnelLimits _limits;
  final ReconnectBackoff _backoff = ReconnectBackoff();
  final Set<RedisConnection> _transactionConnections = {};
  final Set<RedisConnection> _unclaimedConnections = {};
  final Set<ConnectionAttempt> _openingConnections = {};
  final Set<BlockingSession> _blockingSessions = {};
  final Set<PubSubSession> _pubSubSessions = {};

  RedisConnection? _connection;
  Timer? _reconnectTimer;
  Future<void>? _closing;
  _ClientState _state = _ClientState.connecting;

  /// Connects and completes the configured authentication, RESP3, and database handshake.
  static Effect<Runnel, RunnelError> connect(
    String endpoint, {
    SecurityContext? securityContext,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration commandTimeout = const Duration(seconds: 5),
    Duration shutdownTimeout = const Duration(seconds: 5),
    RunnelLimits limits = const RunnelLimits(),
  }) => RunnelOperation.run(
    (operation) => _connect(
      endpoint,
      securityContext: securityContext,
      connectTimeout: connectTimeout,
      commandTimeout: commandTimeout,
      shutdownTimeout: shutdownTimeout,
      limits: limits,
      operation: operation,
    ),
  );

  static Future<Runnel> _connect(
    String endpoint, {
    required RunnelOperation operation,
    SecurityContext? securityContext,
    Duration connectTimeout = const Duration(seconds: 5),
    Duration commandTimeout = const Duration(seconds: 5),
    Duration shutdownTimeout = const Duration(seconds: 5),
    RunnelLimits limits = const RunnelLimits(),
  }) async {
    final configuration = RunnelOperation.validate(
      () => ConnectionConfiguration.parse(endpoint, securityContext: securityContext),
    );
    RunnelOperation.validate(() {
      _positive(connectTimeout, 'connectTimeout');
      _positive(commandTimeout, 'commandTimeout');
      _positive(shutdownTimeout, 'shutdownTimeout');
      limits.validate();
    });
    final client = Runnel._(
      configuration,
      connectTimeout,
      commandTimeout,
      shutdownTimeout,
      limits,
    );
    operation.onCancel(client._close);
    try {
      final connection = await client._openPhysicalConnection();
      if (operation.isCancelled) {
        await connection.close(commandsAreUncertain: true);
        throw const RedisClosedException(message: 'Connection acquisition cancelled.');
      }
      client
        .._unclaimedConnections.remove(connection)
        .._connection = connection
        .._state = _ClientState.ready;
      return client;
    } on Object {
      client._state = _ClientState.closed;
      rethrow;
    }
  }

  Future<RedisConnection> _openPhysicalConnection({
    Duration? timeout,
    RunnelOperation? operation,
  }) async {
    final deadline = ConnectionDeadline(timeout ?? _connectTimeout);
    final attempt = ConnectionAttempt();
    _openingConnections.add(attempt);
    final detach = operation?.onCancel(attempt.cancel);
    RedisConnection? connection;
    try {
      connection = await RedisConnection.open(
        host: _endpoint.host,
        port: _endpoint.port,
        tls: _endpoint.tls,
        securityContext: _endpoint.securityContext,
        limits: _limits,
        timeout: deadline.remaining,
        onTerminated: _connectionTerminated,
        attempt: attempt,
      );
      for (final command in _endpoint.handshakeCommands) {
        await connection.execute(command, timeout: deadline.remaining, enforceLimits: false);
      }
      if (operation?.isCancelled ?? false) {
        await connection.close(commandsAreUncertain: true);
        throw const RedisClosedException(message: 'Connection acquisition cancelled.');
      }
      _unclaimedConnections.add(connection);
      return connection;
    } on Object {
      await connection?.close(commandsAreUncertain: true);
      rethrow;
    } finally {
      detach?.call();
      attempt.finish();
      _openingConnections.remove(attempt);
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
        _unclaimedConnections.remove(replacement);
        await replacement.close(commandsAreUncertain: true);
        return;
      }
      _unclaimedConnections.remove(replacement);
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
  Effect<T, RunnelError> execute<T>(RedisCommand<T> command, {Duration? timeout}) =>
      RunnelOperation.run(
        (operation) => executeFuture(command, timeout: timeout, operation: operation),
      );

  /// Internal transport bridge for command families during the API migration.
  Future<T> executeFuture<T>(
    RedisCommand<T> command, {
    Duration? timeout,
    RunnelOperation? operation,
  }) {
    final deadline = timeout ?? _commandTimeout;
    RunnelOperation.validate(() => _positive(deadline, 'timeout'));
    try {
      RunnelOperation.validate(() => validateOrdinaryCommand(command as RedisCommand<Object?>));
    } on Object catch (error, stackTrace) {
      return Future.error(error, stackTrace);
    }
    final RedisConnection connection;
    try {
      connection = _readyConnection();
    } on Object catch (error, stackTrace) {
      return Future.error(error, stackTrace);
    }
    return connection.execute(command, timeout: deadline, operation: operation);
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
      return await executeFuture(
        evalshaCommand(script, keys: ownedKeys, arguments: ownedArguments),
        timeout: _scriptTimeRemaining(duration, acceptedAt),
      );
    } on RedisServerException catch (error) {
      if (error.code.toUpperCase() != 'NOSCRIPT') rethrow;
    }
    return executeFuture(
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
        transactionFrame('MULTI').encodedLength + transactionFrame('EXEC').encodedLength;
    return RedisBatch.internal(
      maxCommands: _limits.maxPendingCommands,
      maxBytes: _limits.maxPendingBytes,
      reservedCommands: 2,
      reservedBytes: framing,
      defaultTimeout: _commandTimeout,
      executor: _executeTransaction,
    );
  }

  /// Opens a dedicated connection for one blocking operation at a time.
  Effect<BlockingSession, RunnelError> blocking() => RunnelOperation.run(_blocking);

  Future<BlockingSession> _blocking(RunnelOperation operation) async {
    _readyConnection();
    late RedisConnection openingConnection;
    final session = await BlockingSession.internal(
      openConnection: () async =>
          openingConnection = await _openPhysicalConnection(operation: operation),
      commandTimeout: _commandTimeout,
      onClosed: _blockingSessions.remove,
      onCreated: (session) {
        _unclaimedConnections.remove(openingConnection);
        _blockingSessions.add(session);
      },
    );
    if (_state != _ClientState.ready || operation.isCancelled) {
      await session.closeFuture();
      throw const RedisClosedException(message: 'The Runnel client is closing.');
    }
    operation.onCancel(session.closeFuture);
    return session;
  }

  /// Opens a bounded, dynamically subscribed Pub/Sub session on a dedicated socket.
  Future<PubSubSession> openPubSub({
    Duration controlTimeout = const Duration(seconds: 5),
    PubSubLimits limits = const PubSubLimits(),
  }) async {
    _readyConnection();
    final session = await PubSubSession.connect(
      PubSubConnectionConfiguration(
        host: _endpoint.host,
        port: _endpoint.port,
        tls: _endpoint.tls,
        connectTimeout: _connectTimeout,
        connectionLimits: _limits,
        securityContext: _endpoint.securityContext,
        database: _endpoint.database,
        username: _endpoint.username,
        password: _endpoint.password,
      ),
      controlTimeout: controlTimeout,
      limits: limits,
      onClosed: _pubSubSessions.remove,
      onCreated: _pubSubSessions.add,
    );
    if (_state != _ClientState.ready) {
      await session.close();
      throw const RedisClosedException(message: 'The Runnel client is closing.');
    }
    return session;
  }

  Future<List<Result<Object?, RunnelError>>> _executePipeline(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
    RunnelOperation operation,
  ) async {
    final connection = _readyConnection();
    return settleBatch(connection.executeBatch(commands, timeout: timeout, operation: operation));
  }

  Future<List<Result<Object?, RunnelError>>> _executeTransaction(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
    RunnelOperation operation,
  ) async {
    _readyConnection();
    final deadline = ConnectionDeadline(timeout);
    final connection = await _openPhysicalConnection(
      timeout: deadline.remaining,
      operation: operation,
    );
    if (_state != _ClientState.ready || operation.isCancelled) {
      _unclaimedConnections.remove(connection);
      await connection.close(commandsAreUncertain: true);
      throw const RedisClosedException(message: 'The Runnel client is closing.');
    }
    _unclaimedConnections.remove(connection);
    _transactionConnections.add(connection);
    final detach = operation.onCancel(() => connection.close(commandsAreUncertain: true));
    try {
      return await executeTransaction(connection, commands, deadline);
    } finally {
      detach();
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
  Effect<bool, RunnelError> ping({Duration? timeout}) => execute(
    RedisCommand<bool>.internal([RedisArgument.text('PING')], (reply) => respText(reply) == 'PONG'),
    timeout: timeout,
  );

  /// Drains accepted ordinary commands within the shutdown deadline, then releases resources.
  Effect<void, Never> close() => RunnelOperation.release(() => _closing ??= _close());

  Future<void> _close() async {
    _state = _ClientState.closing;
    final deadline = ConnectionDeadline(_shutdownTimeout);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final connection = _connection;
    _connection = null;
    final transactions = List<RedisConnection>.of(_transactionConnections);
    _transactionConnections.clear();
    final blockingSessions = List<BlockingSession>.of(_blockingSessions);
    _blockingSessions.clear();
    final pubSubSessions = List<PubSubSession>.of(_pubSubSessions);
    _pubSubSessions.clear();
    final unclaimed = List<RedisConnection>.of(_unclaimedConnections);
    _unclaimedConnections.clear();
    final opening = List<ConnectionAttempt>.of(_openingConnections);
    _openingConnections.clear();
    await _withinShutdown(
      Future.wait([
        ...opening.map((attempt) => attempt.cancel()),
        ...blockingSessions.map((session) => session.closeFuture()),
        ...pubSubSessions.map((session) => session.close()),
        ...transactions.map(
          (transaction) => transaction.close(commandsAreUncertain: true),
        ),
        ...unclaimed.map(
          (connection) => connection.close(commandsAreUncertain: true),
        ),
      ]),
      deadline,
    );
    if (connection != null && !connection.isClosed) {
      try {
        await connection.waitUntilIdle().timeout(deadline.remaining);
        await connection.close().timeout(deadline.remaining);
      } on TimeoutException {
        await connection.close(commandsAreUncertain: true);
      }
    }
    _state = _ClientState.closed;
  }
}

Future<void> _withinShutdown(Future<void> work, ConnectionDeadline deadline) async {
  try {
    await work.timeout(deadline.remaining);
  } on TimeoutException {
    // Every release has started; shutdown must not outlive its deadline.
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

enum _ClientState { connecting, ready, reconnecting, closing, closed }

bool _terminalConnectFailure(Object error) =>
    error is RedisServerException || error is RedisProtocolException || error is HandshakeException;

void _positive(Duration value, String name) {
  if (value <= Duration.zero) throw ArgumentError.value(value, name, 'must be positive');
}

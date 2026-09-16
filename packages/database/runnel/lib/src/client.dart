import 'dart:async';
import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/src/batch.dart';
import 'package:runnel/src/blocking.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/command_validation.dart';
import 'package:runnel/src/connection/configuration.dart';
import 'package:runnel/src/connection/connection_attempt.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/connection/reconnect_backoff.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/connection/resources.dart';
import 'package:runnel/src/deadline.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/pubsub.dart';
import 'package:runnel/src/pubsub/session.dart' show PubSubSessionOwnership;
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
  final ClientResources _resources = ClientResources();

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
      final ownership = client._resources.register();
      final connection = await client._openPhysicalConnection(ownership);
      if (operation.isCancelled) {
        await connection.close(commandsAreUncertain: true);
        throw RunnelClosedError(
          'Connection acquisition cancelled.',
          stackTrace: StackTrace.current,
        );
      }
      ownership.detach();
      client
        .._connection = connection
        .._state = _ClientState.ready;
      return client;
    } on Object {
      client._state = _ClientState.closed;
      rethrow;
    }
  }

  Future<RedisConnection> _openPhysicalConnection(
    ResourceRegistration ownership, {
    Deadline? deadline,
  }) async {
    final budget = deadline ?? Deadline(_connectTimeout);
    final attempt = ConnectionAttempt();
    ownership.replace(attempt.cancel);
    RedisConnection? connection;
    try {
      connection = await RedisConnection.open(
        host: _endpoint.host,
        port: _endpoint.port,
        tls: _endpoint.tls,
        securityContext: _endpoint.securityContext,
        limits: _limits,
        deadline: budget,
        onTerminated: _connectionTerminated,
        attempt: attempt,
      );
      for (final command in _endpoint.handshakeCommands) {
        await connection.execute(
          command,
          deadline: budget,
          enforceLimits: false,
        );
      }
      final acquired = connection;
      ownership.replace(() => acquired.close(commandsAreUncertain: true));
      return connection;
    } on Object {
      await connection?.close(commandsAreUncertain: true);
      await ownership.close();
      rethrow;
    } finally {
      attempt.finish();
    }
  }

  /// Keeps acquisition owned by both the client and its interrupted caller.
  Future<T> _acquire<T>(
    RunnelOperation operation,
    Future<T> Function(ResourceRegistration ownership) open,
  ) async {
    final ownership = _resources.register();
    operation.onCancel(ownership.close);
    try {
      final resource = await open(ownership);
      ownership.checkOpen();
      return resource;
    } on Object {
      await ownership.close();
      rethrow;
    }
  }

  void _connectionTerminated(RedisConnection connection, Object cause) {
    if (!identical(_connection, connection)) return;
    _connection = null;
    if (_state == _ClientState.closing || _state == _ClientState.closed) return;
    if (cause is RunnelProtocolError) {
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
      final ownership = _resources.register();
      final replacement = await _openPhysicalConnection(ownership);
      if (_state != _ClientState.reconnecting) {
        await ownership.close();
        return;
      }
      ownership.detach();
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
        (operation) => _execute(command, timeout: timeout, operation: operation),
      );

  Future<T> _execute<T>(
    RedisCommand<T> command, {
    Duration? timeout,
    RunnelOperation? operation,
  }) {
    final duration = timeout ?? _commandTimeout;
    RunnelOperation.validate(() {
      _positive(duration, 'timeout');
      validateOrdinaryCommand(command as RedisCommand<Object?>);
    });
    return _readyConnection().execute(command, deadline: Deadline(duration), operation: operation);
  }

  /// Executes a typed Lua script, falling back to source only after NOSCRIPT.
  ///
  /// Both attempts share one deadline. The fallback is a later command, so callers
  /// should await script dependencies before submitting independent work.
  Effect<T, RunnelError> runScript<T>(
    RedisScript<T> script, {
    required List<String> keys,
    required List<RedisArgument> arguments,
    Duration? timeout,
  }) {
    final ownedKeys = List<String>.unmodifiable(keys);
    final ownedArguments = List<RedisArgument>.unmodifiable(arguments);
    final duration = timeout ?? _commandTimeout;
    return RunnelOperation.run((operation) async {
      RunnelOperation.validate(() => _positive(duration, 'timeout'));
      final deadline = Deadline(duration);
      Future<Result<T, RunnelError>> submit(RedisCommand<T> command) {
        if (operation.isCancelled) {
          throw const RunnelClosedError('Script execution cancelled.');
        }
        if (deadline.isExpired) {
          throw const RunnelTimeoutError(
            'The Redis script deadline expired before submission.',
            deliveryStatus: Some(RedisDeliveryStatus.notSent),
          );
        }
        return _readyConnection().executeDecoded(
          command,
          deadline: deadline,
          operation: operation,
        );
      }

      final Result<T, RunnelError> result;
      try {
        result = await submit(evalshaCommand(script, keys: ownedKeys, arguments: ownedArguments));
      } on RunnelServerError catch (error) {
        if (error.code.toUpperCase() != 'NOSCRIPT') rethrow;
        return (await submit(evalCommand(script, keys: ownedKeys, arguments: ownedArguments)))
            .getOrThrowWith((error) => error);
      }
      return result.getOrThrowWith((error) => error);
    });
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

  Future<BlockingSession> _blocking(RunnelOperation operation) {
    _readyConnection();
    return _acquire(operation, (ownership) async {
      final session = await BlockingSessionAccess.internal(
        openConnection: () => _openPhysicalConnection(ownership),
        commandTimeout: _commandTimeout,
        onClosed: (_) => ownership.detach(),
        onCreated: (session) => ownership.replace(session.closeFuture),
      );
      if (_state != _ClientState.ready || operation.isCancelled) {
        await session.closeFuture();
        throw const RunnelClosedError('The Runnel client is closing.');
      }
      return session;
    });
  }

  /// Opens a bounded, dynamically subscribed Pub/Sub session on a dedicated socket.
  Effect<PubSubSession, RunnelError> openPubSub({
    Duration controlTimeout = const Duration(seconds: 5),
    PubSubLimits limits = const PubSubLimits(),
  }) => RunnelOperation.run((operation) {
    _readyConnection();
    return _acquire(operation, (ownership) async {
      final session = await PubSubSessionOwnership.connect(
        _endpoint,
        connectTimeout: _connectTimeout,
        connectionLimits: _limits,
        controlTimeout: controlTimeout,
        limits: limits,
        onClosed: (_) => ownership.detach(),
        onCreated: (session) => ownership.replace(session.closeFuture),
      );
      if (_state != _ClientState.ready || operation.isCancelled) {
        await session.closeFuture();
        throw const RunnelClosedError('The Runnel client is closing.');
      }
      return session;
    });
  });

  Future<List<Result<Object?, RunnelError>>> _executePipeline(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
    RunnelOperation operation,
  ) async {
    final connection = _readyConnection();
    return settleBatch(
      connection.executeBatch(commands, deadline: Deadline(timeout), operation: operation),
    );
  }

  Future<List<Result<Object?, RunnelError>>> _executeTransaction(
    List<RedisCommand<Object?>> commands,
    Duration timeout,
    RunnelOperation operation,
  ) async {
    _readyConnection();
    final deadline = Deadline(timeout);
    final ownership = _resources.register();
    final detach = operation.onCancel(ownership.close);
    try {
      final connection = await _openPhysicalConnection(ownership, deadline: deadline);
      ownership.checkOpen();
      if (_state != _ClientState.ready || operation.isCancelled) {
        throw const RunnelClosedError('The Runnel client is closing.');
      }
      return await executeTransaction(connection, commands, deadline);
    } finally {
      detach();
      await ownership.close();
    }
  }

  RedisConnection _readyConnection() {
    final connection = _connection;
    if (_state == _ClientState.reconnecting || _state == _ClientState.connecting) {
      throw RunnelTransportError(
        'The Redis connection is reconnecting; offline queuing is disabled.',
        deliveryStatus: const Some(RedisDeliveryStatus.notSent),
        stackTrace: StackTrace.current,
      );
    }
    if (_state != _ClientState.ready || connection == null || connection.isClosed) {
      throw RunnelClosedError('The Runnel client is closed.', stackTrace: StackTrace.current);
    }
    return connection;
  }

  /// Checks that Redis can process an ordinary command.
  Effect<bool, RunnelError> ping({Duration? timeout}) => execute(
    builtInCommand<bool>([RedisArgument.text('PING')], (reply) => respText(reply) == 'PONG'),
    timeout: timeout,
  );

  /// Drains accepted ordinary commands within the shutdown deadline, then releases resources.
  Effect<void, Never> close() => RunnelOperation.release(() => _closing ??= _close());

  Future<void> _close() async {
    _state = _ClientState.closing;
    final deadline = Deadline(_shutdownTimeout);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final connection = _connection;
    _connection = null;
    await _withinShutdown(_resources.close(), deadline);
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

Future<void> _withinShutdown(Future<void> work, Deadline deadline) async {
  try {
    await work.timeout(deadline.remaining);
  } on TimeoutException {
    // Every release has started; shutdown must not outlive its deadline.
  }
}

enum _ClientState { connecting, ready, reconnecting, closing, closed }

bool _terminalConnectFailure(Object error) =>
    error is RunnelServerError || error is RunnelProtocolError || error is HandshakeException;

void _positive(Duration value, String name) {
  if (value <= Duration.zero) throw ArgumentError.value(value, name, 'must be positive');
}

import 'dart:async';

import 'package:runnel/src/command.dart';
import 'package:runnel/src/commands/streams.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// Opens one fully configured physical connection for a blocking session.
///
/// This is a package integration seam. Applications create sessions through
/// `Runnel.blocking`, which supplies its inherited endpoint configuration.
typedef BlockingConnectionFactory = Future<RedisConnection> Function();

/// A dedicated connection for one active blocking Redis operation at a time.
///
/// A transport failure or client deadline makes the session terminal. Create a
/// new session instead of replaying a blocking operation whose outcome is
/// uncertain.
final class BlockingSession {
  BlockingSession._(this._connection, this._commandTimeout, this._onClosed);

  /// Creates a session from Runnel's inherited physical-connection factory.
  ///
  /// This constructor is public only so the package's separate Dart libraries
  /// can compose the client. Applications use `Runnel.blocking`.
  static Future<BlockingSession> internal({
    required BlockingConnectionFactory openConnection,
    Duration commandTimeout = const Duration(seconds: 5),
    void Function(BlockingSession session)? onClosed,
    void Function(BlockingSession session)? onCreated,
  }) async {
    _requirePositive(commandTimeout, 'commandTimeout');
    final connection = await openConnection();
    final session = BlockingSession._(connection, commandTimeout, onClosed);
    onCreated?.call(session);
    return session;
  }

  final RedisConnection _connection;
  final Duration _commandTimeout;
  final void Function(BlockingSession session)? _onClosed;

  bool _active = false;
  bool _closed = false;
  Future<void>? _closing;

  /// Removes and returns the first available element from [keys].
  Future<({String key, String value})?> blpop(
    List<String> keys, {
    required Duration wait,
    Duration? timeout,
  }) => _pop('BLPOP', keys, wait: wait, timeout: timeout);

  /// Removes and returns the last available element from [keys].
  Future<({String key, String value})?> brpop(
    List<String> keys, {
    required Duration wait,
    Duration? timeout,
  }) => _pop('BRPOP', keys, wait: wait, timeout: timeout);

  /// Reads Stream entries newer than each concrete cursor, waiting when empty.
  Future<List<StreamRead>> xread(
    Map<String, StreamId> after, {
    required Duration wait,
    int? count,
    Duration? timeout,
  }) {
    _requireWholeMillisecondWait(wait);
    if (after.isEmpty) {
      throw ArgumentError.value(after, 'after', 'must not be empty');
    }
    if (count != null && count <= 0) {
      throw RangeError.range(count, 1, null, 'count');
    }
    final deadline = timeout ?? wait + _commandTimeout;
    _requirePositive(deadline, 'timeout');
    return _execute(
      () {
        final ordinary = xreadCommand(after, count: count);
        final arguments = ordinary.arguments;
        final streamsIndex = count == null ? 1 : 3;
        return RedisCommand<List<StreamRead>>([
          ...arguments.take(streamsIndex),
          RedisArgument.text('BLOCK'),
          RedisArgument.text('${wait.inMilliseconds}'),
          ...arguments.skip(streamsIndex),
        ], ordinary.decode);
      },
      timeout: deadline,
    );
  }

  Future<({String key, String value})?> _pop(
    String command,
    List<String> keys, {
    required Duration wait,
    required Duration? timeout,
  }) {
    _requireWholeMillisecondWait(wait);
    if (keys.isEmpty) {
      throw ArgumentError.value(keys, 'keys', 'must not be empty');
    }
    final deadline = timeout ?? wait + _commandTimeout;
    _requirePositive(deadline, 'timeout');
    return _execute(
      () => RedisCommand<({String key, String value})?>([
        RedisArgument.text(command),
        for (final key in keys) RedisArgument.text(key),
        RedisArgument.text(_secondsArgument(wait)),
      ], _popReply),
      timeout: deadline,
    );
  }

  Future<T> _execute<T>(
    RedisCommand<T> Function() buildCommand, {
    required Duration timeout,
  }) async {
    if (_closed || _connection.isClosed) {
      _markClosed();
      throw const RedisClosedException(message: 'The blocking session is closed.');
    }
    if (_active) {
      throw StateError('A blocking operation is already active on this session.');
    }
    _active = true;
    final elapsed = Stopwatch()..start();
    try {
      final command = buildCommand();
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        throw const RedisTimeoutException(
          message: 'The blocking operation deadline expired during local encoding.',
          deliveryStatus: RedisDeliveryStatus.notSent,
        );
      }
      final result = await _connection.execute(command, timeout: remaining);
      if (elapsed.elapsed >= timeout) {
        throw const RedisTimeoutException(
          message: 'The blocking operation deadline expired during reply decoding.',
          deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
        );
      }
      return result;
    } on Object catch (error, stackTrace) {
      if (_isTerminal(error) || _connection.isClosed) {
        _markClosed();
        await _connection.close(commandsAreUncertain: true);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _active = false;
    }
  }

  /// Immediately destroys the dedicated connection and interrupts active work.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _markClosed();
    await _connection.close(commandsAreUncertain: true);
  }

  void _markClosed() {
    if (_closed) return;
    _closed = true;
    _onClosed?.call(this);
  }
}

({String key, String value})? _popReply(RespValue reply) {
  if (reply is RespNull) return null;
  if (reply case RespArray(:final values) when values.length == 2) {
    return (key: respText(values[0]), value: respText(values[1]));
  }
  throw FormatException('Expected a two-value blocking pop reply, received ${reply.runtimeType}.');
}

bool _isTerminal(Object error) =>
    error is RedisTransportException ||
    error is RedisTimeoutException ||
    error is RedisProtocolException ||
    error is RedisClosedException ||
    error is FormatException;

void _requireWholeMillisecondWait(Duration wait) {
  if (wait <= Duration.zero || wait.inMicroseconds % Duration.microsecondsPerMillisecond != 0) {
    throw ArgumentError.value(wait, 'wait', 'must be positive whole milliseconds');
  }
}

void _requirePositive(Duration duration, String name) {
  if (duration <= Duration.zero) {
    throw ArgumentError.value(duration, name, 'must be positive');
  }
}

String _secondsArgument(Duration wait) {
  final milliseconds = wait.inMilliseconds;
  final wholeSeconds = milliseconds ~/ Duration.millisecondsPerSecond;
  final remainder = milliseconds % Duration.millisecondsPerSecond;
  if (remainder == 0) return '$wholeSeconds';
  final fraction = remainder.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
  return '$wholeSeconds.$fraction';
}

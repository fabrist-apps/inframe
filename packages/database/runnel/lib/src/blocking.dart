import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/commands/streams.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/deadline.dart';
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

  final RedisConnection _connection;
  final Duration _commandTimeout;
  final void Function(BlockingSession session)? _onClosed;

  bool _active = false;
  bool _closed = false;
  Future<void>? _closing;

  /// Removes and returns the first available element from [keys].
  Effect<Option<({String key, String value})>, RunnelError> blpop(
    List<String> keys, {
    required Duration wait,
    Duration? timeout,
  }) => _pop('BLPOP', keys, wait: wait, timeout: timeout);

  /// Removes and returns the last available element from [keys].
  Effect<Option<({String key, String value})>, RunnelError> brpop(
    List<String> keys, {
    required Duration wait,
    Duration? timeout,
  }) => _pop('BRPOP', keys, wait: wait, timeout: timeout);

  /// Reads Stream entries newer than each concrete cursor, waiting when empty.
  Effect<List<StreamRead>, RunnelError> xread(
    Map<String, StreamId> after, {
    required Duration wait,
    int? count,
    Duration? timeout,
  }) {
    final captured = Map<String, StreamId>.unmodifiable(after);
    return _execute(() {
      _requireWholeMillisecondWait(wait);
      final ordinary = xreadCommand(captured, count: count);
      final arguments = ordinary.arguments;
      final streamsIndex = count == null ? 1 : 3;
      return RedisCommand<List<StreamRead>>([
        ...arguments.take(streamsIndex),
        RedisArgument.text('BLOCK'),
        RedisArgument.text('${wait.inMilliseconds}'),
        ...arguments.skip(streamsIndex),
      ], ordinary.decode);
    }, timeout: timeout ?? wait + _commandTimeout);
  }

  Effect<Option<({String key, String value})>, RunnelError> _pop(
    String command,
    List<String> keys, {
    required Duration wait,
    required Duration? timeout,
  }) {
    final captured = List<String>.unmodifiable(keys);
    return _execute(() {
      _requireWholeMillisecondWait(wait);
      if (captured.isEmpty) throw ArgumentError.value(captured, 'keys', 'must not be empty');
      return builtInCommand<Option<({String key, String value})>>([
        RedisArgument.text(command),
        ...captured.map(RedisArgument.text),
        RedisArgument.text(_secondsArgument(wait)),
      ], _popReply);
    }, timeout: timeout ?? wait + _commandTimeout);
  }

  Effect<T, RunnelError> _execute<T>(
    RedisCommand<T> Function() buildCommand, {
    required Duration timeout,
  }) => RunnelOperation.run((operation) async {
    RunnelOperation.validate(() => _requirePositive(timeout, 'timeout'));
    if (_closed || _connection.isClosed) {
      _markClosed();
      throw RunnelClosedError('The blocking session is closed.', stackTrace: StackTrace.current);
    }
    if (_active) {
      throw const RunnelUsageError('A blocking operation is already active on this session.');
    }
    _active = true;
    final deadline = Deadline(timeout);
    final detach = operation.onCancel(closeFuture);
    try {
      final command = RunnelOperation.validate(buildCommand);
      final remaining = deadline.timeLeft;
      if (remaining <= Duration.zero) {
        throw RunnelTimeoutError(
          'The blocking operation deadline expired during local encoding.',
          deliveryStatus: const Some(RedisDeliveryStatus.notSent),
          stackTrace: StackTrace.current,
        );
      }
      final result = await _connection.execute(command, deadline: deadline);
      if (deadline.isExpired) {
        throw RunnelTimeoutError(
          'The blocking operation deadline expired during reply decoding.',
          deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
          stackTrace: StackTrace.current,
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
      detach();
      _active = false;
    }
  });

  /// Immediately destroys the dedicated connection and interrupts active work.
  Effect<void, Never> close() => RunnelOperation.release(closeFuture);

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

Option<({String key, String value})> _popReply(RespValue reply) {
  if (reply is RespNull) return const None();
  if (reply case RespArray(:final values) when values.length == 2) {
    return Some((key: respText(values[0]), value: respText(values[1])));
  }
  throw FormatException('Expected a two-value blocking pop reply, received ${reply.runtimeType}.');
}

bool _isTerminal(Object error) =>
    error is RunnelTransportError ||
    error is RunnelTimeoutError ||
    error is RunnelProtocolError ||
    error is RunnelClosedError ||
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

/// Internal release boundary used by the owning Runnel client.
extension BlockingSessionAccess on BlockingSession {
  /// Creates a session from Runnel's inherited physical-connection factory.
  ///
  /// Applications use `Runnel.blocking`; this extension is not exported.
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

  /// Releases without starting a separate Effect runtime.
  Future<void> closeFuture() => _closing ??= _close();
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:conflux/result.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/connection_attempt.dart';
import 'package:runnel/src/connection/legacy_errors.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/resp/resp_parser.dart';
import 'package:runnel/src/resp/resp_value.dart';

// This class is package-internal; callers use the documented Runnel API.

/// Receives an unexpected terminal failure from [connection].
typedef ConnectionTerminated = void Function(RedisConnection connection, Object cause);

/// One physical socket owns submission order, reply alignment, timers, and reservations.
///
/// Accepted commands remain in [_pending] until their reply or terminal failure. Removing a
/// submitted slot without closing the generation would let a late reply complete another command,
/// so submitted timeouts always terminate the connection and every submitted sibling.
final class RedisConnection {
  RedisConnection._(this._socket, this._limits, this._onTerminated)
    : _parser = RespParser(
        maxFrameBytes: _limits.maxFrameBytes,
        maxNestingDepth: _limits.maxNestingDepth,
      ) {
    _subscription = _socket.listen(
      _onBytes,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  final ConnectionSocket _socket;
  final RunnelLimits _limits;
  final ConnectionTerminated _onTerminated;
  final RespParser _parser;
  late final StreamSubscription<Uint8List> _subscription;
  final List<_Pending<Object?>> _pending = [];
  var _pendingBytes = 0;
  var _flushScheduled = false;
  var _closed = false;
  Completer<void>? _idle;

  /// Whether this physical connection has released its socket.
  bool get isClosed => _closed;

  /// Whether every accepted command has settled.
  bool get isIdle => _pending.isEmpty;

  /// Number of commands accepted and awaiting settlement.
  int get pendingCount => _pending.length;

  /// Encoded bytes reserved by commands awaiting settlement.
  int get pendingBytes => _pendingBytes;

  /// Opens one physical connection and transfers its ownership to the returned instance.
  static Future<RedisConnection> open({
    required String host,
    required int port,
    required bool tls,
    required SecurityContext? securityContext,
    required RunnelLimits limits,
    required Duration timeout,
    required ConnectionTerminated onTerminated,
    ConnectionAttempt? attempt,
  }) async {
    final socket = await openSocket(
      host: host,
      port: port,
      tls: tls,
      securityContext: securityContext,
      timeout: timeout,
      attempt: attempt,
    );
    final connection = RedisConnection._(socket, limits, onTerminated);
    if (!(attempt?.attachResource(
          () => connection.close(commandsAreUncertain: true),
        ) ??
        true)) {
      await connection.close(commandsAreUncertain: true);
      throw const RedisClosedException(message: 'The connection attempt was cancelled.');
    }
    return connection;
  }

  /// Accepts [command] for ordered execution within [timeout].
  Future<T> execute<T>(
    RedisCommand<T> command, {
    required Duration timeout,
    bool enforceLimits = true,
    RunnelOperation? operation,
  }) {
    final acceptedAt = Stopwatch()..start();
    if (_closed) {
      return Future.error(const RedisClosedException(message: 'The Redis connection is closed.'));
    }
    final encoded = encodeCommand(command as RedisCommand<Object?>);
    try {
      final remaining = _admit(
        count: 1,
        bytes: encoded.length,
        acceptedAt: acceptedAt,
        timeout: timeout,
        enforceLimits: enforceLimits,
        batch: false,
      );
      final pending = _register(command, encoded, acceptedAt, timeout, remaining);
      pending.detachCancellation = operation?.onCancel(() => _cancel(pending));
      _scheduleFlush();
      return pending.completer.future;
    } on RunnelException catch (error, stackTrace) {
      return Future.error(error, stackTrace);
    }
  }

  /// Atomically reserves capacity for [commands] and queues them in order.
  List<Future<Object?>> executeBatch(
    List<RedisCommand<Object?>> commands, {
    required Duration timeout,
    RunnelOperation? operation,
  }) {
    final acceptedAt = Stopwatch()..start();
    if (_closed) {
      throw const RedisClosedException(message: 'The Redis connection is closed.');
    }
    final encoded = commands.map(encodeCommand).toList(growable: false);
    final encodedBytes = encoded.fold<int>(0, (total, bytes) => total + bytes.length);
    final remaining = _admit(
      count: commands.length,
      bytes: encodedBytes,
      acceptedAt: acceptedAt,
      timeout: timeout,
      enforceLimits: true,
      batch: true,
    );
    final accepted = <_Pending<Object?>>[
      for (var index = 0; index < commands.length; index++)
        _register(commands[index], encoded[index], acceptedAt, timeout, remaining),
    ];
    for (final pending in accepted) {
      pending.detachCancellation = operation?.onCancel(() => _cancel(pending));
    }
    _scheduleFlush();
    return List.unmodifiable(accepted.map((pending) => pending.completer.future));
  }

  Duration _admit({
    required int count,
    required int bytes,
    required Stopwatch acceptedAt,
    required Duration timeout,
    required bool enforceLimits,
    required bool batch,
  }) {
    if (enforceLimits &&
        (batch
            ? _pending.length + count > _limits.maxPendingCommands
            : _pending.length == _limits.maxPendingCommands)) {
      throw RedisLimitException(
        message: batch
            ? 'The batch would exceed ${_limits.maxPendingCommands} pending commands.'
            : 'The connection already has ${_limits.maxPendingCommands} pending commands.',
        deliveryStatus: RedisDeliveryStatus.notSent,
        limit: _limits.maxPendingCommands,
      );
    }
    if (enforceLimits && _pendingBytes + bytes > _limits.maxPendingBytes) {
      throw RedisLimitException(
        message:
            'The ${batch ? 'batch' : 'command'} would exceed ${_limits.maxPendingBytes} pending encoded bytes.',
        deliveryStatus: RedisDeliveryStatus.notSent,
        limit: _limits.maxPendingBytes,
      );
    }
    final remaining = timeout - acceptedAt.elapsed;
    if (remaining <= Duration.zero) {
      throw RedisTimeoutException(
        message: 'The Redis ${batch ? 'batch' : 'command'} deadline expired during local encoding.',
        deliveryStatus: RedisDeliveryStatus.notSent,
      );
    }
    return remaining;
  }

  _Pending<T> _register<T>(
    RedisCommand<T> command,
    Uint8List encoded,
    Stopwatch acceptedAt,
    Duration timeout,
    Duration remaining,
  ) {
    final pending = _Pending<T>(command, encoded, acceptedAt, timeout);
    _pending.add(pending as _Pending<Object?>);
    _pendingBytes += encoded.length;
    pending.timer = Timer(remaining, () => _timeout(pending as _Pending<Object?>));
    return pending;
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    if (_closed) return;
    final queued = _pending.where((pending) => !pending.submitted).toList(growable: false);
    if (queued.isEmpty) return;
    final bytes = BytesBuilder(copy: false);
    for (final pending in queued) {
      bytes.add(pending.encoded);
    }
    try {
      _socket.add(bytes.takeBytes());
      for (final pending in queued) {
        pending.submitted = true;
      }
    } on Object catch (error, stackTrace) {
      _terminate(
        RedisTransportException(
          message: 'Could not submit Redis command bytes.',
          deliveryStatus: RedisDeliveryStatus.notSent,
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  void _cancel(_Pending<Object?> pending) {
    if (!_pending.contains(pending)) return;
    if (!pending.submitted) {
      _remove(pending);
      pending.completer.completeError(
        const RedisClosedException(message: 'Command cancelled before submission.'),
      );
      return;
    }
    _terminate(
      const RedisTransportException(
        message: 'A submitted command was cancelled.',
        deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
      ),
      StackTrace.current,
    );
  }

  void _timeout(_Pending<Object?> pending) {
    if (pending.completer.isCompleted || !_pending.contains(pending)) return;
    if (!pending.submitted) {
      _remove(pending);
      pending.completer.completeError(
        const RedisTimeoutException(
          message: 'The Redis command deadline expired before submission.',
          deliveryStatus: RedisDeliveryStatus.notSent,
        ),
      );
      return;
    }
    _terminate(
      const RedisTimeoutException(
        message: 'The Redis command deadline expired after submission.',
        deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
      ),
      StackTrace.current,
    );
  }

  void _onBytes(Uint8List bytes) {
    try {
      for (final received in _parser.add(bytes)) {
        final actual = switch (received) {
          RespAttributed(:final value) => value,
          _ => received,
        };
        if (actual is RespPush) continue;
        if (_pending.isEmpty || !_pending.first.submitted) {
          _terminate(
            const RedisProtocolException(message: 'Received a reply without a submitted command.'),
            StackTrace.current,
          );
          return;
        }
        final pending = _pending.first;
        if (actual case RespError(:final code, :final message)) {
          if (pending.deadlineExpired) {
            _terminate(
              const RedisTimeoutException(
                message: 'The Redis command deadline expired during reply decoding.',
                deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
              ),
              StackTrace.current,
            );
            return;
          }
          _remove(pending);
          pending.completer.completeError(RedisServerException(code: code, message: message));
          continue;
        }
        try {
          pending.complete(actual);
          _remove(pending);
        } on _DecodeDeadlineExpired catch (error, stackTrace) {
          _terminate(
            RedisTimeoutException(
              message: 'The Redis command deadline expired during reply decoding.',
              deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
              cause: error.cause,
            ),
            stackTrace,
          );
          return;
        } on Object catch (error, stackTrace) {
          _remove(pending);
          pending.completer.completeError(error, stackTrace);
        }
      }
    } on Object catch (error, stackTrace) {
      _terminate(error, stackTrace);
    }
  }

  void _remove(_Pending<Object?> pending) {
    if (!_pending.remove(pending)) return;
    pending.timer?.cancel();
    pending.detachCancellation?.call();
    _pendingBytes -= pending.encoded.length;
    if (_pending.isEmpty) _notifyIdle();
  }

  void _onError(Object error, StackTrace stackTrace) => _terminate(
    RedisTransportException(
      message: 'The Redis connection failed.',
      deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
      cause: error,
    ),
    stackTrace,
  );

  void _onDone() {
    if (_closed) return;
    _terminate(
      const RedisTransportException(
        message: 'The Redis connection closed before all replies arrived.',
        deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
      ),
      StackTrace.current,
    );
  }

  void _terminate(Object cause, StackTrace stackTrace) {
    if (_closed) return;
    _closed = true;
    _notifyIdle();
    unawaited(_subscription.cancel());
    _socket.destroy();
    _failPending(cause, stackTrace);
    _onTerminated(this, cause);
  }

  void _failPending(Object cause, [StackTrace? stackTrace]) {
    for (final operation in List<_Pending<Object?>>.of(_pending)) {
      _remove(operation);
      operation.completer.completeError(
        _failureFor(cause, submitted: operation.submitted),
        stackTrace,
      );
    }
  }

  void _notifyIdle() {
    _idle?.complete();
    _idle = null;
  }

  Object _failureFor(Object cause, {required bool submitted}) {
    final deliveryStatus = submitted
        ? RedisDeliveryStatus.outcomeUnknown
        : RedisDeliveryStatus.notSent;
    return switch (cause) {
      RedisTimeoutException() => RedisTimeoutException(
        message: cause.message,
        deliveryStatus: deliveryStatus,
        cause: cause.cause,
      ),
      RedisProtocolException() => RedisProtocolException(
        message: cause.message,
        cause: cause.cause,
        deliveryStatus: deliveryStatus,
      ),
      RedisClosedException() => RedisClosedException(
        message: cause.message,
        deliveryStatus: deliveryStatus,
      ),
      RedisLimitException() => RedisLimitException(
        message: cause.message,
        deliveryStatus: deliveryStatus,
        limit: cause.limit,
      ),
      _ => RedisTransportException(
        message: cause is RunnelException ? cause.message : 'The Redis connection failed.',
        deliveryStatus: deliveryStatus,
        cause: cause is RunnelException ? cause.cause : cause,
      ),
    };
  }

  /// Completes when every accepted command settles or the connection closes.
  Future<void> waitUntilIdle() {
    if (_closed || _pending.isEmpty) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  /// Releases this socket and fails any remaining commands.
  ///
  /// When [commandsAreUncertain] is true, the socket is destroyed because submitted work may have
  /// reached the server.
  Future<void> close({bool commandsAreUncertain = false}) async {
    if (_closed) return;
    _closed = true;
    _notifyIdle();
    await _subscription.cancel();
    if (commandsAreUncertain) {
      _socket.destroy();
    } else {
      await _socket.close();
    }
    _failPending(
      const RedisClosedException(message: 'The Redis connection closed before replying.'),
    );
  }
}

final class _Pending<T> {
  _Pending(this.command, this.encoded, this.stopwatch, this.deadline);

  final RedisCommand<T> command;
  final Uint8List encoded;
  final Stopwatch stopwatch;
  final Duration deadline;
  final Completer<T> completer = Completer<T>();
  Timer? timer;
  void Function()? detachCancellation;
  bool submitted = false;

  bool get deadlineExpired => stopwatch.elapsed >= deadline;

  void complete(RespValue reply) {
    try {
      final value = command.decode(reply).getOrThrowWith((error) => error);
      if (deadlineExpired) throw const _DecodeDeadlineExpired();
      completer.complete(value);
    } on Object catch (error, stackTrace) {
      if (error is _DecodeDeadlineExpired || error is CommandDecoderDefect) rethrow;
      if (deadlineExpired) {
        Error.throwWithStackTrace(_DecodeDeadlineExpired(error), stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final class _DecodeDeadlineExpired implements Exception {
  const _DecodeDeadlineExpired([this.cause]);

  final Object? cause;
}

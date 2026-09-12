// This class is package-internal; callers use the documented Runnel API.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/src/command.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/resp/resp_parser.dart';
import 'package:runnel/src/resp/resp_value.dart';

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

  final Socket _socket;
  final RunnelLimits _limits;
  final ConnectionTerminated _onTerminated;
  final RespParser _parser;
  late final StreamSubscription<Uint8List> _subscription;
  final List<_Pending<Object?>> _pending = [];
  var _pendingBytes = 0;
  var _flushScheduled = false;
  var _closed = false;

  bool get isClosed => _closed;
  bool get isIdle => _pending.isEmpty;
  int get pendingCount => _pending.length;
  int get pendingBytes => _pendingBytes;

  static Future<RedisConnection> open({
    required String host,
    required int port,
    required bool tls,
    required SecurityContext? securityContext,
    required RunnelLimits limits,
    required Duration timeout,
    required ConnectionTerminated onTerminated,
  }) async {
    final socket = tls
        ? await SecureSocket.connect(host, port, context: securityContext, timeout: timeout)
        : await Socket.connect(host, port, timeout: timeout);
    return RedisConnection._(socket, limits, onTerminated);
  }

  Future<T> execute<T>(
    RedisCommand<T> command, {
    required Duration timeout,
    bool enforceLimits = true,
  }) {
    final acceptedAt = Stopwatch()..start();
    if (_closed) {
      return Future.error(const RedisClosedException(message: 'The Redis connection is closed.'));
    }
    final encoded = encodeCommand(command as RedisCommand<Object?>);
    if (enforceLimits && _pending.length == _limits.maxPendingCommands) {
      return Future.error(
        RedisLimitException(
          message: 'The connection already has ${_limits.maxPendingCommands} pending commands.',
          deliveryStatus: RedisDeliveryStatus.notSent,
          limit: _limits.maxPendingCommands,
        ),
      );
    }
    if (enforceLimits && _pendingBytes + encoded.length > _limits.maxPendingBytes) {
      return Future.error(
        RedisLimitException(
          message: 'The command would exceed ${_limits.maxPendingBytes} pending encoded bytes.',
          deliveryStatus: RedisDeliveryStatus.notSent,
          limit: _limits.maxPendingBytes,
        ),
      );
    }
    final remaining = timeout - acceptedAt.elapsed;
    if (remaining <= Duration.zero) {
      return Future.error(
        const RedisTimeoutException(
          message: 'The Redis command deadline expired during local encoding.',
          deliveryStatus: RedisDeliveryStatus.notSent,
        ),
      );
    }

    final pending = _Pending<T>(command, encoded);
    _pending.add(pending as _Pending<Object?>);
    _pendingBytes += encoded.length;
    pending.timer = Timer(remaining, () => _timeout(pending as _Pending<Object?>));
    _scheduleFlush();
    return pending.completer.future;
  }

  List<Future<Object?>> executeBatch(
    List<RedisCommand<Object?>> commands, {
    required Duration timeout,
  }) {
    final acceptedAt = Stopwatch()..start();
    if (_closed) {
      throw const RedisClosedException(message: 'The Redis connection is closed.');
    }
    final encoded = commands.map(encodeCommand).toList(growable: false);
    final encodedBytes = encoded.fold<int>(0, (total, bytes) => total + bytes.length);
    if (_pending.length + commands.length > _limits.maxPendingCommands) {
      throw RedisLimitException(
        message: 'The batch would exceed ${_limits.maxPendingCommands} pending commands.',
        deliveryStatus: RedisDeliveryStatus.notSent,
        limit: _limits.maxPendingCommands,
      );
    }
    if (_pendingBytes + encodedBytes > _limits.maxPendingBytes) {
      throw RedisLimitException(
        message: 'The batch would exceed ${_limits.maxPendingBytes} pending encoded bytes.',
        deliveryStatus: RedisDeliveryStatus.notSent,
        limit: _limits.maxPendingBytes,
      );
    }
    final remaining = timeout - acceptedAt.elapsed;
    if (remaining <= Duration.zero) {
      throw const RedisTimeoutException(
        message: 'The Redis batch deadline expired during local encoding.',
        deliveryStatus: RedisDeliveryStatus.notSent,
      );
    }

    final accepted = <_Pending<Object?>>[];
    for (var index = 0; index < commands.length; index++) {
      final pending = _Pending<Object?>(commands[index], encoded[index]);
      _pending.add(pending);
      accepted.add(pending);
      _pendingBytes += encoded[index].length;
      pending.timer = Timer(remaining, () => _timeout(pending));
    }
    _scheduleFlush();
    return List.unmodifiable(accepted.map((pending) => pending.completer.future));
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
        _remove(pending);
        if (actual case RespError(:final code, :final message)) {
          pending.completer.completeError(RedisServerException(code: code, message: message));
          continue;
        }
        try {
          pending.complete(actual);
        } on Object catch (error, stackTrace) {
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
    _pendingBytes -= pending.encoded.length;
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
    unawaited(_subscription.cancel());
    _socket.destroy();
    final pending = List<_Pending<Object?>>.of(_pending);
    for (final operation in pending) {
      final submitted = operation.submitted;
      _remove(operation);
      operation.completer.completeError(_failureFor(cause, submitted: submitted), stackTrace);
    }
    _onTerminated(this, cause);
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

  Future<void> waitUntilIdle() async {
    while (!_closed && _pending.isNotEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> close({bool commandsAreUncertain = false}) async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    if (commandsAreUncertain) {
      _socket.destroy();
    } else {
      await _socket.close();
    }
    final pending = List<_Pending<Object?>>.of(_pending);
    for (final operation in pending) {
      final submitted = operation.submitted;
      _remove(operation);
      operation.completer.completeError(
        RedisClosedException(
          message: 'The Redis connection closed before replying.',
          deliveryStatus: submitted
              ? RedisDeliveryStatus.outcomeUnknown
              : RedisDeliveryStatus.notSent,
        ),
      );
    }
  }
}

final class _Pending<T> {
  _Pending(this.command, this.encoded);

  final RedisCommand<T> command;
  final Uint8List encoded;
  final Completer<T> completer = Completer<T>();
  Timer? timer;
  bool submitted = false;

  void complete(RespValue reply) => completer.complete(command.decode(reply));
}

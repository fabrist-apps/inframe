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

final class RedisConnection {
  RedisConnection._(this._socket, RunnelLimits limits)
    : _parser = RespParser(
        maxFrameBytes: limits.maxFrameBytes,
        maxNestingDepth: limits.maxNestingDepth,
      ) {
    _subscription = _socket.listen(
      _onBytes,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final RespParser _parser;
  late final StreamSubscription<Uint8List> _subscription;
  final List<_Pending<Object?>> _pending = [];
  bool _closed = false;

  static Future<RedisConnection> openWithLimits({
    required String host,
    required int port,
    required bool tls,
    required SecurityContext? securityContext,
    required RunnelLimits limits,
    required Duration timeout,
  }) async {
    final socket = tls
        ? await SecureSocket.connect(host, port, context: securityContext, timeout: timeout)
        : await Socket.connect(host, port, timeout: timeout);
    return RedisConnection._(socket, limits);
  }

  Future<T> execute<T>(RedisCommand<T> command) {
    if (_closed) {
      return Future.error(const RedisClosedException(message: 'The Redis connection is closed.'));
    }
    final encoded = encodeCommand(command as RedisCommand<Object?>);
    final pending = _Pending<T>(command);
    _pending.add(pending as _Pending<Object?>);
    try {
      _socket.add(encoded);
    } on Object catch (error, stackTrace) {
      _pending.remove(pending);
      pending.completer.completeError(
        RedisTransportException(
          message: 'Could not submit the Redis command.',
          deliveryStatus: RedisDeliveryStatus.notSent,
          cause: error,
        ),
        stackTrace,
      );
    }
    return pending.completer.future;
  }

  void _onBytes(Uint8List bytes) {
    try {
      for (final received in _parser.add(bytes)) {
        final actual = switch (received) {
          RespAttributed(:final value) => value,
          _ => received,
        };
        if (actual is RespPush) continue;
        if (_pending.isEmpty) {
          _failProtocol('Received a reply without a pending command.');
          return;
        }
        final pending = _pending.removeAt(0);
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

  void _failProtocol(String message) {
    _terminate(RedisProtocolException(message: message), StackTrace.current);
  }

  void _terminate(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription.cancel());
    unawaited(_socket.close());
    for (final pending in _pending) {
      pending.completer.completeError(error, stackTrace);
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _socket.close();
    const error = RedisClosedException(message: 'The Redis connection closed before replying.');
    for (final pending in _pending) {
      pending.completer.completeError(error);
    }
    _pending.clear();
  }
}

final class _Pending<T> {
  _Pending(this.command);
  final RedisCommand<T> command;
  final Completer<T> completer = Completer<T>();

  void complete(RespValue reply) => completer.complete(command.decode(reply));
}

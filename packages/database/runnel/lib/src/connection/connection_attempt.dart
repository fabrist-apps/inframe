// Package-internal connection ownership shared by physical transports.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';

import 'package:runnel/src/errors.dart';

final class ConnectionAttempt {
  void Function()? _cancelConnect;
  Future<void> Function()? _closeResource;
  bool _cancelled = false;

  bool attachConnect(void Function() cancel) {
    if (_cancelled) {
      cancel();
      return false;
    }
    _cancelConnect = cancel;
    return true;
  }

  void detachConnect(void Function() cancel) {
    if (identical(_cancelConnect, cancel)) _cancelConnect = null;
  }

  bool attachResource(Future<void> Function() close) {
    if (_cancelled) return false;
    _closeResource = close;
    return true;
  }

  void finish() {
    _cancelConnect = null;
    _closeResource = null;
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _cancelConnect?.call();
    _cancelConnect = null;
    final close = _closeResource;
    _closeResource = null;
    await close?.call();
  }
}

Future<Socket> openSocket({
  required String host,
  required int port,
  required bool tls,
  required SecurityContext? securityContext,
  required Duration timeout,
  ConnectionAttempt? attempt,
}) async {
  final elapsed = Stopwatch()..start();
  final pending = tls
      ? await _startSecureConnect(host, port, securityContext)
      : await _startPlainConnect(host, port);
  if (!(attempt?.attachConnect(pending.cancel) ?? true)) {
    try {
      await pending.socket;
    } on Object {
      // Cancellation is represented to the caller by RedisClosedException below.
    }
    throw const RedisClosedException(message: 'The connection attempt was cancelled.');
  }
  try {
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      pending.cancel();
      throw TimeoutException('The socket connection deadline expired.');
    }
    final socket = await pending.socket.timeout(
      remaining,
      onTimeout: () {
        pending.cancel();
        throw TimeoutException('The socket connection deadline expired.');
      },
    );
    if (!(attempt?.attachResource(() async => socket.destroy()) ?? true)) {
      socket.destroy();
      throw const RedisClosedException(message: 'The connection attempt was cancelled.');
    }
    return socket;
  } finally {
    attempt?.detachConnect(pending.cancel);
  }
}

Future<({Future<Socket> socket, void Function() cancel})> _startPlainConnect(
  String host,
  int port,
) async {
  final task = await Socket.startConnect(host, port);
  return (socket: task.socket, cancel: task.cancel);
}

Future<({Future<Socket> socket, void Function() cancel})> _startSecureConnect(
  String host,
  int port,
  SecurityContext? securityContext,
) async {
  final task = await SecureSocket.startConnect(host, port, context: securityContext);
  return (socket: task.socket, cancel: task.cancel);
}

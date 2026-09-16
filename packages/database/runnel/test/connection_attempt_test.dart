import 'dart:async';
import 'dart:io';

import 'package:runnel/src/connection/connection_attempt.dart';
import 'package:runnel/src/deadline.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionAttempt', () {
    test('should release a plain socket when the TLS handshake times out', () async {
      final peer = await _StalledTlsPeer.start();
      addTearDown(peer.close);
      final attempt = ConnectionAttempt();

      final opening = openSocket(
        host: InternetAddress.loopbackIPv4.address,
        port: peer.port,
        tls: true,
        securityContext: SecurityContext(),
        deadline: Deadline(const Duration(milliseconds: 50)),
        attempt: attempt,
      );
      await peer.connected;

      await expectLater(opening, throwsA(isA<TimeoutException>()));
      attempt.finish();
      await peer.disconnected.timeout(const Duration(seconds: 1));
      await attempt.settled;
    });

    test('should release a plain socket when a TLS handshake is cancelled', () async {
      final peer = await _StalledTlsPeer.start();
      addTearDown(peer.close);
      final attempt = ConnectionAttempt();

      final opening = openSocket(
        host: InternetAddress.loopbackIPv4.address,
        port: peer.port,
        tls: true,
        securityContext: SecurityContext(),
        deadline: Deadline(const Duration(seconds: 5)),
        attempt: attempt,
      );
      final openingFailure = expectLater(
        opening.timeout(const Duration(seconds: 1)),
        throwsA(anything),
      );
      await peer.connected;
      await attempt.cancel();

      await openingFailure;
      attempt.finish();
      await peer.disconnected.timeout(const Duration(seconds: 1));
      await attempt.settled;
    });
  });
}

final class _StalledTlsPeer {
  _StalledTlsPeer._(this._server);

  final ServerSocket _server;
  final Completer<void> _connected = Completer<void>();
  final Completer<void> _disconnected = Completer<void>();
  Socket? _socket;

  int get port => _server.port;
  Future<void> get connected => _connected.future;
  Future<void> get disconnected => _disconnected.future;

  static Future<_StalledTlsPeer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = _StalledTlsPeer._(server);
    server.listen(peer._accept);
    return peer;
  }

  void _accept(Socket socket) {
    _socket = socket;
    socket.listen(
      (_) {},
      onError: (_, _) => _completeDisconnected(),
      onDone: _completeDisconnected,
      cancelOnError: true,
    );
    _connected.complete();
  }

  void _completeDisconnected() {
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  Future<void> close() async {
    _socket?.destroy();
    await _server.close();
  }
}

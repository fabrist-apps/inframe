import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:inlet/inlet.dart';
import 'package:test/test.dart';

final class WireClient {
  WireClient._(this._socket) {
    _socket.listen(
      (chunk) {
        _bytes.addAll(chunk);
        if (!_changed.isCompleted) {
          _changed.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_changed.isCompleted) {
          _changed.completeError(error, stackTrace);
        }
      },
      onDone: () {
        _done = true;
        if (!_changed.isCompleted) {
          _changed.complete();
        }
      },
    );
  }

  static Future<WireClient> connect(InletServer server) async =>
      WireClient._(await Socket.connect(server.address, server.port));

  final Socket _socket;
  final List<int> _bytes = [];
  Completer<void> _changed = Completer<void>();
  bool _done = false;

  String get text => latin1.decode(_bytes);

  void send(String value) {
    _socket.add(latin1.encode(value));
    unawaited(_socket.flush());
  }

  Future<void> waitFor(bool Function(String value) predicate) async {
    while (!predicate(text)) {
      if (_done) {
        fail('Connection closed before the expected response arrived:\n$text');
      }
      final changed = _changed;
      await changed.future.timeout(const Duration(seconds: 2));
      if (identical(changed, _changed)) {
        _changed = Completer<void>();
      }
    }
  }

  Future<void> waitUntilDone() async {
    while (!_done) {
      final changed = _changed;
      await changed.future.timeout(const Duration(seconds: 2));
      if (identical(changed, _changed)) {
        _changed = Completer<void>();
      }
    }
  }

  Future<void> close() => _socket.close();
}

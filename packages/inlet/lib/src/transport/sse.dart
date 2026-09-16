import 'dart:async';
import 'dart:io';

/// Tracks only SSE sockets detached from this listener.
final class SseConnections {
  final Set<_DetachedSseResponse> _active = {};
  bool _closed = false;

  /// Aborts active and subsequently arriving detached sockets.
  void abort() {
    if (_closed) return;
    _closed = true;
    final responses = _active.toList();
    _active.clear();
    for (final response in responses) {
      response.abort().ignore();
    }
  }

  /// Owns the socket until delivery finishes, fails, or is forcibly stopped.
  Future<void> deliver(Socket socket, Stream<List<int>> body) async {
    final response = _DetachedSseResponse(socket, body);
    if (_closed) {
      response.abort().ignore();
      return;
    }
    _active.add(response);
    try {
      await response.deliver();
    } finally {
      _active.remove(response);
    }
  }
}

final class _DetachedSseResponse {
  _DetachedSseResponse(this._socket, Stream<List<int>> body) : _events = StreamIterator(body);

  final Socket _socket;
  final StreamIterator<List<int>> _events;
  Future<void>? _abortFuture;

  Future<void> deliver() async {
    try {
      // StreamIterator stays unsubscribed until moveNext, after headers flush.
      await _socket.flush();
      while (await _events.moveNext()) {
        _socket.add(_events.current);
        await _socket.flush();
      }

      await _socket.close();
    } on Object {
      abort().ignore();
      rethrow;
    }
  }

  Future<void> abort() => _abortFuture ??= _abort();

  Future<void> _abort() async {
    _socket.destroy();
    await _events.cancel();
  }
}

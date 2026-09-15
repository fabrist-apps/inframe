import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A disposable TCP peer. Tests supply command behavior; this owns wire I/O.
final class RespPeer {
  RespPeer._(this._server, this._onCommand, this._onConnect, this._onDisconnect) {
    _server.listen(_accept);
  }

  final ServerSocket _server;
  final void Function(RespPeerCommand command) _onCommand;
  final void Function(Socket socket)? _onConnect;
  final void Function(Socket socket)? _onDisconnect;
  final List<Socket> sockets = [];
  final List<RespPeerCommand> commands = [];

  int get port => _server.port;
  String get endpoint => 'redis://127.0.0.1:$port';

  static Future<RespPeer> start({
    required void Function(RespPeerCommand command) onCommand,
    void Function(Socket socket)? onConnect,
    void Function(Socket socket)? onDisconnect,
  }) async => RespPeer._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    onCommand,
    onConnect,
    onDisconnect,
  );

  void _accept(Socket socket) {
    sockets.add(socket);
    _onConnect?.call(socket);
    unawaited(socket.done.then<void>((_) {}, onError: (_, _) {}));
    var disconnected = false;
    void notifyDisconnected() {
      if (disconnected) return;
      disconnected = true;
      _onDisconnect?.call(socket);
    }

    var buffer = <int>[];
    socket.listen(
      (bytes) {
        buffer.addAll(bytes);
        while (true) {
          final parsed = parseCommand(buffer);
          if (parsed == null) return;
          buffer = buffer.sublist(parsed.consumed);
          final command = RespPeerCommand(socket, parsed.arguments);
          commands.add(command);
          _onCommand(command);
        }
      },
      // Tests deliberately destroy either endpoint to exercise disconnects.
      onError: (Object error, StackTrace stackTrace) => notifyDisconnected(),
      onDone: notifyDisconnected,
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

final class RespPeerCommand {
  const RespPeerCommand(this.socket, this.arguments);

  final Socket socket;
  final List<Uint8List> arguments;

  String get name => ascii.decode(arguments.first).toUpperCase();
  List<String> get textArguments => arguments.map(utf8.decode).toList(growable: false);

  void reply(String frame) => socket.add(utf8.encode(frame));

  /// Handles the standard handshake unless a test needs to delay or reject it.
  bool replyToHandshake() {
    switch (name) {
      case 'HELLO':
        reply('%1\r\n+proto\r\n:3\r\n');
        return true;
      case 'SELECT':
        reply('+OK\r\n');
        return true;
      default:
        return false;
    }
  }
}

/// Parses client command arrays independently of Runnel's production RESP parser.
({List<Uint8List> arguments, int consumed})? parseCommand(List<int> bytes) {
  if (bytes.isEmpty) return null;
  if (bytes.first != 42) throw const FormatException('Expected a command array.');
  final headerEnd = _findCrlf(bytes, 0);
  if (headerEnd < 0) return null;
  final count = int.parse(ascii.decode(bytes.sublist(1, headerEnd)));
  var offset = headerEnd + 2;
  final arguments = <Uint8List>[];
  for (var index = 0; index < count; index++) {
    if (offset >= bytes.length) return null;
    if (bytes[offset] != 36) throw const FormatException('Expected a bulk command argument.');
    final lengthEnd = _findCrlf(bytes, offset);
    if (lengthEnd < 0) return null;
    final length = int.parse(ascii.decode(bytes.sublist(offset + 1, lengthEnd)));
    final start = lengthEnd + 2;
    final end = start + length;
    if (length < 0) throw const FormatException('Expected a nonnegative argument length.');
    if (end + 2 > bytes.length) return null;
    if (bytes[end] != 13 || bytes[end + 1] != 10) {
      throw const FormatException('Expected an argument terminator.');
    }
    arguments.add(Uint8List.fromList(bytes.sublist(start, end)));
    offset = end + 2;
  }
  return (arguments: arguments, consumed: offset);
}

int _findCrlf(List<int> bytes, int start) {
  for (var index = start; index + 1 < bytes.length; index++) {
    if (bytes[index] == 13 && bytes[index + 1] == 10) return index;
  }
  return -1;
}

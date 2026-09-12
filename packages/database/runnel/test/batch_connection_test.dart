import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  test('an execution-capacity failure transmits no batch prefix', () async {
    final peer = await _BatchPeer.start()
      ..holdPings = true;
    addTearDown(peer.close);
    final client = await Runnel.connect(
      peer.endpoint,
      limits: const RunnelLimits(maxPendingCommands: 2),
    );
    addTearDown(client.close);

    final pending = client.ping();
    await peer.waitFor('PING', 1);
    final pipeline = client.pipeline()
      ..add(_pingCommand())
      ..add(_pingCommand());

    await expectLater(pipeline.exec(), throwsA(isA<RedisLimitException>()));
    await Future<void>.delayed(Duration.zero);
    expect(peer.count('PING'), 1);

    peer.replyHeldPing();
    expect(await pending, isTrue);
  });

  test('losing EXEC reports uncertainty and does not replay the transaction', () async {
    final peer = await _BatchPeer.start()
      ..dropExec = true;
    addTearDown(peer.close);
    final client = await Runnel.connect(peer.endpoint);
    addTearDown(client.close);
    final transaction = client.transaction()..add(incrCommand('counter'));

    await expectLater(
      transaction.exec(),
      throwsA(
        isA<RunnelException>().having(
          (error) => error.deliveryStatus,
          'delivery status',
          RedisDeliveryStatus.outcomeUnknown,
        ),
      ),
    );

    expect(peer.count('EXEC'), 1);
    expect(peer.count('INCR'), 1);
    expect(await client.ping(), isTrue);
  });
}

RedisCommand<bool> _pingCommand() => RedisCommand<bool>(
  [RedisArgument.text('PING')],
  (reply) => respText(reply) == 'PONG',
);

final class _BatchPeer {
  _BatchPeer._(this._server);

  final ServerSocket _server;
  final List<Socket> _sockets = [];
  final List<String> _commands = [];
  final List<Socket> _heldPings = [];
  bool holdPings = false;
  bool dropExec = false;

  String get endpoint => 'redis://127.0.0.1:${_server.port}';

  static Future<_BatchPeer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = _BatchPeer._(server);
    server.listen(peer._accept);
    return peer;
  }

  int count(String command) => _commands.where((value) => value == command).length;

  void _accept(Socket socket) {
    _sockets.add(socket);
    var buffer = <int>[];
    var transaction = false;
    socket.listen((bytes) {
      buffer.addAll(bytes);
      while (true) {
        final parsed = _parseCommand(buffer);
        if (parsed == null) return;
        buffer = buffer.sublist(parsed.consumed);
        final command = ascii.decode(parsed.arguments.first).toUpperCase();
        _commands.add(command);
        switch (command) {
          case 'HELLO':
            socket.add(ascii.encode('%1\r\n+proto\r\n:3\r\n'));
          case 'MULTI':
            transaction = true;
            socket.add(ascii.encode('+OK\r\n'));
          case 'EXEC' when dropExec:
            socket.destroy();
          case 'EXEC':
            socket.add(ascii.encode('*0\r\n'));
          case 'PING' when transaction:
          case 'INCR' when transaction:
            socket.add(ascii.encode('+QUEUED\r\n'));
          case 'PING' when holdPings:
            _heldPings.add(socket);
          case 'PING':
            socket.add(ascii.encode('+PONG\r\n'));
          default:
            socket.add(ascii.encode('-ERR unsupported\r\n'));
        }
      }
    });
  }

  void replyHeldPing() => _heldPings.removeAt(0).add(ascii.encode('+PONG\r\n'));

  Future<void> waitFor(String command, int expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (count(command) < expected) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Did not receive $expected $command commands.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

({List<List<int>> arguments, int consumed})? _parseCommand(List<int> bytes) {
  if (bytes.isEmpty || bytes.first != 42) return null;
  final countLine = _line(bytes, 1);
  if (countLine == null) return null;
  final count = int.parse(ascii.decode(bytes.sublist(1, countLine.index)));
  var offset = countLine.after;
  final arguments = <List<int>>[];
  for (var index = 0; index < count; index++) {
    if (offset >= bytes.length || bytes[offset] != 36) return null;
    final lengthLine = _line(bytes, offset + 1);
    if (lengthLine == null) return null;
    final length = int.parse(ascii.decode(bytes.sublist(offset + 1, lengthLine.index)));
    final end = lengthLine.after + length;
    if (end + 2 > bytes.length) return null;
    arguments.add(bytes.sublist(lengthLine.after, end));
    offset = end + 2;
  }
  return (arguments: arguments, consumed: offset);
}

({int index, int after})? _line(List<int> bytes, int start) {
  for (var index = start; index + 1 < bytes.length; index++) {
    if (bytes[index] == 13 && bytes[index + 1] == 10) {
      return (index: index, after: index + 2);
    }
  }
  return null;
}

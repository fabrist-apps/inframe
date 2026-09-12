import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  group('Runnel', () {
    test('should complete the RESP3 handshake and round-trip text and bytes', () async {
      final peer = await _RespPeer.start();
      addTearDown(peer.close);

      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}');
      addTearDown(client.close);

      expect(await client.ping(), isTrue);
      expect(await client.set('name', 'Bhaswanth'), isTrue);
      expect(await client.get('name'), 'Bhaswanth');

      final source = Uint8List.fromList([0, 255, 1]);
      final write = client.setBytes('blob', source);
      source[1] = 7;
      expect(await write, isTrue);
      expect(await client.getBytes('blob'), [0, 255, 1]);
      expect(await client.get('missing'), isNull);

      expect(peer.commands, [
        ['HELLO', '3'],
        ['PING'],
        ['SET', 'name', 'Bhaswanth'],
        ['GET', 'name'],
        ['SET', 'blob', '\u0000\ufffd\u0001'],
        ['GET', 'blob'],
        ['GET', 'missing'],
      ]);
    });

    test('should reject invalid endpoint shapes asynchronously', () async {
      for (final endpoint in [
        'http://localhost:6379',
        'redis:///0',
        'redis://localhost/path',
        'redis://localhost/1/2',
        'redis://localhost?query=yes',
        'redis://localhost#fragment',
      ]) {
        await expectLater(Runnel.connect(endpoint), throwsArgumentError);
      }

      await expectLater(
        Runnel.connect(
          'redis://localhost:6379',
          securityContext: SecurityContext(),
        ),
        throwsArgumentError,
      );
      await expectLater(
        Runnel.connect('redis://localhost:6379', limits: const RunnelLimits(maxFrameBytes: 0)),
        throwsArgumentError,
      );
    });

    test('should keep credentials out of connection diagnostics', () async {
      final unavailable = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = unavailable.port;
      await unavailable.close();

      Object? failure;
      try {
        await Runnel.connect('redis://secret-user:secret-password@127.0.0.1:$port');
      } on Object catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect('$failure', isNot(contains('secret-user')));
      expect('$failure', isNot(contains('secret-password')));
    });

    test('should finish authentication and database selection before connecting', () async {
      final peer = await _RespPeer.start();
      addTearDown(peer.close);

      final connecting = Runnel.connect(
        'redis://user:p%40ss@127.0.0.1:${peer.port}/2',
      );
      final client = await connecting;
      addTearDown(client.close);

      expect(peer.commands.take(2), [
        ['HELLO', '3', 'AUTH', 'user', 'p@ss'],
        ['SELECT', '2'],
      ]);
    });

    test('should release the socket when the handshake is rejected', () async {
      final peer = await _RespPeer.start()
        ..rejectHandshake = true;
      addTearDown(peer.close);

      await expectLater(
        Runnel.connect('redis://:wrong@127.0.0.1:${peer.port}'),
        throwsA(isA<RedisServerException>()),
      );
      await peer.socketClosed.future.timeout(const Duration(seconds: 1));
    });

    test('should keep reply alignment after a command decoder fails', () async {
      final peer = await _RespPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}');
      addTearDown(client.close);

      final invalid = client.execute(
        RedisCommand<int>([RedisArgument.text('PING')], (_) => throw const FormatException('bad')),
      );
      final valid = client.ping();

      await expectLater(invalid, throwsFormatException);
      expect(await valid, isTrue);
    });

    test('should not consume pending replies with attributed pushes', () async {
      final peer = await _RespPeer.start()
        ..pushBeforeNextReply = true;
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}');
      addTearDown(client.close);

      expect(await client.ping(), isTrue);
      expect(await client.ping(), isTrue);
    });

    test('should invalidate the connection when a reply is malformed', () async {
      final peer = await _RespPeer.start()
        ..malformNextReply = true;
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}');
      addTearDown(client.close);

      final first = client.ping();
      final second = client.ping();

      await expectLater(first, throwsA(isA<RedisProtocolException>()));
      await expectLater(second, throwsA(isA<RedisProtocolException>()));
      await expectLater(client.ping(), throwsA(isA<RedisClosedException>()));
    });

    test('should reject work after idempotent close', () async {
      final peer = await _RespPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}');

      await Future.wait([client.close(), client.close()]);

      await expectLater(client.ping(), throwsA(isA<RedisClosedException>()));
    });
  });
}

final class _RespPeer {
  _RespPeer._(this._server);

  final ServerSocket _server;
  final List<List<String>> commands = [];
  Socket? _socket;
  final Map<String, Uint8List> _values = {};
  bool pushBeforeNextReply = false;
  bool malformNextReply = false;
  bool rejectHandshake = false;
  final Completer<void> socketClosed = Completer<void>();

  int get port => _server.port;

  static Future<_RespPeer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = _RespPeer._(server);
    server.listen(peer._accept);
    return peer;
  }

  void _accept(Socket socket) {
    _socket = socket;
    unawaited(socket.done.then<void>((_) {}, onError: (_, _) {}));
    var buffer = <int>[];
    socket.listen(
      (bytes) {
        buffer.addAll(bytes);
        while (true) {
          final parsed = _parseCommand(buffer);
          if (parsed == null) return;
          buffer = buffer.sublist(parsed.consumed);
          final display = parsed.arguments
              .map((bytes) => utf8.decode(bytes, allowMalformed: true))
              .toList(growable: false);
          commands.add(display);
          _reply(socket, parsed.arguments);
        }
      },
      onDone: () {
        if (!socketClosed.isCompleted) socketClosed.complete();
      },
      onError: (_, _) {
        if (!socketClosed.isCompleted) socketClosed.complete();
      },
      cancelOnError: true,
    );
  }

  void _reply(Socket socket, List<Uint8List> arguments) {
    final command = ascii.decode(arguments.first).toUpperCase();
    if (rejectHandshake && command == 'HELLO') {
      socket.add(ascii.encode('-WRONGPASS invalid credentials\r\n'));
      return;
    }
    if (pushBeforeNextReply && command != 'HELLO') {
      pushBeforeNextReply = false;
      socket.add(ascii.encode('|1\r\n+source\r\n+peer\r\n>2\r\n+notice\r\n+value\r\n'));
    }
    if (malformNextReply && command != 'HELLO') {
      malformNextReply = false;
      socket.add(ascii.encode('?malformed\r\n'));
      return;
    }
    switch (command) {
      case 'HELLO':
        socket.add(ascii.encode('%1\r\n+proto\r\n:${displayProtocol(arguments)}\r\n'));
      case 'SELECT':
        socket.add(ascii.encode('+OK\r\n'));
      case 'PING':
        socket.add(ascii.encode('+PONG\r\n'));
      case 'SET':
        _values[utf8.decode(arguments[1])] = Uint8List.fromList(arguments[2]);
        socket.add(ascii.encode('+OK\r\n'));
      case 'GET':
        final value = _values[utf8.decode(arguments[1])];
        if (value == null) {
          socket.add(ascii.encode('_\r\n'));
        } else {
          socket
            ..add(
              ascii.encode(
                r'$'
                '${value.length}\r\n',
              ),
            )
            ..add([...value, 13, 10]);
        }
    }
  }

  Future<void> close() async {
    _socket?.destroy();
    await _server.close();
  }
}

String displayProtocol(List<Uint8List> arguments) => ascii.decode(arguments[1]);

({List<Uint8List> arguments, int consumed})? _parseCommand(List<int> bytes) {
  if (bytes.isEmpty || bytes.first != 42) return null;
  final headerEnd = _findCrlf(bytes, 0);
  if (headerEnd < 0) return null;
  final count = int.parse(ascii.decode(bytes.sublist(1, headerEnd)));
  var offset = headerEnd + 2;
  final arguments = <Uint8List>[];
  for (var index = 0; index < count; index++) {
    if (offset >= bytes.length || bytes[offset] != 36) return null;
    final lengthEnd = _findCrlf(bytes, offset);
    if (lengthEnd < 0) return null;
    final length = int.parse(ascii.decode(bytes.sublist(offset + 1, lengthEnd)));
    offset = lengthEnd + 2;
    if (bytes.length < offset + length + 2) return null;
    arguments.add(Uint8List.fromList(bytes.sublist(offset, offset + length)));
    offset += length + 2;
  }
  return (arguments: arguments, consumed: offset);
}

int _findCrlf(List<int> bytes, int start) {
  for (var index = start; index + 1 < bytes.length; index++) {
    if (bytes[index] == 13 && bytes[index + 1] == 10) return index;
  }
  return -1;
}

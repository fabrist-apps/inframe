import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/runnel.dart';
import 'package:runnel/src/connection/reconnect_backoff.dart';
import 'package:test/test.dart';

void main() {
  group('Runnel connection lifecycle', () {
    test('should enforce and release exact pending command and byte limits', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        limits: const RunnelLimits(maxPendingCommands: 1, maxPendingBytes: 14),
      );
      addTearDown(client.close);

      final first = client.ping();
      await peer.waitForCommandCount('PING', 1);
      final rejected = client.ping();

      await expectLater(
        rejected,
        throwsA(
          isA<RedisLimitException>()
              .having((error) => error.limit, 'limit', 1)
              .having(
                (error) => error.deliveryStatus,
                'delivery status',
                RedisDeliveryStatus.notSent,
              ),
        ),
      );
      peer.replyToNextHeld('+PONG\r\n');
      expect(await first, isTrue);

      final afterRelease = client.ping();
      await peer.waitForCommandCount('PING', 2);
      peer.replyToNextHeld('+PONG\r\n');
      expect(await afterRelease, isTrue);
    });

    test('should accept the exact pending-byte boundary and reject excess', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        limits: const RunnelLimits(maxPendingBytes: 14),
      );
      addTearDown(client.close);

      final exact = client.ping();
      await peer.waitForCommandCount('PING', 1);
      await expectLater(
        client.ping(),
        throwsA(
          isA<RedisLimitException>()
              .having((error) => error.limit, 'limit', 14)
              .having(
                (error) => error.deliveryStatus,
                'delivery status',
                RedisDeliveryStatus.notSent,
              ),
        ),
      );
      peer.replyToNextHeld('+PONG\r\n');
      expect(await exact, isTrue);
    });

    test('should report a locally expired encoded command as not sent', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint);
      addTearDown(client.close);
      final largeArgument = Uint8List(8 * 1024 * 1024);

      await expectLater(
        client.execute(
          RedisCommand<bool>([
            RedisArgument.text('ECHO'),
            RedisArgument.bytes(largeArgument),
          ], (_) => true),
          timeout: const Duration(microseconds: 1),
        ),
        throwsA(
          isA<RedisTimeoutException>().having(
            (error) => error.deliveryStatus,
            'delivery status',
            RedisDeliveryStatus.notSent,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.commandCount('ECHO'), 0);
    });

    test('should destroy a submitted generation on timeout without replaying it', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint);
      addTearDown(client.close);

      final timedOut = client.ping(timeout: const Duration(milliseconds: 20));
      await peer.waitForCommandCount('PING', 1);

      await expectLater(
        timedOut,
        throwsA(
          isA<RedisTimeoutException>()
              .having(
                (error) => error.category,
                'category',
                RedisFailureCategory.timeout,
              )
              .having(
                (error) => error.deliveryStatus,
                'delivery status',
                RedisDeliveryStatus.outcomeUnknown,
              ),
        ),
      );
      await peer.waitForConnections(2);
      expect(peer.commandCount('PING'), 1);

      peer
        ..discardNextHeld()
        ..holdCommands = false;
      await _eventually(() async {
        try {
          return await client.ping();
        } on RedisTransportException {
          return false;
        }
      });
      expect(peer.commandCount('PING'), 2);
    });

    test('should fail submitted timeout siblings as outcome unknown', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint);
      addTearDown(client.close);

      final first = client.ping(timeout: const Duration(milliseconds: 20));
      final sibling = client.ping(timeout: const Duration(seconds: 1));
      await peer.waitForCommandCount('PING', 2);

      await expectLater(first, throwsA(isA<RedisTimeoutException>()));
      await expectLater(
        sibling,
        throwsA(
          isA<RunnelException>().having(
            (error) => error.deliveryStatus,
            'delivery status',
            RedisDeliveryStatus.outcomeUnknown,
          ),
        ),
      );
    });

    test('should classify submitted transport loss as outcome unknown', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint);
      addTearDown(client.close);

      final command = client.ping();
      await peer.waitForCommandCount('PING', 1);
      peer.destroyLatest();

      await expectLater(
        command,
        throwsA(
          isA<RedisTransportException>()
              .having(
                (error) => error.category,
                'category',
                RedisFailureCategory.transport,
              )
              .having(
                (error) => error.deliveryStatus,
                'delivery status',
                RedisDeliveryStatus.outcomeUnknown,
              ),
        ),
      );
    });

    test('should reject work while reconnecting and resume after a complete handshake', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint);
      addTearDown(client.close);

      peer
        ..holdHandshakes = true
        ..destroyLatest();
      await peer.waitForConnections(2);
      await peer.waitForCommandCount('HELLO', 2);

      await expectLater(
        client.ping(),
        throwsA(
          isA<RedisTransportException>().having(
            (error) => error.deliveryStatus,
            'delivery status',
            RedisDeliveryStatus.notSent,
          ),
        ),
      );
      peer
        ..replyToNextHandshake()
        ..holdHandshakes = false;
      await _eventually(() async {
        try {
          return await client.ping();
        } on RedisTransportException {
          return false;
        }
      });
      expect(peer.commandCount('PING'), 1);
    });

    test('should drain accepted work before graceful shutdown', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        shutdownTimeout: const Duration(seconds: 1),
      );

      final command = client.ping();
      await peer.waitForCommandCount('PING', 1);
      final closing = client.close();
      await expectLater(client.ping(), throwsA(isA<RedisClosedException>()));
      peer.replyToNextHeld('+PONG\r\n');

      expect(await command, isTrue);
      await closing;
      await client.close();
    });

    test('should destroy submitted work after the shutdown deadline', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        shutdownTimeout: const Duration(milliseconds: 20),
      );

      final command = client.ping();
      await peer.waitForCommandCount('PING', 1);
      await client.close();

      await expectLater(
        command,
        throwsA(
          isA<RedisClosedException>().having(
            (error) => error.deliveryStatus,
            'delivery status',
            RedisDeliveryStatus.outcomeUnknown,
          ),
        ),
      );
      expect(peer.connectionCount, 1);
    });

    test('should classify a server error without closing the connection', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint);
      addTearDown(client.close);

      final failed = client.ping();
      await peer.waitForCommandCount('PING', 1);
      peer.replyToNextHeld('-READONLY replica\r\n');
      await expectLater(
        failed,
        throwsA(
          isA<RedisServerException>()
              .having((error) => error.code, 'code', 'READONLY')
              .having((error) => error.message, 'message', 'replica'),
        ),
      );

      final next = client.ping();
      await peer.waitForCommandCount('PING', 2);
      peer.replyToNextHeld('+PONG\r\n');
      expect(await next, isTrue);
      expect(peer.connectionCount, 1);
    });

    test('should preserve concurrent submission order while replies are pending', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint);
      addTearDown(client.close);

      final ping = client.ping();
      final get = client.get('key');
      final set = client.set('key', 'value');
      await peer.waitForCommandCount('SET', 1);

      expect(peer.ordinaryCommands, ['PING', 'GET', 'SET']);
      peer
        ..replyToNextHeld('+PONG\r\n')
        ..replyToNextHeld('\$5\r\nvalue\r\n')
        ..replyToNextHeld('+OK\r\n');
      expect(await ping, isTrue);
      expect(await get, 'value');
      expect(await set, isTrue);
    });

    test('should stop reconnecting after a terminal handshake rejection', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.hostnameEndpoint);
      addTearDown(client.close);

      peer
        ..rejectHandshakes = true
        ..destroyLatest();
      await peer.waitForConnections(2);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(peer.connectionCount, 2);
      await expectLater(client.ping(), throwsA(isA<RedisClosedException>()));
    });
  });

  group('ReconnectBackoff', () {
    test('should apply full jitter caps and reset after a complete handshake', () {
      final maximum = ReconnectBackoff(randomBelow: (upperBound) => upperBound - 1);

      expect(
        [for (var index = 0; index < 9; index++) maximum.next().inMilliseconds],
        [100, 200, 400, 800, 1600, 3200, 5000, 5000, 5000],
      );
      maximum.reset();
      expect(maximum.next(), const Duration(milliseconds: 100));

      final minimum = ReconnectBackoff(randomBelow: (_) => 0);
      expect(minimum.next(), Duration.zero);
    });
  });
}

final class _LifecyclePeer {
  _LifecyclePeer._(this._server);

  final ServerSocket _server;
  final List<_PeerSocket> _connections = [];
  final List<_HeldReply> _held = [];
  final List<_HeldReply> _heldHandshakes = [];
  final List<String> _commands = [];
  bool holdCommands = false;
  bool holdHandshakes = false;
  bool rejectHandshakes = false;

  int get connectionCount => _connections.length;
  String get endpoint => 'redis://127.0.0.1:${_server.port}';
  String get hostnameEndpoint => 'redis://localhost:${_server.port}';
  List<String> get ordinaryCommands =>
      _commands.where((command) => command != 'HELLO' && command != 'SELECT').toList();

  static Future<_LifecyclePeer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = _LifecyclePeer._(server);
    server.listen(peer._accept);
    return peer;
  }

  int commandCount(String name) => _commands.where((command) => command == name).length;

  void _accept(Socket socket) {
    final peerSocket = _PeerSocket(socket);
    _connections.add(peerSocket);
    socket.listen(
      (bytes) {
        peerSocket.buffer.addAll(bytes);
        while (true) {
          final parsed = _parseCommand(peerSocket.buffer);
          if (parsed == null) return;
          peerSocket.buffer = peerSocket.buffer.sublist(parsed.consumed);
          final command = ascii.decode(parsed.arguments.first).toUpperCase();
          _commands.add(command);
          if (command == 'HELLO') {
            if (rejectHandshakes) {
              socket.add(ascii.encode('-WRONGPASS denied\r\n'));
            } else if (holdHandshakes) {
              _heldHandshakes.add(_HeldReply(socket, parsed.arguments));
            } else {
              socket.add(ascii.encode('%1\r\n+proto\r\n:3\r\n'));
            }
          } else if (command == 'SELECT') {
            socket.add(ascii.encode('+OK\r\n'));
          } else if (holdCommands) {
            _held.add(_HeldReply(socket, parsed.arguments));
          } else if (command == 'PING') {
            socket.add(ascii.encode('+PONG\r\n'));
          }
        }
      },
      onError: (_) {},
    );
  }

  void replyToNextHeld(String frame) {
    final held = _held.removeAt(0);
    try {
      held.socket.add(ascii.encode(frame));
    } on SocketException {
      // A stale server-side socket may already observe the client's generation reset.
    }
  }

  void discardNextHeld() => _held.removeAt(0);

  void replyToNextHandshake() {
    final held = _heldHandshakes.removeAt(0);
    held.socket.add(ascii.encode('%1\r\n+proto\r\n:3\r\n'));
  }

  void destroyLatest() => _connections.last.socket.destroy();

  Future<void> waitForConnections(int count) => _eventually(() async => connectionCount >= count);

  Future<void> waitForCommandCount(String command, int count) =>
      _eventually(() async => commandCount(command) >= count);

  Future<void> close() async {
    for (final connection in _connections) {
      connection.socket.destroy();
    }
    await _server.close();
  }
}

final class _PeerSocket {
  _PeerSocket(this.socket);
  final Socket socket;
  List<int> buffer = [];
}

final class _HeldReply {
  const _HeldReply(this.socket, this.arguments);
  final Socket socket;
  final List<Uint8List> arguments;
}

Future<void> _eventually(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not become true before the test deadline.');
}

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

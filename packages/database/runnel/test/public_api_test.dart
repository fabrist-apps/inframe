import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Runnel', () {
    test('should complete the RESP3 handshake and round-trip text and bytes', () async {
      final peer = await _RespPeer.start();
      addTearDown(peer.close);

      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}').runFuture();
      addTearDown(() => client.close().runFuture());

      expect(await client.ping().runFuture(), isTrue);
      expect(await client.set('name', 'Bhaswanth').runFuture(), isTrue);
      expect(
        await client.get('name').runFuture(),
        isA<Some<String>>().having((value) => value.value, 'value', 'Bhaswanth'),
      );

      final source = Uint8List.fromList([0, 255, 1]);
      final write = client.setBytes('blob', source).runFuture();
      source[1] = 7;
      expect(await write, isTrue);
      expect(
        await client.getBytes('blob').runFuture(),
        isA<Some<Uint8List>>().having((value) => value.value, 'value', [0, 255, 1]),
      );
      expect(await client.get('missing').runFuture(), isA<None>());

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
        await expectLater(
          Runnel.connect(endpoint).runFuture(),
          throwsA(
            isA<EffectException<RunnelError>>().having(
              (error) => error.cause,
              'cause',
              isA<Expected<RunnelError>>().having(
                (cause) => cause.error,
                'error',
                isA<RunnelInputError>(),
              ),
            ),
          ),
        );
      }

      await expectLater(
        Runnel.connect(
          'redis://localhost:6379',
          securityContext: SecurityContext(),
        ).runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause,
            'cause',
            isA<Expected<RunnelError>>().having(
              (cause) => cause.error,
              'error',
              isA<RunnelInputError>(),
            ),
          ),
        ),
      );
      await expectLater(
        Runnel.connect(
          'redis://localhost:6379',
          limits: const RunnelLimits(maxFrameBytes: 0),
        ).runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause,
            'cause',
            isA<Expected<RunnelError>>().having(
              (cause) => cause.error,
              'error',
              isA<RunnelInputError>(),
            ),
          ),
        ),
      );
    });

    test('should keep credentials out of connection diagnostics', () async {
      final unavailable = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = unavailable.port;
      await unavailable.close();

      Object? failure;
      try {
        await Runnel.connect('redis://secret-user:secret-password@127.0.0.1:$port').runFuture();
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
      ).runFuture();
      final client = await connecting;
      addTearDown(() => client.close().runFuture());

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
        Runnel.connect('redis://:wrong@127.0.0.1:${peer.port}').runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelServerError>(),
          ),
        ),
      );
      await peer.socketClosed.future.timeout(const Duration(seconds: 1));
    });

    test('should keep reply alignment after a command decoder fails', () async {
      final peer = await _RespPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}').runFuture();
      addTearDown(() => client.close().runFuture());

      final invalid = client
          .execute(
            RedisCommand<int>([
              RedisArgument.text('PING'),
            ], (_) => throw const FormatException('bad')),
          )
          .runFuture();
      final valid = client.ping().runFuture();

      await expectLater(
        invalid,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause,
            'cause',
            isA<Defect<RunnelError>>().having(
              (cause) => cause.error,
              'error',
              isA<FormatException>(),
            ),
          ),
        ),
      );
      expect(await valid, isTrue);
    });

    test('should not consume pending replies with attributed pushes', () async {
      final peer = await _RespPeer.start()
        ..pushBeforeNextReply = true;
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}').runFuture();
      addTearDown(() => client.close().runFuture());

      expect(await client.ping().runFuture(), isTrue);
      expect(await client.ping().runFuture(), isTrue);
    });

    test('should invalidate the connection when a reply is malformed', () async {
      final peer = await _RespPeer.start()
        ..malformNextReply = true;
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}').runFuture();
      addTearDown(() => client.close().runFuture());

      final first = client.ping().runFuture();
      final second = client.ping().runFuture();

      await expectLater(
        first,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelProtocolError>(),
          ),
        ),
      );
      await expectLater(
        second,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelProtocolError>(),
          ),
        ),
      );
      await expectLater(
        client.ping().runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelClosedError>(),
          ),
        ),
      );
    });

    test('should reject work after idempotent close', () async {
      final peer = await _RespPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect('redis://127.0.0.1:${peer.port}').runFuture();

      await Future.wait([client.close().runFuture(), client.close().runFuture()]);

      await expectLater(
        client.ping().runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelClosedError>(),
          ),
        ),
      );
    });
  });
}

final class _RespPeer {
  late final RespPeer _peer;
  final List<List<String>> commands = [];
  final Map<String, Uint8List> _values = {};
  bool pushBeforeNextReply = false;
  bool malformNextReply = false;
  bool rejectHandshake = false;
  final Completer<void> socketClosed = Completer<void>();

  int get port => _peer.port;

  static Future<_RespPeer> start() async {
    final peer = _RespPeer();
    peer._peer = await RespPeer.start(
      onCommand: (command) {
        peer.commands.add(
          command.arguments.map((bytes) => utf8.decode(bytes, allowMalformed: true)).toList(),
        );
        peer._reply(command.socket, command.arguments);
      },
      onDisconnect: (_) {
        if (!peer.socketClosed.isCompleted) peer.socketClosed.complete();
      },
    );
    return peer;
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

  Future<void> close() => _peer.close();
}

String displayProtocol(List<Uint8List> arguments) => ascii.decode(arguments[1]);

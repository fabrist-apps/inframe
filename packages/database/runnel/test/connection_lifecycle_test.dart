import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:runnel/src/connection/legacy_errors.dart';
import 'package:runnel/src/connection/reconnect_backoff.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Runnel connection lifecycle', () {
    test('should enforce and release exact pending command and byte limits', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        limits: const RunnelLimits(maxPendingCommands: 1, maxPendingBytes: 14),
      ).runFuture();
      addTearDown(() => client.close().runFuture());

      final first = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 1);
      final rejected = client.ping().runFuture();

      await expectLater(
        rejected,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelLimitError>()
                .having((error) => error.limit, 'limit', 1)
                .having(
                  (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
                  'delivery status',
                  RedisDeliveryStatus.notSent,
                ),
          ),
        ),
      );
      peer.replyToNextHeld('+PONG\r\n');
      expect(await first, isTrue);

      final afterRelease = client.ping().runFuture();
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
      ).runFuture();
      addTearDown(() => client.close().runFuture());

      final exact = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 1);
      await expectLater(
        client.ping().runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelLimitError>()
                .having((error) => error.limit, 'limit', 14)
                .having(
                  (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
                  'delivery status',
                  RedisDeliveryStatus.notSent,
                ),
          ),
        ),
      );
      peer.replyToNextHeld('+PONG\r\n');
      expect(await exact, isTrue);
    });

    test('should report a locally expired encoded command as not sent', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final largeArgument = Uint8List(8 * 1024 * 1024);

      await expectLater(
        client
            .execute(
              RedisCommand<bool>([
                RedisArgument.text('ECHO'),
                RedisArgument.bytes(largeArgument),
              ], (_) => const Success(true)),
              timeout: const Duration(microseconds: 1),
            )
            .runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelTimeoutError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.notSent,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.commandCount('ECHO'), 0);
    });

    test('should reject a reply whose synchronous decoder exceeds the deadline', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final delayedDecode = client
          .execute(
            RedisCommand<bool>([RedisArgument.text('PING')], (_) {
              final work = Stopwatch()..start();
              while (work.elapsed < const Duration(milliseconds: 75)) {}
              return const Success(true);
            }),
            timeout: const Duration(milliseconds: 50),
          )
          .runFuture();

      await expectLater(
        delayedDecode,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelTimeoutError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.outcomeUnknown,
            ),
          ),
        ),
      );
      await _eventually(() async {
        try {
          return await client.ping().runFuture();
        } on EffectException<RunnelError> catch (error) {
          expect(
            error.cause,
            isA<Expected<RunnelError>>().having(
              (cause) => cause.error,
              'error',
              isA<RunnelTransportError>(),
            ),
          );
          return false;
        }
      });
      expect(peer.commandCount('PING'), 2);
    });

    test('should destroy a submitted generation on timeout without replaying it', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final timedOut = client.ping(timeout: const Duration(milliseconds: 20)).runFuture();
      await peer.waitForCommandCount('PING', 1);

      await expectLater(
        timedOut,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelTimeoutError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.outcomeUnknown,
            ),
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
          return await client.ping().runFuture();
        } on EffectException<RunnelError> catch (error) {
          expect(
            error.cause,
            isA<Expected<RunnelError>>().having(
              (cause) => cause.error,
              'error',
              isA<RunnelTransportError>(),
            ),
          );
          return false;
        }
      });
      expect(peer.commandCount('PING'), 2);
    });

    test('should fail submitted timeout siblings as outcome unknown', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final first = client.ping(timeout: const Duration(milliseconds: 20)).runFuture();
      final sibling = client.ping(timeout: const Duration(seconds: 1)).runFuture();
      await peer.waitForCommandCount('PING', 2);

      await expectLater(
        first,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelTimeoutError>(),
          ),
        ),
      );
      await expectLater(
        sibling,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.outcomeUnknown,
            ),
          ),
        ),
      );
    });

    test('should classify submitted transport loss as outcome unknown', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final command = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 1);
      peer.destroyLatest();

      await expectLater(
        command,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelTransportError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.outcomeUnknown,
            ),
          ),
        ),
      );
    });

    test('should reject work while reconnecting and resume after a complete handshake', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      peer
        ..holdHandshakes = true
        ..destroyLatest();
      await peer.waitForConnections(2);
      await peer.waitForCommandCount('HELLO', 2);

      await expectLater(
        client.ping().runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelTransportError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.notSent,
            ),
          ),
        ),
      );
      peer
        ..replyToNextHandshake()
        ..holdHandshakes = false;
      await _eventually(() async {
        try {
          return await client.ping().runFuture();
        } on EffectException<RunnelError> catch (error) {
          expect(
            error.cause,
            isA<Expected<RunnelError>>().having(
              (cause) => cause.error,
              'error',
              isA<RunnelTransportError>(),
            ),
          );
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
      ).runFuture();

      final command = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 1);
      final closing = client.close().runFuture();
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
      peer.replyToNextHeld('+PONG\r\n');

      expect(await command, isTrue);
      await closing;
      await client.close().runFuture();
    });

    test('should destroy submitted work after the shutdown deadline', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        shutdownTimeout: const Duration(milliseconds: 20),
      ).runFuture();

      final command = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 1);
      await client.close().runFuture();

      await expectLater(
        command,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelClosedError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.outcomeUnknown,
            ),
          ),
        ),
      );
      expect(peer.connectionCount, 1);
    });

    test('should close every owned session and pending operation once', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        shutdownTimeout: const Duration(milliseconds: 20),
      ).runFuture();
      final blocking = await client.blocking().runFuture();
      final pubSub = await client.openPubSub();

      final ordinary = client.ping().runFuture();
      final transaction = (client.transaction()..add(_pingCommand())).exec();
      final blocked = blocking.blpop(['jobs'], wait: const Duration(seconds: 30)).runFuture();
      final subscription = pubSub.subscribe(['orders']);
      final ordinaryFailure = expectLater(
        ordinary,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelClosedError>(),
          ),
        ),
      );
      final transactionFailure = expectLater(transaction, throwsA(isA<RunnelException>()));
      final blockingFailure = expectLater(
        blocked,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (e) => e.cause.expectedErrors.single,
            'error',
            isA<RunnelClosedError>(),
          ),
        ),
      );
      final subscriptionFailure = expectLater(
        subscription,
        throwsA(isA<RedisClosedException>()),
      );
      await peer.waitForCommandCount('PING', 2);
      await peer.waitForCommandCount('EXEC', 1);
      await peer.waitForCommandCount('BLPOP', 1);
      await peer.waitForCommandCount('SUBSCRIBE', 1);

      final firstClose = client.close().runFuture();
      final secondClose = client.close().runFuture();
      await firstClose.timeout(const Duration(seconds: 1));
      await Future.wait([
        ordinaryFailure,
        transactionFailure,
        blockingFailure,
        subscriptionFailure,
      ]);
      await secondClose;

      expect(pubSub.state, PubSubState.closed);
      final connectionsAfterClose = peer.connectionCount;
      expect(connectionsAfterClose, 4);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(peer.connectionCount, connectionsAfterClose);
    });

    test('should close child sessions after a terminal ordinary protocol failure', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        shutdownTimeout: const Duration(milliseconds: 50),
      ).runFuture();
      final blocking = await client.blocking().runFuture();
      final pubSub = await client.openPubSub();
      peer.holdCommands = true;

      final malformed = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 1);
      peer.replyToNextHeld('?\r\n');
      await expectLater(
        malformed,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelProtocolError>(),
          ),
        ),
      );
      final blocked = blocking.blpop(['jobs'], wait: const Duration(seconds: 30)).runFuture();
      final subscribed = pubSub.subscribe(['orders']);
      final blockedFailure = expectLater(
        blocked,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (e) => e.cause.expectedErrors.single,
            'error',
            isA<RunnelClosedError>(),
          ),
        ),
      );
      final subscribeFailure = expectLater(subscribed, throwsA(isA<RedisClosedException>()));
      await peer.waitForCommandCount('BLPOP', 1);
      await peer.waitForCommandCount('SUBSCRIBE', 1);

      await client.close().runFuture().timeout(const Duration(seconds: 1));
      await Future.wait([blockedFailure, subscribeFailure]);
      expect(pubSub.state, PubSubState.closed);
    });

    test('should cancel child connections whose handshakes are still opening', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        connectTimeout: const Duration(seconds: 30),
        shutdownTimeout: const Duration(milliseconds: 50),
      ).runFuture();
      peer.holdHandshakes = true;

      final openingBlocking = client.blocking().runFuture();
      final openingPubSub = client.openPubSub();
      final openingTransaction = (client.transaction()..add(_pingCommand())).exec();
      final blockingFailure = expectLater(openingBlocking, throwsA(anything));
      final pubSubFailure = expectLater(openingPubSub, throwsA(anything));
      final transactionFailure = expectLater(openingTransaction, throwsA(anything));
      await peer.waitForConnections(4);

      await client.close().runFuture().timeout(const Duration(seconds: 1));
      await Future.wait([blockingFailure, pubSubFailure, transactionFailure]);
      await _eventually(() async => peer.activeConnections == 0);
    });

    test('should cancel an ordinary reconnect handshake during shutdown', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        connectTimeout: const Duration(seconds: 30),
        shutdownTimeout: const Duration(milliseconds: 50),
      ).runFuture();
      peer
        ..holdHandshakes = true
        ..destroyLatest();
      await peer.waitForConnections(2);

      await client.close().runFuture().timeout(const Duration(seconds: 1));
      await _eventually(() async => peer.activeConnections == 0);
      final connectionsAfterClose = peer.connectionCount;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(peer.connectionCount, connectionsAfterClose);
    });

    test('should classify a server error without closing the connection', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final failed = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 1);
      peer.replyToNextHeld('-READONLY replica\r\n');
      await expectLater(
        failed,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelServerError>()
                .having((error) => error.code, 'code', 'READONLY')
                .having((error) => error.message, 'message', 'replica'),
          ),
        ),
      );

      final next = client.ping().runFuture();
      await peer.waitForCommandCount('PING', 2);
      peer.replyToNextHeld('+PONG\r\n');
      expect(await next, isTrue);
      expect(peer.connectionCount, 1);
    });

    test('should preserve concurrent submission order while replies are pending', () async {
      final peer = await _LifecyclePeer.start()
        ..holdCommands = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final ping = client.ping().runFuture();
      final get = client.get('key').runFuture();
      final set = client.set('key', 'value').runFuture();
      await peer.waitForCommandCount('SET', 1);

      expect(peer.ordinaryCommands, ['PING', 'GET', 'SET']);
      peer
        ..replyToNextHeld('+PONG\r\n')
        ..replyToNextHeld('\$5\r\nvalue\r\n')
        ..replyToNextHeld('+OK\r\n');
      expect(await ping, isTrue);
      expect(await get, isA<Some<String>>().having((value) => value.value, 'value', 'value'));
      expect(await set, isTrue);
    });

    test('should stop reconnecting after a terminal handshake rejection', () async {
      final peer = await _LifecyclePeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.hostnameEndpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      peer
        ..rejectHandshakes = true
        ..destroyLatest();
      await peer.waitForConnections(2);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(peer.connectionCount, 2);
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

RedisCommand<bool> _pingCommand() => RedisCommand<bool>(
  [RedisArgument.text('PING')],
  (reply) => Success(respText(reply) == 'PONG'),
);

final class _LifecyclePeer {
  late final RespPeer _peer;
  List<Socket> get _connections => _peer.sockets;
  final List<_HeldReply> _held = [];
  final List<_HeldReply> _heldHandshakes = [];
  final List<String> _commands = [];
  bool holdCommands = false;
  bool holdHandshakes = false;
  bool rejectHandshakes = false;
  int _closedConnections = 0;

  int get connectionCount => _connections.length;
  int get activeConnections => connectionCount - _closedConnections;
  String get endpoint => 'redis://127.0.0.1:${_peer.port}';
  String get hostnameEndpoint => 'redis://localhost:${_peer.port}';
  List<String> get ordinaryCommands =>
      _commands.where((command) => command != 'HELLO' && command != 'SELECT').toList();

  static Future<_LifecyclePeer> start() async {
    final peer = _LifecyclePeer();
    peer._peer = await RespPeer.start(
      onCommand: peer._handle,
      onDisconnect: (_) => peer._closedConnections++,
    );
    return peer;
  }

  int commandCount(String name) => _commands.where((command) => command == name).length;

  void _handle(RespPeerCommand received) {
    final socket = received.socket;
    final command = received.name;
    _commands.add(command);
    if (command == 'HELLO') {
      if (rejectHandshakes) {
        socket.add(ascii.encode('-WRONGPASS denied\r\n'));
      } else if (holdHandshakes) {
        _heldHandshakes.add(_HeldReply(socket, received.arguments));
      } else {
        socket.add(ascii.encode('%1\r\n+proto\r\n:3\r\n'));
      }
    } else if (command == 'SELECT') {
      socket.add(ascii.encode('+OK\r\n'));
    } else if (holdCommands) {
      _held.add(_HeldReply(socket, received.arguments));
    } else if (command == 'PING') {
      socket.add(ascii.encode('+PONG\r\n'));
    }
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

  void destroyLatest() => _connections.last.destroy();

  Future<void> waitForConnections(int count) => _eventually(() async => connectionCount >= count);

  Future<void> waitForCommandCount(String command, int count) =>
      _eventually(() async => commandCount(command) >= count);

  Future<void> close() => _peer.close();
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

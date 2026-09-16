import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/src/connection/legacy_errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/pubsub.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('PubSubSession recovery', () {
    test('should order interruptions before restored generations across disconnects', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      final events = <PubSubEvent>[];
      final listener = session.events.listen(events.add);
      addTearDown(listener.cancel);
      await session.subscribe(['orders']);

      peer.destroyLatest();
      await peer.waitForConnections(2);
      await _eventually(() => events.whereType<PubSubRestored>().length == 1);
      peer.publish('orders', [2]);
      await _eventually(() => events.whereType<PubSubMessage>().isNotEmpty);
      peer.destroyLatest();
      await peer.waitForConnections(3);
      await _eventually(() => events.whereType<PubSubRestored>().length == 2);

      expect(
        events.map((event) => (event.runtimeType, _generationOf(event))),
        [
          (PubSubInterrupted, 1),
          (PubSubRestored, 2),
          (PubSubMessage, 2),
          (PubSubInterrupted, 2),
          (PubSubRestored, 3),
        ],
      );
      expect(session.generation, 3);
      expect(session.state, PubSubState.ready);
      expect(session.lastInterruption?.cause, PubSubInterruptionCause.networkLoss);
    });

    test('should remove a channel racing restoration without resurrecting delivery', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      final events = <PubSubEvent>[];
      final listener = session.events.listen(events.add);
      addTearDown(listener.cancel);
      await session.subscribe(['orders', 'notifications']);

      peer
        ..holdAcknowledgementsFromConnection = 2
        ..destroyLatest();
      await peer.waitForCommandCount('SUBSCRIBE', 2);
      await session.unsubscribe(['orders']);
      expect(session.desiredChannels, {'notifications'});
      peer.releaseAcknowledgements();
      await _eventually(() => events.whereType<PubSubRestored>().isNotEmpty);

      final restored = events.whereType<PubSubRestored>().single;
      expect(restored.channels, {'notifications'});
      expect(session.acknowledgedChannels, {'notifications'});
      peer
        ..publish('orders', [1])
        ..publish('notifications', [2]);
      await _eventually(() => events.whereType<PubSubMessage>().isNotEmpty);
      expect(events.whereType<PubSubMessage>().map((event) => event.channel), ['notifications']);
    });

    test('should preserve newer desires when a partial subscribe is rejected', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      await session.subscribe(['established']);
      peer.partialAcknowledgementsBeforeRejection = 1;

      final first = session.subscribe(['first', 'overlap']);
      await peer.waitForHeldRejection();
      final newer = session.subscribe(['overlap', 'newer']);
      peer.rejectHeldControl();

      await expectLater(first, throwsA(isA<RedisServerException>()));
      await expectLater(newer, throwsA(isA<RedisServerException>()));
      await peer.waitForConnections(2);
      await _eventually(() => session.state == PubSubState.ready);
      expect(session.desiredChannels, {'established', 'overlap', 'newer'});
      expect(session.acknowledgedChannels, {'established', 'overlap', 'newer'});
    });

    test('should roll back only new additions after a subscription timeout', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      await session.subscribe(['established']);
      peer.holdAcknowledgementsFromConnection = 1;

      await expectLater(
        session.subscribe(['timed-out'], timeout: const Duration(milliseconds: 20)),
        throwsA(isA<RedisTimeoutException>()),
      );
      peer.holdAcknowledgementsFromConnection = null;
      await peer.waitForConnections(2);
      await _eventually(() => session.state == PubSubState.ready);

      expect(session.desiredChannels, {'established'});
      expect(session.acknowledgedChannels, {'established'});
      expect(session.lastInterruption?.cause, PubSubInterruptionCause.subscriptionTimeout);
    });

    test('should expire queued controls and release their reservations on time', () async {
      final peer = await _RecoveryPeer.start()
        ..holdAcknowledgementsFromConnection = 1;
      addTearDown(peer.close);
      final session = await _connect(
        peer,
        controlTimeout: const Duration(seconds: 1),
        connectionLimits: const RunnelLimits(maxPendingCommands: 2),
      );
      addTearDown(session.close);

      final first = session.subscribe(['first']);
      await peer.waitForCommandCount('SUBSCRIBE', 1);
      final stopwatch = Stopwatch()..start();
      final queued = session.subscribe(
        ['expired'],
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(queued, throwsA(isA<RedisTimeoutException>()));
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 200)));
      expect(session.desiredChannels, {'first'});
      peer.releaseAcknowledgements();
      await first;

      final channels = List.generate(513, (index) => 'channel-$index');
      await session.subscribe(channels);
      expect(session.acknowledgedChannels, {'first', ...channels});
    });

    test('should reset the socket when a queued unsubscribe expires', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(
        peer,
        controlTimeout: const Duration(seconds: 1),
      );
      addTearDown(session.close);
      await session.subscribe(['established']);
      peer.holdAcknowledgementsFromConnection = 1;

      final preceding = session.subscribe(['retained']);
      final precedingFailure = expectLater(preceding, throwsA(isA<RedisTimeoutException>()));
      await peer.waitForCommandCount('SUBSCRIBE', 2);
      final removal = session.unsubscribe(
        ['established'],
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(removal, throwsA(isA<RedisTimeoutException>()));
      await precedingFailure;
      await peer.waitForConnections(2);
      await _eventually(() => session.state == PubSubState.ready);

      expect(session.desiredChannels, {'retained'});
      expect(session.acknowledgedChannels, {'retained'});
      expect(
        peer.commands
            .where((command) => command.connection == 2)
            .map((command) => command.arguments),
        [
          ['3'],
          ['retained'],
        ],
      );
    });

    test('should keep removals when unsubscribe is rejected and reset the socket', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      await session.subscribe(['orders']);
      peer.rejectNextControl = true;

      await expectLater(session.unsubscribe(['orders']), throwsA(isA<RedisServerException>()));
      await peer.waitForConnections(2);
      await _eventually(() => session.state == PubSubState.ready);

      expect(session.desiredChannels, isEmpty);
      expect(session.acknowledgedChannels, isEmpty);
      expect(session.lastInterruption?.cause, PubSubInterruptionCause.subscriptionRejection);
    });

    test('should terminate when automatic restoration is denied', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      final events = <PubSubEvent>[];
      final listener = session.events.listen(events.add);
      addTearDown(listener.cancel);
      await session.subscribe(['orders']);
      peer
        ..rejectSubscriptionsFromConnection = 2
        ..destroyLatest();

      await _eventually(() => session.state == PubSubState.closed);

      final terminal = events.whereType<PubSubInterrupted>().last;
      expect(terminal.terminal, isTrue);
      expect(terminal.cause, PubSubInterruptionCause.subscriptionRejection);
      expect(session.generation, 2);
      await expectLater(session.reconnect(), throwsA(isA<RedisClosedException>()));
    });

    test('should explicitly reconnect and restore the starting desired channels', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      final events = <PubSubEvent>[];
      final listener = session.events.listen(events.add);
      addTearDown(listener.cancel);
      await session.subscribe(['orders']);

      await session.reconnect();

      expect(peer.connectionCount, 2);
      expect(session.generation, 2);
      expect(session.state, PubSubState.ready);
      expect(session.acknowledgedChannels, {'orders'});
      expect(events, [
        isA<PubSubInterrupted>()
            .having((event) => event.cause, 'cause', PubSubInterruptionCause.explicitReconnect)
            .having((event) => event.generation, 'generation', 1),
        isA<PubSubRestored>().having((event) => event.generation, 'generation', 2),
      ]);
    });

    test(
      'should coalesce explicit reconnects under the first deadline and terminate on expiry',
      () async {
        final peer = await _RecoveryPeer.start()
          ..holdHelloFromConnection = 2;
        addTearDown(peer.close);
        final session = await _connect(peer);
        addTearDown(session.close);

        final first = session.reconnect(timeout: const Duration(milliseconds: 30));
        final second = session.reconnect(timeout: const Duration(seconds: 1));

        expect(identical(first, second), isTrue);
        await expectLater(first, throwsA(isA<RedisTimeoutException>()));
        await expectLater(second, throwsA(isA<RedisTimeoutException>()));
        expect(session.state, PubSubState.closed);
        expect(peer.connectionCount, 2);
        expect(session.lastInterruption?.cause, PubSubInterruptionCause.explicitReconnect);
        expect(session.lastInterruption?.terminal, isTrue);
      },
    );

    test('should share one explicit deadline across connection and restoration', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      await session.subscribe(['orders']);
      peer
        ..delayHelloFromConnection = 2
        ..helloDelay = const Duration(milliseconds: 60)
        ..holdAcknowledgementsFromConnection = 2;
      Timer(const Duration(milliseconds: 100), peer.releaseAcknowledgements);

      await expectLater(
        session.reconnect(timeout: const Duration(milliseconds: 80)),
        throwsA(isA<RedisTimeoutException>()),
      );

      expect(session.state, PubSubState.closed);
      expect(session.lastInterruption?.cause, PubSubInterruptionCause.explicitReconnect);
    });

    test('should apply an explicit deadline while automatic recovery is in progress', () async {
      final peer = await _RecoveryPeer.start()
        ..holdHelloFromConnection = 2;
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(session.close);
      peer.destroyLatest();
      await peer.waitForConnections(2);

      await expectLater(
        session.reconnect(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<RedisTimeoutException>()),
      );

      expect(session.state, PubSubState.closed);
      await peer.waitForConnectionClosed(2);
      await session.close().timeout(const Duration(seconds: 1));
      final connectionsAfterTimeout = peer.connectionCount;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(peer.connectionCount, connectionsAfterTimeout);
    });

    test('should close during backoff without opening another socket', () async {
      final peer = await _RecoveryPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      peer.destroyLatest();
      await _eventually(() => session.state == PubSubState.reconnecting);

      await session.close().timeout(const Duration(seconds: 1));
      final connectionsAfterClose = peer.connectionCount;
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(session.state, PubSubState.closed);
      expect(peer.connectionCount, connectionsAfterClose);
    });

    test('should terminate malformed and oversized server frames without reconnecting', () async {
      for (final frame in [ascii.encode('?\r\n'), ascii.encode('\$100\r\n')]) {
        final peer = await _RecoveryPeer.start();
        final session = await _connect(
          peer,
          connectionLimits: const RunnelLimits(maxFrameBytes: 16),
        );
        final events = <PubSubEvent>[];
        final listener = session.events.listen(events.add);

        peer.sendRaw(frame);
        await _eventually(() => session.state == PubSubState.closed);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(peer.connectionCount, 1);
        expect(
          events.whereType<PubSubInterrupted>().last,
          isA<PubSubInterrupted>()
              .having((event) => event.cause, 'cause', PubSubInterruptionCause.protocolFailure)
              .having((event) => event.terminal, 'terminal', isTrue),
        );
        await listener.cancel();
        await session.close();
        await peer.close();
      }
    });
  });
}

int _generationOf(PubSubEvent event) => switch (event) {
  PubSubMessage(:final generation) => generation,
  PubSubInterrupted(:final generation) => generation,
  PubSubRestored(:final generation) => generation,
};

Future<PubSubSession> _connect(
  _RecoveryPeer peer, {
  Duration controlTimeout = const Duration(milliseconds: 200),
  RunnelLimits connectionLimits = const RunnelLimits(),
}) => PubSubSession.connect(
  PubSubConnectionConfiguration(
    host: InternetAddress.loopbackIPv4.address,
    port: peer.port,
    tls: false,
    connectTimeout: const Duration(milliseconds: 200),
    connectionLimits: connectionLimits,
  ),
  controlTimeout: controlTimeout,
);

Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not become true.');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _RecoveryPeer {
  late final RespPeer _peer;
  final List<_PeerConnection> _connections = [];
  final List<_PeerCommand> commands = [];
  final List<_HeldAcknowledgement> _heldAcknowledgements = [];
  Completer<void>? _heldRejectionReady;
  _PeerConnection? _heldRejectionConnection;
  int? holdAcknowledgementsFromConnection;
  int? holdHelloFromConnection;
  int? delayHelloFromConnection;
  Duration helloDelay = Duration.zero;
  int? rejectSubscriptionsFromConnection;
  int? partialAcknowledgementsBeforeRejection;
  bool rejectNextControl = false;

  int get port => _peer.port;
  int get connectionCount => _connections.length;

  static Future<_RecoveryPeer> start() async {
    final peer = _RecoveryPeer();
    peer._peer = await RespPeer.start(
      onConnect: (socket) =>
          peer._connections.add(_PeerConnection(socket, peer._connections.length + 1)),
      onDisconnect: (socket) => peer._connectionFor(socket).closed.complete(),
      onCommand: (command) => peer._handle(peer._connectionFor(command.socket), command.arguments),
    );
    return peer;
  }

  _PeerConnection _connectionFor(Socket socket) =>
      _connections.firstWhere((connection) => identical(connection.socket, socket));

  void destroyLatest() => _connections.last.socket.destroy();

  void sendRaw(List<int> bytes) => _connections.last.socket.add(bytes);

  int commandCount(String name) => commands.where((command) => command.name == name).length;

  Future<void> waitForConnections(int count) => _eventually(() => connectionCount >= count);

  Future<void> waitForConnectionClosed(int connection) =>
      _connections[connection - 1].closed.future.timeout(const Duration(seconds: 1));

  Future<void> waitForCommandCount(String name, int count) =>
      _eventually(() => commandCount(name) >= count);

  Future<void> waitForHeldRejection() {
    final completer = _heldRejectionReady ??= Completer<void>();
    return completer.future.timeout(const Duration(seconds: 1));
  }

  void rejectHeldControl() {
    final connection = _heldRejectionConnection!;
    _heldRejectionConnection = null;
    partialAcknowledgementsBeforeRejection = null;
    connection.socket.add(ascii.encode('-ERR subscription denied\r\n'));
  }

  void releaseAcknowledgements() {
    holdAcknowledgementsFromConnection = null;
    for (final acknowledgement in _heldAcknowledgements) {
      _acknowledge(acknowledgement.connection, acknowledgement.kind, acknowledgement.channel);
    }
    _heldAcknowledgements.clear();
  }

  void publish(String channel, List<int> payload) {
    final connection = _connections.last;
    final channelBytes = utf8.encode(channel);
    connection.socket.add([
      ...ascii.encode('>3\r\n+message\r\n\$${channelBytes.length}\r\n'),
      ...channelBytes,
      ...ascii.encode('\r\n\$${payload.length}\r\n'),
      ...payload,
      ...ascii.encode('\r\n'),
    ]);
  }

  void _handle(_PeerConnection connection, List<Uint8List> rawArguments) {
    final name = ascii.decode(rawArguments.first).toUpperCase();
    final arguments = rawArguments.skip(1).map(utf8.decode).toList(growable: false);
    commands.add(_PeerCommand(connection.number, name, arguments));
    if (name == 'HELLO') {
      if (delayHelloFromConnection == connection.number) {
        Timer(helloDelay, () => connection.socket.add(ascii.encode('+OK\r\n')));
      } else if (holdHelloFromConnection != connection.number) {
        connection.socket.add(ascii.encode('+OK\r\n'));
      }
      return;
    }
    if (name == 'SELECT') {
      connection.socket.add(ascii.encode('+OK\r\n'));
      return;
    }
    if (name != 'SUBSCRIBE' && name != 'UNSUBSCRIBE') {
      connection.socket.add(ascii.encode('-ERR unsupported\r\n'));
      return;
    }
    if (rejectNextControl ||
        (name == 'SUBSCRIBE' && rejectSubscriptionsFromConnection == connection.number)) {
      rejectNextControl = false;
      connection.socket.add(ascii.encode('-ERR subscription denied\r\n'));
      return;
    }
    final partial = partialAcknowledgementsBeforeRejection;
    if (partial != null) {
      for (final channel in arguments.take(partial)) {
        _acknowledge(connection, name.toLowerCase(), channel);
      }
      _heldRejectionConnection = connection;
      final ready = _heldRejectionReady ??= Completer<void>();
      if (!ready.isCompleted) ready.complete();
      return;
    }
    for (final channel in arguments) {
      if (holdAcknowledgementsFromConnection == connection.number) {
        _heldAcknowledgements.add(_HeldAcknowledgement(connection, name.toLowerCase(), channel));
      } else {
        _acknowledge(connection, name.toLowerCase(), channel);
      }
    }
  }

  void _acknowledge(_PeerConnection connection, String kind, String channel) {
    final channelBytes = utf8.encode(channel);
    connection.socket.add([
      ...ascii.encode('>3\r\n+$kind\r\n\$${channelBytes.length}\r\n'),
      ...channelBytes,
      ...ascii.encode('\r\n:1\r\n'),
    ]);
  }

  Future<void> close() => _peer.close();
}

final class _PeerConnection {
  _PeerConnection(this.socket, this.number);

  final Socket socket;
  final int number;
  final Completer<void> closed = Completer<void>();
}

final class _PeerCommand {
  const _PeerCommand(this.connection, this.name, this.arguments);

  final int connection;
  final String name;
  final List<String> arguments;
}

final class _HeldAcknowledgement {
  const _HeldAcknowledgement(this.connection, this.kind, this.channel);

  final _PeerConnection connection;
  final String kind;
  final String channel;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/src/connection/configuration.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/pubsub.dart';
import 'package:runnel/src/pubsub/session.dart';
import 'package:runnel/src/resp/resp_value.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Publishing commands', () {
    test('should preserve binary input and decode the broker subscriber count', () {
      final source = Uint8List.fromList([0, 255, 1]);
      final command = publishBytesCommand('updates', source);
      source[1] = 7;

      expect(command.arguments.map((argument) => argument.bytes), [
        ascii.encode('PUBLISH'),
        ascii.encode('updates'),
        [0, 255, 1],
      ]);
      expect(command.decode(const RespInteger(3)).getOrThrowWith((error) => error), 3);
      expect(
        () => command.decode(const RespSimpleString('3')).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
    });
  });

  group('PubSubSession', () {
    test(
      'should share one socket and wait for all dynamic subscription acknowledgements',
      () async {
        final peer = await _PubSubPeer.start()
          ..holdAcknowledgements = true;
        addTearDown(peer.close);
        final session = await _connect(peer);
        addTearDown(() => session.close().runFuture());

        final subscribing = session.subscribe(['orders', 'notifications', 'orders']).runFuture();
        await peer.waitForCommandCount('SUBSCRIBE', 1);
        expect(peer.connectionCount, 1);
        expect(session.state, PubSubState.subscribing);
        expect(session.desiredChannels, {'orders', 'notifications'});

        peer.acknowledgeNextChannel();
        await _expectIncomplete(subscribing);
        peer.acknowledgeNextChannel();
        await subscribing;

        expect(session.state, PubSubState.ready);
        expect(session.generation, 1);
        expect(session.acknowledgedChannels, {'orders', 'notifications'});
        expect(() => session.desiredChannels.add('mutated'), throwsUnsupportedError);

        await session.subscribe(['orders']).runFuture();
        expect(peer.commandCount('SUBSCRIBE'), 1);
      },
    );

    test('should deliver owned binary publications with strict text decoding', () async {
      final peer = await _PubSubPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(() => session.close().runFuture());
      await session.subscribe(['binary']).runFuture();
      final messages = <PubSubMessage>[];
      final listener = session.events.toStream().listen((event) {
        if (event is PubSubMessage) messages.add(event);
      });
      addTearDown(listener.cancel);

      final source = Uint8List.fromList([0, 255, 1]);
      peer.publish('binary', source);
      source[1] = 7;
      await _eventually(() => messages.isNotEmpty);

      expect(messages.single.payload, [0, 255, 1]);
      expect(messages.single.decodeText().isFailure, isTrue);
    });

    test('should let a later unsubscribe supersede an unfinished subscribe', () async {
      final peer = await _PubSubPeer.start()
        ..holdAcknowledgements = true;
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(() => session.close().runFuture());

      final subscribing = session.subscribe(['orders']).runFuture();
      await peer.waitForCommandCount('SUBSCRIBE', 1);
      final unsubscribing = session.unsubscribe(['orders']).runFuture();
      await _eventually(() => session.desiredChannels.isEmpty);
      peer.acknowledgeNextChannel();

      await expectLater(
        subscribing,
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (e) => e.cause.expectedErrors.single,
            'expected error',
            isA<RunnelSubscriptionError>(),
          ),
        ),
      );
      await peer.waitForCommandCount('UNSUBSCRIBE', 1);
      peer.acknowledgeNextChannel();
      await unsubscribing;
      expect(session.acknowledgedChannels, isEmpty);
    });

    test('should suppress queued and future delivery immediately on unsubscribe', () async {
      final peer = await _PubSubPeer.start();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(() => session.close().runFuture());
      await session.subscribe(['orders']).runFuture();

      peer.publish('orders', [1]);
      await Future<void>.delayed(Duration.zero);
      await session.unsubscribe(['orders']).runFuture();
      peer.publish('orders', [2]);
      final events = <PubSubEvent>[];
      final listener = session.events.toStream().listen(events.add, onError: _expectFlowFailure);
      addTearDown(listener.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events, isEmpty);
    });

    test('should accept exact channel/control limits and chunk controls at 512 channels', () async {
      final peer = await _PubSubPeer.start();
      addTearDown(peer.close);
      final channels = List.generate(513, (index) => 'channel-$index');
      final session = await _connect(
        peer,
        limits: const PubSubLimits(maxChannels: 513),
        connectionLimits: const RunnelLimits(maxPendingCommands: 2),
      );
      addTearDown(() => session.close().runFuture());

      await session.subscribe(channels).runFuture();

      final commands = peer.commands.where((command) => command.name == 'SUBSCRIBE').toList();
      expect(commands, hasLength(2));
      expect(commands[0].arguments, hasLength(512));
      expect(commands[1].arguments, hasLength(1));
      expect(session.desiredChannels, hasLength(513));
      await expectLater(
        session.subscribe(['excess']).runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (e) => e.cause.expectedErrors.single,
            'expected error',
            isA<RunnelLimitError>().having((error) => error.limit, 'limit', 513),
          ),
        ),
      );
    });

    test('should reject excess queued controls without changing desired state', () async {
      final peer = await _PubSubPeer.start()
        ..holdAcknowledgements = true;
      addTearDown(peer.close);
      final session = await _connect(
        peer,
        connectionLimits: const RunnelLimits(maxPendingCommands: 1),
      );
      addTearDown(() => session.close().runFuture());

      final first = session.subscribe(['one']).runFuture();
      await peer.waitForCommandCount('SUBSCRIBE', 1);
      await expectLater(
        session.subscribe(['two']).runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (e) => e.cause.expectedErrors.single,
            'expected error',
            isA<RunnelLimitError>(),
          ),
        ),
      );
      expect(session.desiredChannels, {'one'});
      peer.acknowledgeNextChannel();
      await first;
    });

    test('should terminate overflow before listening with one retained terminal event', () async {
      final peer = await _PubSubPeer.start();
      addTearDown(peer.close);
      var released = false;
      final session = await _connect(
        peer,
        limits: const PubSubLimits(maxBufferedEvents: 1),
        onClosed: (_) => released = true,
      );
      await session.subscribe(['orders']).runFuture();

      peer
        ..publish('orders', [1])
        ..publish('orders', [2]);
      await _eventually(() => session.state == PubSubState.closed);
      final events = await session.events.take(1).runCollect().runFuture();

      expect(events, [
        isA<PubSubInterrupted>()
            .having((event) => event.cause, 'cause', PubSubInterruptionCause.bufferOverflow)
            .having((event) => event.terminal, 'terminal', isTrue),
      ]);
      expect(released, isTrue);
      expect(peer.connectionCount, 1);
    });

    test('should enforce byte bounds while paused and release before resume', () async {
      final peer = await _PubSubPeer.start();
      addTearDown(peer.close);
      final session = await _connect(
        peer,
        limits: const PubSubLimits(maxBufferedBytes: 3),
      );
      await session.subscribe(['c']).runFuture();
      final events = <PubSubEvent>[];
      final done = Completer<void>();
      final listener = session.events.toStream().listen(
        events.add,
        onError: _expectFlowFailure,
        onDone: done.complete,
      )..pause();

      peer
        ..publish('c', [1, 2])
        ..publish('c', [3]);
      await _eventually(() => session.state == PubSubState.closed);
      await session.close().runFuture().timeout(const Duration(seconds: 1));
      expect(events, isEmpty);

      listener.resume();
      await done.future;
      expect(events, [isA<PubSubInterrupted>()]);
      await listener.cancel();
    });

    test('should reject one oversized publication with an active listener', () async {
      final peer = await _PubSubPeer.start();
      addTearDown(peer.close);
      final session = await _connect(
        peer,
        limits: const PubSubLimits(maxBufferedBytes: 3),
      );
      await session.subscribe(['c']).runFuture();
      final events = <PubSubEvent>[];
      final done = Completer<void>();
      final listener = session.events.toStream().listen(
        events.add,
        onError: _expectFlowFailure,
        onDone: done.complete,
      );

      peer.publish('c', [1, 2, 3]);
      await done.future.timeout(const Duration(seconds: 1));

      expect(events, [
        isA<PubSubInterrupted>()
            .having((event) => event.cause, 'cause', PubSubInterruptionCause.bufferOverflow)
            .having(
              (event) => ((event.error as Some<RunnelError>).value as RunnelLimitError).limit,
              'limit',
              3,
            ),
      ]);
      expect(session.state, PubSubState.closed);
      await listener.cancel();
    });

    test('should reject a second listener and close when the first is cancelled', () async {
      final peer = await _PubSubPeer.start();
      addTearDown(peer.close);
      final released = Completer<void>();
      final session = await _connect(
        peer,
        onClosed: (_) {
          if (!released.isCompleted) released.complete();
        },
      );
      final listener = session.events.toStream().listen((_) {});

      await Future<void>.delayed(Duration.zero);
      final rejected = await session.events.runCollect().runFutureExit();
      expect(
        (rejected as Failed<List<PubSubEvent>, RunnelError>).cause.expectedErrors.single,
        isA<RunnelUsageError>(),
      );
      expect(session.state, PubSubState.ready);
      await listener.cancel().timeout(const Duration(seconds: 1));
      await released.future;
      expect(session.state, PubSubState.closed);
      await session.close().runFuture();
    });
  });
}

Future<PubSubSession> _connect(
  _PubSubPeer peer, {
  PubSubLimits limits = const PubSubLimits(),
  RunnelLimits connectionLimits = const RunnelLimits(),
  void Function(PubSubSession)? onClosed,
}) => PubSubSessionOwnership.connect(
  ConnectionConfiguration(
    host: InternetAddress.loopbackIPv4.address,
    port: peer.port,
    tls: false,
  ),
  connectTimeout: const Duration(seconds: 1),
  connectionLimits: connectionLimits,
  limits: limits,
  controlTimeout: const Duration(seconds: 1),
  onClosed: onClosed,
);

Future<void> _expectIncomplete(Future<void> future) async {
  var completed = false;
  unawaited(future.then((_) => completed = true, onError: (_) => completed = true));
  await Future<void>.delayed(Duration.zero);
  expect(completed, isFalse);
}

Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition did not become true.');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _PubSubPeer {
  late final RespPeer _peer;
  final List<_PeerCommand> commands = [];
  List<Socket> get _sockets => _peer.sockets;
  final List<_PendingAcknowledgement> _acknowledgements = [];
  bool holdAcknowledgements = false;

  int get port => _peer.port;
  int get connectionCount => _sockets.length;

  static Future<_PubSubPeer> start() async {
    final peer = _PubSubPeer();
    peer._peer = await RespPeer.start(
      onCommand: (command) => peer._handle(command.socket, command.arguments),
    );
    return peer;
  }

  int commandCount(String name) => commands.where((command) => command.name == name).length;

  Future<void> waitForCommandCount(String name, int count) =>
      _eventually(() => commandCount(name) >= count);

  void acknowledgeNextChannel() {
    final acknowledgement = _acknowledgements.removeAt(0);
    _sendAcknowledgement(acknowledgement);
  }

  void publish(String channel, List<int> payload) {
    _sockets.single.add([
      ...ascii.encode('>3\r\n+message\r\n\$${utf8.encode(channel).length}\r\n'),
      ...utf8.encode(channel),
      ...ascii.encode('\r\n\$${payload.length}\r\n'),
      ...payload,
      ...ascii.encode('\r\n'),
    ]);
  }

  void _handle(Socket socket, List<Uint8List> rawArguments) {
    final name = ascii.decode(rawArguments.first).toUpperCase();
    final arguments = rawArguments.skip(1).map(utf8.decode).toList(growable: false);
    commands.add(_PeerCommand(name, arguments));
    switch (name) {
      case 'HELLO' || 'SELECT':
        socket.add(ascii.encode('+OK\r\n'));
      case 'SUBSCRIBE' || 'UNSUBSCRIBE':
        for (final channel in arguments) {
          final acknowledgement = _PendingAcknowledgement(socket, name.toLowerCase(), channel);
          if (holdAcknowledgements) {
            _acknowledgements.add(acknowledgement);
          } else {
            _sendAcknowledgement(acknowledgement);
          }
        }
      default:
        socket.add(ascii.encode('-ERR unsupported\r\n'));
    }
  }

  void _sendAcknowledgement(_PendingAcknowledgement acknowledgement) {
    final channelBytes = utf8.encode(acknowledgement.channel);
    acknowledgement.socket.add([
      ...ascii.encode('>3\r\n+${acknowledgement.kind}\r\n\$${channelBytes.length}\r\n'),
      ...channelBytes,
      ...ascii.encode('\r\n:1\r\n'),
    ]);
  }

  Future<void> close() => _peer.close();
}

final class _PeerCommand {
  const _PeerCommand(this.name, this.arguments);

  final String name;
  final List<String> arguments;
}

final class _PendingAcknowledgement {
  const _PendingAcknowledgement(this.socket, this.kind, this.channel);

  final Socket socket;
  final String kind;
  final String channel;
}

void _expectFlowFailure(Object error) {
  expect(error, isA<FlowException<RunnelError>>());
  expect((error as FlowException<RunnelError>).cause.expectedErrors.single, isA<RunnelError>());
}

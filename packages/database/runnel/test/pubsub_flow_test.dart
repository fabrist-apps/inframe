import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/src/connection/configuration.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/pubsub.dart';
import 'package:runnel/src/pubsub/session.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('PubSubSession Effects', () {
    test('should capture channels and defer subscription intent until execution', () async {
      final peer = await _peer();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(() => session.close().runFuture());
      final channels = ['orders'];
      final operation = session.subscribe(channels);
      channels[0] = 'changed';
      session.events;
      expect(session.desiredChannels, isEmpty);
      await operation.runFuture();
      expect(session.desiredChannels, {'orders'});
      await session.unsubscribe(['orders']).runFuture();
      await operation.runFuture();
      expect(session.desiredChannels, {'orders'});
      expect(peer.commands.where((c) => c.name == 'SUBSCRIBE'), hasLength(2));
    });

    test('should keep a session usable when interruption precedes admission', () async {
      final peer = await _peer();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(() => session.close().runFuture());
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(session.subscribe(['orders']));
      final exit = await fiber.interrupt();
      expect((exit as Failed<void, RunnelError>).cause.containsInterruption, isTrue);
      expect(session.desiredChannels, isEmpty);
      expect(session.state, PubSubState.ready);
      await session.subscribe(['orders']).runFuture();
    });

    test('should close admitted controls and fail pending siblings on interruption', () async {
      final submitted = Completer<void>();
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake() && !submitted.isCompleted) submitted.complete();
        },
      );
      addTearDown(peer.close);
      final session = await _connect(peer);
      final runtime = Runtime();
      addTearDown(runtime.close);
      final first = runtime.fork(session.subscribe(['orders']));
      await submitted.future;
      final second = runtime.fork(session.subscribe(['other']));
      await Future<void>.delayed(Duration.zero);
      final exit = await first.interrupt();
      expect((exit as Failed<void, RunnelError>).cause.containsInterruption, isTrue);
      expect(
        (await second.exit as Failed<void, RunnelError>).cause.expectedErrors.single,
        isA<RunnelClosedError>(),
      );
      expect(session.state, PubSubState.closed);
      expect(peer.sockets, hasLength(1));
    });

    test('should return invalid controls as typed errors without closing the session', () async {
      final peer = await _peer();
      addTearDown(peer.close);
      final session = await _connect(peer);
      addTearDown(() => session.close().runFuture());
      final effect = session.subscribe([]);
      final exit = await effect.runFutureExit();
      expect(
        (exit as Failed<void, RunnelError>).cause.expectedErrors.single,
        isA<RunnelInputError>(),
      );
      expect(session.state, PubSubState.ready);
      await session.subscribe(['orders']).runFuture();
    });
  });

  group('PubSubSession Flow', () {
    test('should release an acquired consumer scope without requiring a pull', () async {
      final peer = await _peer();
      addTearDown(peer.close);
      var releases = 0;
      final session = await _connect(peer, onClosed: (_) => releases++);
      await Effect.build<void, RunnelError>(($) async {
        await $(session.events.open());
      }).runFuture();
      expect(session.state, PubSubState.closed);
      expect(releases, 1);
      final second = await session.events.runCollect().runFutureExit();
      expect(
        (second as Failed<List<PubSubEvent>, RunnelError>).cause.expectedErrors.single,
        isA<RunnelUsageError>(),
      );
      await session.close().runFuture();
      expect(releases, 1);
    });

    test('should wake a waiting pull and close after early completion', () async {
      final peer = await _peer();
      addTearDown(peer.close);
      final session = await _connect(peer);
      await session.subscribe(['orders']).runFuture();
      final runtime = Runtime();
      addTearDown(runtime.close);
      final first = runtime.fork(session.events.runFirst());
      await Future<void>.delayed(Duration.zero);
      _publish(peer, 'one');
      final exit = await first.exit;
      final message =
          ((exit as Succeeded<Option<PubSubEvent>, RunnelError>).value as Some<PubSubEvent>).value
              as PubSubMessage;
      expect(message.decodeText().getOrThrowWith((error) => error), 'one');
      expect(session.state, PubSubState.closed);
    });

    test('should close a waiting consumer when interrupted', () async {
      final peer = await _peer();
      addTearDown(peer.close);
      final session = await _connect(peer);
      final runtime = Runtime();
      addTearDown(runtime.close);
      final consumer = runtime.fork(session.events.runCollect());
      await Future<void>.delayed(Duration.zero);
      final exit = await consumer.interrupt();
      expect((exit as Failed<List<PubSubEvent>, RunnelError>).cause.containsInterruption, isTrue);
      expect(session.state, PubSubState.closed);
    });

    test(
      'should discard queued publications and deliver terminal event before typed failure',
      () async {
        final closed = Completer<void>();
        final peer = await _peer();
        addTearDown(peer.close);
        final session = await _connect(
          peer,
          limits: const PubSubLimits(maxBufferedEvents: 1),
          onClosed: (_) => closed.complete(),
        );
        await session.subscribe(['orders']).runFuture();
        _publish(peer, 'one');
        _publish(peer, 'two');
        await closed.future.timeout(const Duration(seconds: 1));
        final exit = await Effect.build<void, RunnelError>(($) async {
          final cursor = await $(session.events.open());
          final event = await $(cursor.next());
          final interruption = (event as Some<PubSubEvent>).value as PubSubInterrupted;
          expect(interruption.terminal, isTrue);
          expect((interruption.error as Some<RunnelError>).value, isA<RunnelLimitError>());
          await $(cursor.next());
          fail('Terminal event must be followed by typed failure.');
        }).runFutureExit();
        expect(
          (exit as Failed<void, RunnelError>).cause.expectedErrors.single,
          isA<RunnelLimitError>(),
        );
      },
    );

    test('should report explicit reconnect without an underlying failure', () async {
      final peer = await _peer();
      addTearDown(peer.close);
      final session = await _connect(peer);
      await session.reconnect().runFuture();
      final events = await session.events.take(2).runCollect().runFuture();
      expect((events.first as PubSubInterrupted).error, isA<None>());
      expect(events.last, isA<PubSubRestored>());
    });
  });
}

Future<RespPeer> _peer() => RespPeer.start(
  onCommand: (command) {
    if (command.replyToHandshake()) return;
    if (command.name == 'SUBSCRIBE' || command.name == 'UNSUBSCRIBE') {
      for (final channel in command.textArguments.skip(1)) {
        command.reply('>3\r\n+${command.name.toLowerCase()}\r\n+$channel\r\n:1\r\n');
      }
    }
  },
);

Future<PubSubSession> _connect(
  RespPeer peer, {
  PubSubLimits limits = const PubSubLimits(),
  void Function(PubSubSession)? onClosed,
}) => PubSubSessionOwnership.connect(
  ConnectionConfiguration(
    host: InternetAddress.loopbackIPv4.address,
    port: peer.port,
    tls: false,
  ),
  connectTimeout: const Duration(seconds: 1),
  connectionLimits: const RunnelLimits(),
  limits: limits,
  onClosed: onClosed,
);

void _publish(RespPeer peer, String value) => peer.sockets.last.add(
  utf8.encode('>3\r\n+message\r\n+orders\r\n+$value\r\n'),
);

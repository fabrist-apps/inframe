import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Runnel Pub/Sub acquisition', () {
    test('should defer opening the dedicated session', () async {
      final peer = await RespPeer.start(onCommand: (command) => command.replyToHandshake());
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      client.openPubSub();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.sockets, hasLength(1));
    });

    test('should close a session interrupted during acquisition', () async {
      var handshakes = 0;
      final opening = Completer<void>();
      final released = Completer<void>();
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.name == 'HELLO' && ++handshakes == 2) {
            opening.complete();
            return;
          }
          command.replyToHandshake();
        },
        onDisconnect: (_) {
          if (!released.isCompleted) released.complete();
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(client.openPubSub());
      await opening.future;
      final exit = await fiber.interrupt();
      expect((exit as Failed<PubSubSession, RunnelError>).cause.containsInterruption, isTrue);
      await released.future.timeout(const Duration(seconds: 2));
    });

    test('should create independent sessions per run and release them from a scope', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('+PONG\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final open = client.openPubSub();
      late PubSubSession first;
      late PubSubSession second;
      await Effect.build<void, RunnelError>(($) async {
        first = await $.acquireRelease(open, release: (session, _) => session.close());
        second = await $.acquireRelease(open, release: (session, _) => session.close());
        expect(identical(first, second), isFalse);
      }).runFuture();
      expect(first.state, PubSubState.closed);
      expect(second.state, PubSubState.closed);
      expect(await client.ping().runFuture(), isTrue);
    });
  });
}

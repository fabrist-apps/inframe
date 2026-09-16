import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('BlockingSession Effects', () {
    test('should construct a blocking pop without sending it', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('_\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final session = await client.blocking().runFuture();
      session.blpop(['queue'], wait: const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.commands.where((command) => command.name == 'BLPOP'), isEmpty);
    });

    test('should snapshot keys and repeat ordinary blocking Effects', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('_\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final session = await client.blocking().runFuture();
      final keys = ['original'];
      final pop = session.blpop(keys, wait: const Duration(seconds: 1));
      keys[0] = 'mutated';
      expect(await pop.runFuture(), isA<None>());
      expect(await pop.runFuture(), isA<None>());
      expect(peer.commands.where((c) => c.name == 'BLPOP').map((c) => c.textArguments[1]), [
        'original',
        'original',
      ]);
    });

    test(
      'should release a cancelled dedicated connection and preserve its borrowed client',
      () async {
        final submitted = Completer<void>();
        final peer = await RespPeer.start(
          onCommand: (command) {
            if (command.replyToHandshake()) return;
            if (command.name == 'BLPOP') submitted.complete();
            if (command.name == 'PING') command.reply('+PONG\r\n');
          },
        );
        addTearDown(peer.close);
        final client = await Runnel.connect(peer.endpoint).runFuture();
        addTearDown(() => client.close().runFuture());
        final session = await client.blocking().runFuture();
        final runtime = Runtime();
        addTearDown(runtime.close);
        final fiber = runtime.fork(session.blpop(['queue'], wait: const Duration(seconds: 30)));
        await submitted.future;
        final exit = await fiber.interrupt();
        expect(
          (exit as Failed<Option<({String key, String value})>, RunnelError>)
              .cause
              .containsInterruption,
          isTrue,
        );
        final next = await session.blpop([
          'queue',
        ], wait: const Duration(seconds: 1)).runFutureExit();
        expect(
          (next as Failed<Option<({String key, String value})>, RunnelError>)
              .cause
              .expectedErrors
              .single,
          isA<RunnelClosedError>(),
        );
        expect(await client.ping().runFuture(), isTrue);
        await session.close().runFuture();
      },
    );

    test('should release a session acquisition cancelled during handshake', () async {
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
      final fiber = runtime.fork(client.blocking());
      await opening.future;
      final exit = await fiber.interrupt();
      expect((exit as Failed<BlockingSession, RunnelError>).cause.containsInterruption, isTrue);
      await released.future.timeout(const Duration(seconds: 2));
    });
  });
}

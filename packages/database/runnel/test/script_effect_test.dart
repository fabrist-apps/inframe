import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('RedisScript Effects', () {
    test('should construct a script execution without submitting it', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('_\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      client.runScript(
        RedisScript<String?>('return nil', (_) => const Success(null)),
        keys: [],
        arguments: [],
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.commands.where((c) => c.name == 'EVALSHA'), isEmpty);
    });

    test('should not fallback for a decoder-produced NOSCRIPT failure', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('+OK\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final script = RedisScript<void>(
        'return 1',
        (_) => const Failure(RunnelServerError('decoder failure', code: 'NOSCRIPT')),
      );
      final exit = await client.runScript(script, keys: [], arguments: []).runFutureExit();
      expect(
        (exit as Failed<void, RunnelError>).cause.expectedErrors.single,
        isA<RunnelServerError>(),
      );
      expect(peer.commands.where((c) => c.name == 'EVAL'), isEmpty);
    });

    test(
      'should preserve exact nullable script values and captured arguments across runs',
      () async {
        final peer = await RespPeer.start(
          onCommand: (command) {
            if (!command.replyToHandshake()) command.reply('_\r\n');
          },
        );
        addTearDown(peer.close);
        final client = await Runnel.connect(peer.endpoint).runFuture();
        addTearDown(() => client.close().runFuture());
        final keys = ['original'];
        final arguments = [RedisArgument.text('value')];
        final effect = client.runScript(
          RedisScript<String?>('return nil', (_) => const Success(null)),
          keys: keys,
          arguments: arguments,
        );
        keys[0] = 'changed';
        arguments.clear();
        expect(await effect.runFuture(), isNull);
        expect(await effect.runFuture(), isNull);
        final nested = client.runScript(
          RedisScript<Option<String?>>('return nil', (_) => const Success(Some(null))),
          keys: [],
          arguments: [],
        );
        expect(
          await nested.runFuture(),
          isA<Some<String?>>().having((s) => s.value, 'value', isNull),
        );
        for (final command in peer.commands.where((c) => c.name == 'EVALSHA').take(2)) {
          expect(command.textArguments.skip(3), ['original', 'value']);
        }
      },
    );

    test('should stop a cancelled script before any NOSCRIPT fallback', () async {
      final submitted = Completer<RespPeerCommand>();
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          if (!submitted.isCompleted) submitted.complete(command);
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(
        client.runScript(
          RedisScript<void>('return nil', (_) => const Success(null)),
          keys: [],
          arguments: [],
        ),
      );
      final command = await submitted.future;
      final interruption = fiber.interrupt();
      command.reply('-NOSCRIPT missing\r\n');
      expect((await interruption as Failed<void, RunnelError>).cause.containsInterruption, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.commands.where((c) => c.name == 'EVAL'), isEmpty);
    });

    test('should preserve thrown script decoder errors as defects with their stack', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('+OK\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      const error = RunnelServerError('thrown decoder error', code: 'NOSCRIPT');
      final stack = StackTrace.current;
      final script = RedisScript<void>(
        'return nil',
        (_) => Error.throwWithStackTrace(error, stack),
      );
      final exit = await client.runScript(script, keys: [], arguments: []).runFutureExit();
      final cause = (exit as Failed<void, RunnelError>).cause as Defect<RunnelError>;
      expect(cause.error, same(error));
      expect(cause.stackTrace.toString(), stack.toString());
      expect(peer.commands.where((c) => c.name == 'EVAL'), isEmpty);
    });
  });
}

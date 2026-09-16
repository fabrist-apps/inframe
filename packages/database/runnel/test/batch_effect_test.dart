import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('RedisBatch Effects', () {
    test('should freeze without executing the batch', () {
      var transmissions = 0;
      final batch =
          RedisBatch.internal(
              maxCommands: 10,
              maxBytes: 1024,
              reservedCommands: 0,
              reservedBytes: 0,
              defaultTimeout: const Duration(seconds: 1),
              executor: (commands, timeout, operation) async {
                transmissions++;
                return [const Success<Object?, RunnelError>(1)];
              },
            )
            ..add(incrCommand('counter'))
            ..exec();
      expect(transmissions, 0);
      expect(() => batch.add(incrCommand('counter')), throwsStateError);
    });

    test('should atomically claim once across concurrent and repeated runs', () async {
      var transmissions = 0;
      final entered = Completer<void>();
      final finish = Completer<void>();
      final batch = RedisBatch.internal(
        maxCommands: 10,
        maxBytes: 1024,
        reservedCommands: 0,
        reservedBytes: 0,
        defaultTimeout: const Duration(seconds: 1),
        executor: (commands, timeout, operation) async {
          transmissions++;
          entered.complete();
          await finish.future;
          return [const Success<Object?, RunnelError>(1)];
        },
      );
      final reference = batch.add(incrCommand('counter'));
      final effect = batch.exec();
      final first = effect.runFuture();
      await entered.future;
      final second = await effect.runFutureExit();
      expect(
        (second as Failed<BatchResults, RunnelError>).cause.expectedErrors.single,
        isA<RunnelUsageError>(),
      );
      finish.complete();
      final result = await first;
      expect(result.outcome(reference).getOrThrowWith((e) => e), 1);
      expect(transmissions, 1);
    });

    test('should not consume a batch interrupted before executor entry', () async {
      var transmissions = 0;
      final batch = RedisBatch.internal(
        maxCommands: 10,
        maxBytes: 1024,
        reservedCommands: 0,
        reservedBytes: 0,
        defaultTimeout: const Duration(seconds: 1),
        executor: (commands, timeout, operation) async {
          transmissions++;
          return [const Success<Object?, RunnelError>(1)];
        },
      )..add(incrCommand('counter'));
      final effect = batch.exec();
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(effect);
      await fiber.interrupt();
      expect(transmissions, 0);
      await effect.runFuture();
      expect(transmissions, 1);
    });

    test('should preserve nullable and Option-valued pipeline successes exactly', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('_\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final batch = client.pipeline();
      final nullable = batch.add(
        RedisCommand<String?>([RedisArgument.text('CUSTOM')], (_) => const Success(null)),
      );
      final absent = batch.add(
        RedisCommand<Option<String?>>([RedisArgument.text('CUSTOM')], (_) => const Success(None())),
      );
      final present = batch.add(
        RedisCommand<Option<String?>>([
          RedisArgument.text('CUSTOM'),
        ], (_) => const Success(Some(null))),
      );
      final results = await batch.exec().runFuture();
      expect(results.outcome(nullable).getOrThrowWith((e) => e), isNull);
      expect(results.outcome(absent).getOrThrowWith((e) => e), isA<None>());
      expect(
        results.outcome(present).getOrThrowWith((e) => e),
        isA<Some<String?>>().having((s) => s.value, 'value', isNull),
      );
    });

    test(
      'should fail the outer pipeline for a decoder defect while observing other replies',
      () async {
        final peer = await RespPeer.start(
          onCommand: (command) {
            if (!command.replyToHandshake()) command.reply('+OK\r\n');
          },
        );
        addTearDown(peer.close);
        final client = await Runnel.connect(peer.endpoint).runFuture();
        addTearDown(() => client.close().runFuture());
        const error = RunnelUsageError('thrown callback');
        final batch = client.pipeline()
          ..add(RedisCommand<void>([RedisArgument.text('CUSTOM')], (_) => throw error))
          ..add(RedisCommand<void>([RedisArgument.text('CUSTOM')], (_) => const Success(null)));
        final exit = await batch.exec().runFutureExit();
        expect(
          (exit as Failed<BatchResults, RunnelError>).cause,
          isA<Defect<RunnelError>>().having((c) => c.error, 'error', same(error)),
        );
        expect(peer.commands.where((c) => c.name == 'CUSTOM'), hasLength(2));
      },
    );

    test('should interrupt a submitted transaction without making it reusable', () async {
      final executed = Completer<void>();
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          switch (command.name) {
            case 'MULTI':
              command.reply('+OK\r\n');
            case 'EXEC':
              executed.complete();
            default:
              command.reply('+QUEUED\r\n');
          }
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final batch = client.transaction()..add(incrCommand('counter'));
      final effect = batch.exec();
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(effect);
      await executed.future;
      final exit = await fiber.interrupt();
      expect((exit as Failed<BatchResults, RunnelError>).cause.containsInterruption, isTrue);
      final repeated = await effect.runFutureExit();
      expect(
        (repeated as Failed<BatchResults, RunnelError>).cause.expectedErrors.single,
        isA<RunnelUsageError>(),
      );
      expect(peer.commands.where((c) => c.name == 'EXEC'), hasLength(1));
    });
  });
}

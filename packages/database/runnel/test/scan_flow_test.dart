import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Runnel SCAN Flow', () {
    test('should start every consumption at zero and retain duplicates', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          command.reply(
            command.textArguments[1] == '0'
                ? '*2\r\n+7\r\n*2\r\n+a\r\n+b\r\n'
                : '*2\r\n+0\r\n*2\r\n+b\r\n+c\r\n',
          );
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final flow = client.scan(match: 'item:*', count: 2);
      expect(peer.commands, hasLength(1));
      for (var run = 0; run < 2; run++) {
        expect(await flow.runCollect().runFuture(), ['a', 'b', 'b', 'c']);
      }
      expect(peer.commands.skip(1).map((command) => command.textArguments), [
        ['SCAN', '0', 'MATCH', 'item:*', 'COUNT', '2'],
        ['SCAN', '7', 'MATCH', 'item:*', 'COUNT', '2'],
        ['SCAN', '0', 'MATCH', 'item:*', 'COUNT', '2'],
        ['SCAN', '7', 'MATCH', 'item:*', 'COUNT', '2'],
      ]);
    });
    test('should exhaust a page before pulling again and stop on scope exit', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          command.reply('*2\r\n+7\r\n*2\r\n+first\r\n+second\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final flow = client.scan();
      await Effect.build<void, RunnelError>(($) async {
        final cursor = await $(flow.open());
        expect(peer.commands, hasLength(1));
        expect((await $(cursor.next()) as Some<String>).value, 'first');
        await Future<void>.delayed(Duration.zero);
        expect(peer.commands, hasLength(2));
        expect((await $(cursor.next()) as Some<String>).value, 'second');
        await Future<void>.delayed(Duration.zero);
        expect(peer.commands, hasLength(2));
      }).runFuture();
      expect(peer.commands, hasLength(2));
      expect(await flow.take(1).runCollect().runFuture(), ['first']);
      expect(peer.commands, hasLength(3));
    });

    test('should advance empty pages and observe changes between page reads', () async {
      var changed = false;
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          command.reply(switch (command.textArguments[1]) {
            '0' => '*2\r\n+5\r\n*0\r\n',
            '5' => '*2\r\n+9\r\n*1\r\n+same\r\n',
            _ => '*2\r\n+0\r\n*2\r\n+same\r\n+${changed ? 'new' : 'old'}\r\n',
          });
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final values = <String>[];
      await client
          .scan()
          .runForEach(
            (value, _) => Effect.sync((_) {
              values.add(value);
              changed = true;
            }),
          )
          .runFuture();
      expect(values, ['same', 'same', 'new']);
      expect(peer.commands.skip(1).map((command) => command.textArguments[1]), ['0', '5', '9']);
    });

    test('should keep simultaneous consumers independent', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          command.reply(
            command.textArguments[1] == '0'
                ? '*2\r\n+1\r\n*1\r\n+first\r\n'
                : '*2\r\n+0\r\n*1\r\n+last\r\n',
          );
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final flow = client.scan();
      final values = await Effect.all([
        flow.runCollect(),
        flow.runCollect(),
      ], concurrency: 2).runFuture();
      expect(values, [
        ['first', 'last'],
        ['first', 'last'],
      ]);
      expect(
        peer.commands.skip(1).where((command) => command.textArguments[1] == '0'),
        hasLength(2),
      );
    });

    test('should preserve typed errors and validate count only on consumption', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('-ERR denied\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final invalid = client.scan(count: 0);
      expect(peer.commands, hasLength(1));
      final invalidExit = await invalid.runCollect().runFutureExit();
      expect(
        (invalidExit as Failed<List<String>, RunnelError>).cause.expectedErrors.single,
        isA<RunnelInputError>(),
      );
      expect(peer.commands, hasLength(1));
      final denied = await client.scan().runCollect().runFutureExit();
      expect(
        (denied as Failed<List<String>, RunnelError>).cause.expectedErrors.single,
        isA<RunnelServerError>().having((error) => error.code, 'code', 'ERR'),
      );
      expect(peer.commands, hasLength(2));
    });

    test('should cancel an outstanding page and fail submitted siblings safely', () async {
      final pageSubmitted = Completer<void>();
      final pingSubmitted = Completer<void>();
      final disconnected = Completer<void>();
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          if (command.name == 'SCAN') pageSubmitted.complete();
          if (command.name == 'PING') pingSubmitted.complete();
        },
        onDisconnect: (_) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final fiber = Runtime().fork(client.scan().runCollect());
      await pageSubmitted.future;
      final sibling = client.ping().runFutureExit();
      await pingSubmitted.future;
      final exit = await fiber.interrupt('stop scan');
      expect((exit as Failed<List<String>, RunnelError>).cause.containsInterruption, isTrue);
      final siblingExit = await sibling;
      expect(
        (siblingExit as Failed<bool, RunnelError>).cause.expectedErrors.single,
        isA<RunnelTransportError>().having(
          (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
          'delivery',
          RedisDeliveryStatus.outcomeUnknown,
        ),
      );
      await disconnected.future.timeout(const Duration(seconds: 1));
      expect(peer.commands.where((command) => command.name == 'SCAN'), hasLength(1));
    });

    test('should support explicit Stream interop', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('*2\r\n+0\r\n*2\r\n+a\r\n+b\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      expect(await client.scan().toStream().toList(), ['a', 'b']);
    });
  });
}

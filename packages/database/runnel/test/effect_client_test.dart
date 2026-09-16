import 'dart:async';
import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Runnel Effects', () {
    test('should connect lazily and create an independent owned client per run', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          command.replyToHandshake();
        },
      );
      addTearDown(peer.close);
      final connect = Runnel.connect(peer.endpoint);
      expect(peer.sockets, isEmpty);
      final first = await connect.runFuture();
      final second = await connect.runFuture();
      expect(identical(first, second), isFalse);
      expect(peer.sockets, hasLength(2));
      await first.close().runFuture();
      await second.close().runFuture();
    });

    test('should round trip in a scope and retain missing and nullable values', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          command.reply(command.name == 'SET' ? '+OK\r\n' : '_\r\n');
        },
      );
      addTearDown(peer.close);
      final value = await Effect.build<Option<String>, RunnelError>(($) async {
        final client = await $.acquireRelease(
          Runnel.connect(peer.endpoint),
          release: (client, _) => client.close(),
        );
        final write = client.set('key', 'value');
        expect(peer.commands.where((c) => c.name == 'SET'), isEmpty);
        expect(await $(write), isTrue);
        expect(await $(write), isTrue);
        expect(
          await $(
            client.execute(
              RedisCommand<String?>([RedisArgument.text('CUSTOM')], (_) => const Success(null)),
            ),
          ),
          isNull,
        );
        expect(
          await $(
            client.execute(
              RedisCommand<Option<String?>>([
                RedisArgument.text('CUSTOM'),
              ], (_) => const Success(Some(null))),
            ),
          ),
          isA<Some<String?>>().having((v) => v.value, 'value', isNull),
        );
        return $(client.get('missing'));
      }).runFuture();
      expect(value, isA<None>());
      expect(peer.commands.where((c) => c.name == 'SET'), hasLength(2));
    });

    test('should reject invalid configuration at execution without exposing credentials', () async {
      final effect = Runnel.connect('redis://user:secret@localhost/not-a-database');
      final exit = await effect.runFutureExit();
      final error = (exit as Failed<Runnel, RunnelError>).cause.expectedErrors.single;
      expect(error, isA<RunnelInputError>());
      expect(error.toString(), isNot(contains('secret')));
    });

    test('should preserve custom decoder defects and consume their matching reply', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('+PONG\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final error = StateError('decoder');
      final stack = StackTrace.current;
      final exit = await client
          .execute(
            RedisCommand<String>([
              RedisArgument.text('PING'),
            ], (_) => Error.throwWithStackTrace(error, stack)),
          )
          .runFutureExit();
      final cause = (exit as Failed<String, RunnelError>).cause as Defect<RunnelError>;
      expect(cause.error, same(error));
      expect(cause.stackTrace.toString(), stack.toString());
      expect(await client.ping().runFuture(), isTrue);
    });

    test('should cancel submitted work without assigning its reply to a sibling', () async {
      final submitted = Completer<void>();
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          if (!submitted.isCompleted) submitted.complete();
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final runtime = Runtime();
      addTearDown(runtime.close);
      final first = runtime.fork(client.ping());
      final second = runtime.fork(client.ping());
      await submitted.future;
      final exit = await first.interrupt('stop');
      expect((exit as Failed<bool, RunnelError>).cause.containsInterruption, isTrue);
      final sibling = await second.exit;
      final error = (sibling as Failed<bool, RunnelError>).cause.expectedErrors.single;
      expect(
        error.deliveryStatus,
        isA<Some<RedisDeliveryStatus>>().having(
          (s) => s.value,
          'status',
          RedisDeliveryStatus.outcomeUnknown,
        ),
      );
    });

    test('should release an acquisition cancelled during handshake', () async {
      final handshake = Completer<void>();
      final disconnected = Completer<void>();
      final peer = await RespPeer.start(
        onCommand: (_) {
          if (!handshake.isCompleted) handshake.complete();
        },
        onDisconnect: (_) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
      addTearDown(peer.close);
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(Runnel.connect(peer.endpoint));
      await handshake.future;
      final exit = await fiber.interrupt('stop acquisition');
      expect((exit as Failed<Runnel, RunnelError>).cause.containsInterruption, isTrue);
      await disconnected.future.timeout(const Duration(seconds: 2));
    });

    test('should leave a borrowed client usable when command scopes end', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('+PONG\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      expect(await client.ping().runFuture(), isTrue);
      expect(await client.ping().runFuture(), isTrue);
    });

    test('should remove only a request cancelled before physical submission', () async {
      final peer = await RespPeer.start(onCommand: (command) => command.reply('+PONG\r\n'));
      addTearDown(peer.close);
      final connection = await RedisConnection.open(
        host: '127.0.0.1',
        port: peer.port,
        tls: false,
        securityContext: null,
        limits: const RunnelLimits(),
        timeout: const Duration(seconds: 1),
        onTerminated: (_, _) {},
      );
      addTearDown(connection.close);
      final operation = RunnelOperation();
      final command = RedisCommand<bool>([RedisArgument.text('PING')], (_) => const Success(true));
      final first = connection.execute(
        command,
        timeout: const Duration(seconds: 1),
        operation: operation,
      );
      final observed = first.then<Object?>((value) => value, onError: (Object error) => error);
      final second = connection.execute(command, timeout: const Duration(seconds: 1));
      await operation.cancel();
      await observed;
      expect(await second, isTrue);
      expect(peer.commands, hasLength(1));
      expect(connection.pendingCount, 0);
      expect(connection.pendingBytes, 0);
    });

    test('should start deadlines on execution and return typed decoding failures', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          command.reply(command.name == 'GET' ? ':42\r\n' : '+PONG\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final effect = client.ping(timeout: const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(peer.commands.where((c) => c.name == 'PING'), isEmpty);
      expect(await effect.runFuture(), isTrue);
      final exit = await client.get('key').runFutureExit();
      expect(
        (exit as Failed<Option<String>, RunnelError>).cause.expectedErrors.single,
        isA<RunnelDecodingError>(),
      );
      expect(await client.ping().runFuture(), isTrue);
    });

    test('should preserve a thrown domain error as a decoder defect', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('+OK\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      const error = RunnelUsageError('callback threw');
      final exit = await client
          .execute(RedisCommand<void>([RedisArgument.text('CUSTOM')], (_) => throw error))
          .runFutureExit();
      expect(
        (exit as Failed<void, RunnelError>).cause,
        isA<Defect<RunnelError>>().having((c) => c.error, 'error', same(error)),
      );
    });

    test('should report connection refusal as an expected transport error', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final exit = await Runnel.connect('redis://127.0.0.1:$port').runFutureExit();
      expect(
        (exit as Failed<Runnel, RunnelError>).cause,
        isA<Expected<RunnelError>>().having((c) => c.error, 'error', isA<RunnelTransportError>()),
      );
    });

    test('should retain decoder defects even when decoding exceeds the deadline', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('+OK\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final error = StateError('slow decoder');
      final stack = StackTrace.current;
      final exit = await client
          .execute(
            RedisCommand<void>([RedisArgument.text('CUSTOM')], (_) {
              final watch = Stopwatch()..start();
              while (watch.elapsedMilliseconds < 35) {}
              Error.throwWithStackTrace(error, stack);
            }),
            timeout: const Duration(milliseconds: 25),
          )
          .runFutureExit();
      expect(
        (exit as Failed<void, RunnelError>).cause,
        isA<Defect<RunnelError>>().having((c) => c.error, 'error', same(error)),
      );
    });

    test('should retain operation and cleanup causes through result conversion', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply('-ERR rejected\r\n');
        },
      );
      addTearDown(peer.close);
      final cleanup = StateError('cleanup');
      final program = Effect.build<bool, RunnelError>(($) async {
        final client = await $.acquireRelease(
          Runnel.connect(peer.endpoint),
          release: (client, _) =>
              client.close().flatMap((_, _) => Effect.sync((_) => throw cleanup)),
        );
        return $(client.ping());
      });
      final exit = await Effect.using(program).result().runFutureExit();
      final cause = (exit as Failed<Result<bool, RunnelError>, RunnelError>).cause;
      expect(cause, isA<Sequential<RunnelError>>());
      expect(cause.expectedErrors.single, isA<RunnelServerError>());
      expect(
        (cause as Sequential<RunnelError>).causes.last,
        isA<Defect<RunnelError>>().having((c) => c.error, 'error', same(cleanup)),
      );
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('RedisBatch connection', () {
    test('an execution-capacity failure transmits no batch prefix', () async {
      final peer = await _BatchPeer.start()
        ..holdPings = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(
        peer.endpoint,
        limits: const RunnelLimits(maxPendingCommands: 2),
      ).runFuture();
      addTearDown(() => client.close().runFuture());

      final pending = client.ping().runFuture();
      await peer.waitFor('PING', 1);
      final pipeline = client.pipeline()
        ..add(_pingCommand())
        ..add(_pingCommand());

      await expectLater(
        pipeline.exec().runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'error',
            isA<RunnelLimitError>(),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(peer.count('PING'), 1);

      peer.replyHeldPing();
      expect(await pending, isTrue);
    });

    test('losing EXEC reports uncertainty and does not replay the transaction', () async {
      final peer = await _BatchPeer.start()
        ..dropExec = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final transaction = client.transaction()..add(incrCommand('counter'));

      await expectLater(
        transaction.exec().runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'error',
            isA<RunnelError>().having(
              (error) => (error.deliveryStatus as Some<RedisDeliveryStatus>).value,
              'delivery status',
              RedisDeliveryStatus.outcomeUnknown,
            ),
          ),
        ),
      );

      expect(peer.count('EXEC'), 1);
      expect(peer.count('INCR'), 1);
      expect(await client.ping().runFuture(), isTrue);
    });

    test('transaction result decoding cannot overrun the total deadline', () async {
      final peer = await _BatchPeer.start()
        ..returnOneFromExec = true;
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final transaction = client.transaction()
        ..add(
          RedisCommand<int>([RedisArgument.text('INCR'), RedisArgument.text('counter')], (reply) {
            final work = Stopwatch()..start();
            while (work.elapsed < const Duration(milliseconds: 75)) {}
            return Success((reply as RespInteger).value);
          }),
        );

      await expectLater(
        transaction.exec(timeout: const Duration(milliseconds: 50)).runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'error',
            isA<RunnelTimeoutError>(),
          ),
        ),
      );
    });
  });
}

RedisCommand<bool> _pingCommand() => RedisCommand<bool>(
  [RedisArgument.text('PING')],
  (reply) => Success(respText(reply) == 'PONG'),
);

final class _BatchPeer {
  late final RespPeer _peer;
  final Set<Socket> _transactions = {};
  final List<Socket> _heldPings = [];
  bool holdPings = false;
  bool dropExec = false;
  bool returnOneFromExec = false;

  String get endpoint => _peer.endpoint;

  static Future<_BatchPeer> start() async {
    final peer = _BatchPeer();
    peer._peer = await RespPeer.start(onCommand: peer._handle);
    return peer;
  }

  int count(String name) => _peer.commands.where((command) => command.name == name).length;

  void _handle(RespPeerCommand command) {
    if (command.replyToHandshake()) return;
    final socket = command.socket;
    switch (command.name) {
      case 'MULTI':
        _transactions.add(socket);
        command.reply('+OK\r\n');
      case 'EXEC' when dropExec:
        socket.destroy();
      case 'EXEC':
        command.reply(returnOneFromExec ? '*1\r\n:1\r\n' : '*0\r\n');
      case 'PING' || 'INCR' when _transactions.contains(socket):
        command.reply('+QUEUED\r\n');
      case 'PING' when holdPings:
        _heldPings.add(socket);
      case 'PING':
        command.reply('+PONG\r\n');
      default:
        command.reply('-ERR unsupported\r\n');
    }
  }

  void replyHeldPing() => _heldPings.removeAt(0).add(ascii.encode('+PONG\r\n'));

  Future<void> waitFor(String command, int expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (count(command) < expected) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Did not receive $expected $command commands.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> close() => _peer.close();
}

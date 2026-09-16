import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:runnel/src/connection/legacy_errors.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  test('EVAL and EVALSHA preserve exact keys, binary arguments, and decoding', () {
    final binary = Uint8List.fromList([0, 255, 13, 10]);
    final keys = ['key:one', 'key:two'];
    final arguments = [RedisArgument.text('plain'), RedisArgument.bytes(binary)];
    final script = RedisScript<int>('return #KEYS + #ARGV', (reply) {
      if (reply case RespInteger(:final value)) return value;
      throw const FormatException('Expected an integer script result.');
    });

    final eval = evalCommand(script, keys: keys, arguments: arguments);
    final evalsha = evalshaCommand(script, keys: keys, arguments: arguments);
    keys
      ..clear()
      ..add('changed');
    arguments.clear();
    binary.fillRange(0, binary.length, 42);

    expect(_arguments(eval), [
      ascii.encode('EVAL'),
      utf8.encode('return #KEYS + #ARGV'),
      ascii.encode('2'),
      utf8.encode('key:one'),
      utf8.encode('key:two'),
      utf8.encode('plain'),
      [0, 255, 13, 10],
    ]);
    expect(
      evalsha.arguments.take(4).map((argument) => utf8.decode(argument.bytes)),
      ['EVALSHA', script.sha1, '2', 'key:one'],
    );
    expect(script.sha1, '6e550ab7cf45e2ef5d2af047fbc92dd7594f4005');
    expect(eval.decode(const RespInteger(6)).getOrThrowWith((error) => error), 6);
  });

  test('runScript falls back only from NOSCRIPT and warms the cache path', () async {
    final peer = await _ScriptPeer.start(evalshaDelay: const Duration(milliseconds: 10));
    addTearDown(peer.close);
    final client = await Runnel.connect(peer.endpoint).runFuture();
    addTearDown(() => client.close().runFuture());
    final script = RedisScript<String>('return ARGV[1]', respText);
    final keys = ['literal:key'];
    final arguments = [RedisArgument.text('decoded')];

    final coldExecution = client.runScript(
      script,
      keys: keys,
      arguments: arguments,
      timeout: const Duration(seconds: 1),
    );
    keys[0] = 'changed:key';
    arguments[0] = RedisArgument.text('changed');
    expect(await coldExecution, 'decoded');
    expect(
      await client.runScript(
        script,
        keys: ['literal:key'],
        arguments: [RedisArgument.text('decoded')],
        timeout: const Duration(seconds: 1),
      ),
      'decoded',
    );

    expect(peer.commands.where((command) => command.name == 'EVALSHA'), hasLength(2));
    expect(peer.commands.where((command) => command.name == 'EVAL'), hasLength(1));
    expect(peer.commands.firstWhere((command) => command.name == 'EVAL').textArguments, [
      'EVAL',
      'return ARGV[1]',
      '1',
      'literal:key',
      'decoded',
    ]);
  });

  test('a non-NOSCRIPT server error does not execute source', () async {
    final peer = await _ScriptPeer.start(evalshaError: '-ERR script failed\r\n');
    addTearDown(peer.close);
    final client = await Runnel.connect(peer.endpoint).runFuture();
    addTearDown(() => client.close().runFuture());
    final script = RedisScript<int>('return 1', (reply) => (reply as RespInteger).value);

    await expectLater(
      client.runScript(
        script,
        keys: const [],
        arguments: const [],
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<RedisServerException>().having((error) => error.code, 'code', 'ERR'),
      ),
    );
    expect(peer.commands.where((command) => command.name == 'EVAL'), isEmpty);
  });

  test('transport loss after EVALSHA never replays with EVAL', () async {
    final peer = await _ScriptPeer.start(dropEvalsha: true);
    addTearDown(peer.close);
    final client = await Runnel.connect(peer.endpoint).runFuture();
    addTearDown(() => client.close().runFuture());
    final script = RedisScript<int>('return 1', (reply) => (reply as RespInteger).value);

    await expectLater(
      client.runScript(
        script,
        keys: const [],
        arguments: const [],
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<RedisTransportException>().having(
          (error) => error.deliveryStatus,
          'delivery status',
          RedisDeliveryStatus.outcomeUnknown,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(peer.commands.where((command) => command.name == 'EVAL'), isEmpty);
  });

  test('an EVALSHA timeout never retries with EVAL', () async {
    final peer = await _ScriptPeer.start(evalshaDelay: const Duration(milliseconds: 100));
    addTearDown(peer.close);
    final client = await Runnel.connect(peer.endpoint).runFuture();
    addTearDown(() => client.close().runFuture());
    final script = RedisScript<int>('return 1', (reply) => (reply as RespInteger).value);

    await expectLater(
      client.runScript(
        script,
        keys: const [],
        arguments: const [],
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<RedisTimeoutException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(peer.commands.where((command) => command.name == 'EVAL'), isEmpty);
  });

  test('EVAL fallback uses the remaining original deadline', () async {
    final peer = await _ScriptPeer.start(
      evalshaDelay: const Duration(milliseconds: 40),
      evalDelay: const Duration(milliseconds: 40),
    );
    addTearDown(peer.close);
    final client = await Runnel.connect(peer.endpoint).runFuture();
    addTearDown(() => client.close().runFuture());
    final script = RedisScript<int>('return 1', (reply) => (reply as RespInteger).value);

    await expectLater(
      client.runScript(
        script,
        keys: const [],
        arguments: const [],
        timeout: const Duration(milliseconds: 65),
      ),
      throwsA(isA<RedisTimeoutException>()),
    );
    expect(peer.commands.where((command) => command.name == 'EVALSHA'), hasLength(1));
    expect(peer.commands.where((command) => command.name == 'EVAL'), hasLength(1));
  });

  test('script command builders can retain a cold-cache batch position', () async {
    final script = RedisScript<int>('return 1', (reply) => (reply as RespInteger).value);
    final seen = <String>[];
    final batch = RedisBatch.internal(
      maxCommands: 3,
      maxBytes: 4096,
      reservedCommands: 0,
      reservedBytes: 0,
      defaultTimeout: const Duration(seconds: 1),
      executor: (commands, timeout) async {
        seen.addAll(commands.map((command) => _texts(command).first));
        return const [
          BatchSuccess<Object?>('before'),
          BatchSuccess<Object?>(1),
          BatchSuccess<Object?>('after'),
        ];
      },
    );
    await (batch
          ..add(RedisCommand<String>([RedisArgument.text('GET')], (_) => const Success('before')))
          ..add(evalCommand(script, keys: const [], arguments: const []))
          ..add(RedisCommand<String>([RedisArgument.text('GET')], (_) => const Success('after'))))
        .exec();

    expect(seen, ['GET', 'EVAL', 'GET']);
  });
}

List<List<int>> _arguments(RedisCommand<Object?> command) =>
    command.arguments.map((argument) => argument.bytes.toList()).toList(growable: false);

List<String> _texts(RedisCommand<Object?> command) =>
    command.arguments.map((argument) => utf8.decode(argument.bytes)).toList(growable: false);

final class _ScriptPeer {
  _ScriptPeer({
    required this.evalshaError,
    required this.dropEvalsha,
    required this.evalshaDelay,
    required this.evalDelay,
  });

  late final RespPeer _peer;
  final String? evalshaError;
  final bool dropEvalsha;
  final Duration evalshaDelay;
  final Duration evalDelay;
  bool _loaded = false;

  String get endpoint => _peer.endpoint;
  List<RespPeerCommand> get commands => _peer.commands;

  static Future<_ScriptPeer> start({
    String? evalshaError,
    bool dropEvalsha = false,
    Duration evalshaDelay = Duration.zero,
    Duration evalDelay = Duration.zero,
  }) async {
    final peer = _ScriptPeer(
      evalshaError: evalshaError,
      dropEvalsha: dropEvalsha,
      evalshaDelay: evalshaDelay,
      evalDelay: evalDelay,
    );
    peer._peer = await RespPeer.start(
      onCommand: (command) {
        if (!command.replyToHandshake()) unawaited(peer._reply(command.socket, command));
      },
    );
    return peer;
  }

  Future<void> _reply(Socket socket, RespPeerCommand command) async {
    switch (command.name) {
      case 'EVALSHA' when dropEvalsha:
        socket.destroy();
      case 'EVALSHA':
        await Future<void>.delayed(evalshaDelay);
        if (evalshaError case final error?) {
          socket.add(ascii.encode(error));
        } else if (!_loaded) {
          socket.add(ascii.encode('-NOSCRIPT No matching script. Please use EVAL.\r\n'));
        } else {
          _replyWithArgument(socket, command);
        }
      case 'EVAL':
        await Future<void>.delayed(evalDelay);
        _loaded = true;
        _replyWithArgument(socket, command);
      default:
        socket.add(ascii.encode('-ERR unsupported\r\n'));
    }
  }

  void _replyWithArgument(Socket socket, RespPeerCommand command) {
    final keyCount = int.parse(ascii.decode(command.arguments[2]));
    final firstArgument = 3 + keyCount;
    if (firstArgument < command.arguments.length) {
      final value = command.arguments[firstArgument];
      socket
        ..add(
          ascii.encode(
            r'$'
            '${value.length}\r\n',
          ),
        )
        ..add(value)
        ..add(const [13, 10]);
    } else {
      socket.add(ascii.encode(':1\r\n'));
    }
  }

  Future<void> close() => _peer.close();
}

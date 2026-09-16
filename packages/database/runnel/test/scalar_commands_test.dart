import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Scalar command builders', () {
    test('should encode every scalar and key command form', () {
      expect(_texts(getCommand('exact:key')), ['GET', 'exact:key']);
      expect(_texts(getBytesCommand('blob')), ['GET', 'blob']);
      expect(_texts(mgetCommand(['a', 'a', 'b'])), ['MGET', 'a', 'a', 'b']);
      expect(_texts(msetCommand({'a': '1', 'b': '2'})), ['MSET', 'a', '1', 'b', '2']);
      expect(_texts(incrCommand('count')), ['INCR', 'count']);
      expect(_texts(incrbyCommand('count', -3)), ['INCRBY', 'count', '-3']);
      expect(_texts(decrCommand('count')), ['DECR', 'count']);
      expect(_texts(decrbyCommand('count', 4)), ['DECRBY', 'count', '4']);
      expect(_texts(delCommand(['a', 'a'])), ['DEL', 'a', 'a']);
      expect(_texts(unlinkCommand(['a', 'b'])), ['UNLINK', 'a', 'b']);
      expect(_texts(existsCommand(['a', 'a'])), ['EXISTS', 'a', 'a']);
      expect(_texts(persistCommand('a')), ['PERSIST', 'a']);
      expect(_texts(expireCommand('a', Duration.zero)), ['PEXPIRE', 'a', '0']);
      expect(_texts(expireCommand('a', const Duration(milliseconds: -2))), [
        'PEXPIRE',
        'a',
        '-2',
      ]);
      expect(_texts(pttlCommand('a')), ['PTTL', 'a']);
      expect(_texts(typeCommand('a')), ['TYPE', 'a']);
      expect(_texts(scanCommand('7', match: 'user:*', count: 20)), [
        'SCAN',
        '7',
        'MATCH',
        'user:*',
        'COUNT',
        '20',
      ]);
    });

    test('should encode SET conditions and expiration variants', () {
      expect(_texts(setCommand('key', 'value')), ['SET', 'key', 'value']);
      expect(
        _texts(setCommand('key', 'value', condition: SetCondition.ifAbsent)),
        ['SET', 'key', 'value', 'NX'],
      );
      expect(
        _texts(setCommand('key', 'value', condition: SetCondition.ifPresent)),
        ['SET', 'key', 'value', 'XX'],
      );
      expect(
        _texts(
          setCommand(
            'key',
            'value',
            expiry: Expiry.after(const Duration(milliseconds: 1500)),
          ),
        ),
        ['SET', 'key', 'value', 'PX', '1500'],
      );
      expect(
        _texts(
          setCommand(
            'key',
            'value',
            expiry: Expiry.at(DateTime.fromMillisecondsSinceEpoch(1700000000123, isUtc: true)),
          ),
        ),
        ['SET', 'key', 'value', 'PXAT', '1700000000123'],
      );
      expect(
        _texts(setCommand('key', 'value', expiry: const Expiry.keep())),
        ['SET', 'key', 'value', 'KEEPTTL'],
      );
      expect(
        _texts(
          setCommand(
            'key',
            'value',
            condition: SetCondition.ifAbsent,
            expiry: Expiry.after(const Duration(seconds: 1)),
          ),
        ),
        ['SET', 'key', 'value', 'PX', '1000', 'NX'],
      );
    });

    test('should snapshot mutable inputs and preserve duplicates', () {
      final keys = ['first', 'first'];
      final command = mgetCommand(keys);
      keys
        ..clear()
        ..add('changed');
      expect(_texts(command), ['MGET', 'first', 'first']);

      final values = {'first': '1', 'second': '2'};
      final mset = msetCommand(values);
      values['first'] = 'changed';
      expect(_texts(mset), ['MSET', 'first', '1', 'second', '2']);

      final bytes = Uint8List.fromList([0, 255]);
      final binary = setBytesCommand('blob', bytes);
      bytes[1] = 1;
      expect(binary.arguments[2].bytes, [0, 255]);
    });

    test('should reject empty variadic inputs and invalid numeric hints', () {
      expect(() => mgetCommand(const []), throwsArgumentError);
      expect(() => msetCommand(const {}), throwsArgumentError);
      expect(() => delCommand(const []), throwsArgumentError);
      expect(() => unlinkCommand(const []), throwsArgumentError);
      expect(() => existsCommand(const []), throwsArgumentError);
      expect(() => scanCommand('0', count: 0), throwsArgumentError);
      expect(() => scanCommand('0', count: -1), throwsArgumentError);
    });

    test('should reject fractional or invalid expiration precision', () {
      expect(
        () => Expiry.after(const Duration(microseconds: 1500)),
        throwsArgumentError,
      );
      expect(() => Expiry.after(Duration.zero), throwsArgumentError);
      expect(
        () => Expiry.at(DateTime.fromMicrosecondsSinceEpoch(1500, isUtc: true)),
        throwsArgumentError,
      );
      expect(
        () => Expiry.at(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
        throwsArgumentError,
      );
      expect(
        () => expireCommand('key', const Duration(microseconds: -1500)),
        throwsArgumentError,
      );
    });

    test('should decode nullable, integer, predicate, and status replies strictly', () {
      expect(
        getCommand('key')
            .decode(RespBlobString(utf8.encode('value')))
            .getOrThrowWith((error) => error),
        isA<Some<String>>().having((value) => value.value, 'value', 'value'),
      );
      expect(
        getCommand('key').decode(const RespNull()).getOrThrowWith((error) => error),
        isA<None>(),
      );
      expect(
        getBytesCommand('key').decode(RespBlobString([0, 255])).getOrThrowWith((error) => error),
        isA<Some<Uint8List>>().having((value) => value.value, 'value', [0, 255]),
      );
      expect(incrCommand('key').decode(const RespInteger(3)).getOrThrowWith((error) => error), 3);
      expect(pttlCommand('key').decode(const RespInteger(-2)).getOrThrowWith((error) => error), -2);
      expect(
        persistCommand('key').decode(const RespInteger(1)).getOrThrowWith((error) => error),
        isTrue,
      );
      expect(
        persistCommand('key').decode(const RespInteger(0)).getOrThrowWith((error) => error),
        isFalse,
      );
      expect(
        typeCommand('key').decode(const RespSimpleString('none')).getOrThrowWith((error) => error),
        'none',
      );
      expect(
        () =>
            msetCommand({'a': 'b'})
                .decode(const RespSimpleString('OK'))
                .getOrThrowWith((error) => error),
        returnsNormally,
      );

      expect(
        () => getCommand('key').decode(RespBlobString([0xFF])).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () =>
            incrCommand('key').decode(const RespSimpleString('3')).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () => persistCommand('key').decode(const RespInteger(2)).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () =>
            msetCommand({'a': 'b'})
                .decode(const RespSimpleString('NO'))
                .getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
    });

    test('should distinguish a conditional SET miss from an invalid reply', () {
      final command = setCommand('key', 'value', condition: SetCondition.ifAbsent);

      expect(command.decode(const RespNull()).getOrThrowWith((error) => error), isFalse);
      expect(command.decode(const RespSimpleString('OK')).getOrThrowWith((error) => error), isTrue);
      expect(
        () => command.decode(const RespSimpleString('NO')).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
    });

    test('should preserve ordered missing MGET values in an unmodifiable list', () {
      final values = mgetCommand(['a', 'missing', 'a'])
          .decode(
            RespArray([
              RespBlobString(utf8.encode('one')),
              const RespNull(),
              RespBlobString(utf8.encode('two')),
            ]),
          )
          .getOrThrowWith((error) => error);

      expect(values, [
        isA<Some<String>>().having((value) => value.value, 'value', 'one'),
        isA<None>(),
        isA<Some<String>>().having((value) => value.value, 'value', 'two'),
      ]);
      expect(() => values.add(const Some('changed')), throwsUnsupportedError);
    });

    test('should decode SCAN cursor and keys without removing duplicates', () {
      final page = scanCommand('0')
          .decode(
            RespArray([
              RespBlobString(ascii.encode('7')),
              RespArray([
                RespBlobString(utf8.encode('a')),
                RespBlobString(utf8.encode('a')),
              ]),
            ]),
          )
          .getOrThrowWith((error) => error);

      expect(page.cursor, '7');
      expect(page.keys, ['a', 'a']);
      expect(() => page.keys.add('changed'), throwsUnsupportedError);
    });
  });

  group('RunnelScalarCommands', () {
    test('should keep conditional SET misses distinct from server rejection', () async {
      final peer = await _ScalarPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      expect(
        await client
            .execute(
              setCommand('conditional-miss', 'value', condition: SetCondition.ifAbsent),
            )
            .runFuture(),
        isFalse,
      );
      await expectLater(
        client.execute(setCommand('server-error', 'value')).runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'expected error',
            isA<RunnelServerError>()
                .having((error) => error.code, 'code', 'ERR')
                .having((error) => error.message, 'message', 'write rejected'),
          ),
        ),
      );
      expect(
        await client
            .execute(
              setCommand(
                'accepted',
                'value',
                expiry: Expiry.after(const Duration(seconds: 1)),
              ),
            )
            .runFuture(),
        isTrue,
      );
      expect(peer.commands.last, ['SET', 'accepted', 'value', 'PX', '1000']);
    });

    test('should execute typed conveniences through the connection', () async {
      final peer = await _ScalarPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      expect(await client.mget(['a', 'missing', 'a']).runFuture(), [
        isA<Some<String>>().having((value) => value.value, 'value', 'one'),
        isA<None>(),
        isA<Some<String>>().having((value) => value.value, 'value', 'two'),
      ]);
      await client.mset({'a': 'one', 'b': 'two'}).runFuture();
      expect(await client.incr('counter').runFuture(), 2);
      expect(await client.incrby('counter', 4).runFuture(), 6);
      expect(await client.decr('counter').runFuture(), 5);
      expect(await client.decrby('counter', 3).runFuture(), 2);
      expect(await client.del(['a', 'a']).runFuture(), 1);
      expect(await client.unlink(['b']).runFuture(), 1);
      expect(await client.exists(['a', 'a']).runFuture(), 2);
      expect(await client.persist('a').runFuture(), isTrue);
      expect(await client.expire('a', Duration.zero).runFuture(), isTrue);
      expect(await client.pttl('a').runFuture(), -2);
      expect(await client.type('a').runFuture(), 'none');
    });

    test('should request SCAN pages lazily and preserve duplicates', () async {
      final peer = await _ScalarPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final stream = client.scan(match: 'item:*', count: 2);
      expect(peer.commandCount('SCAN'), 0);
      expect(await stream.toList(), ['a', 'b', 'b', 'c']);
      expect(peer.commandCount('SCAN'), 2);
      expect(peer.commands.where((parts) => parts.first == 'SCAN'), [
        ['SCAN', '0', 'MATCH', 'item:*', 'COUNT', '2'],
        ['SCAN', '7', 'MATCH', 'item:*', 'COUNT', '2'],
      ]);
    });

    test('should stop requesting SCAN pages after cancellation', () async {
      final peer = await _ScalarPeer.start();
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final firstKey = Completer<void>();
      late final StreamSubscription<String> subscription;

      subscription = client.scan().listen((_) {
        if (!firstKey.isCompleted) {
          firstKey.complete();
          unawaited(subscription.cancel());
        }
      });
      await firstKey.future;
      await Future<void>.delayed(Duration.zero);

      expect(peer.commandCount('SCAN'), 1);
    });
  });
}

List<String> _texts(RedisCommand<Object?> command) => command.arguments
    .map((argument) => utf8.decode(argument.bytes, allowMalformed: true))
    .toList(growable: false);

final class _ScalarPeer {
  late final RespPeer _peer;

  String get endpoint => _peer.endpoint;
  List<List<String>> get commands =>
      _peer.commands.map((command) => command.textArguments).toList();

  static Future<_ScalarPeer> start() async {
    final peer = _ScalarPeer();
    peer._peer = await RespPeer.start(
      onCommand: (command) {
        if (!command.replyToHandshake()) command.reply(peer._reply(command.textArguments));
      },
    );
    return peer;
  }

  int commandCount(String name) => _peer.commands.where((command) => command.name == name).length;

  String _reply(List<String> parts) => switch (parts.first) {
    'MGET' => r'*3\r\n$3\r\none\r\n_\r\n$3\r\ntwo\r\n'.replaceAll(r'\r\n', '\r\n'),
    'MSET' => '+OK\r\n',
    'SET' when parts[1] == 'conditional-miss' => '_\r\n',
    'SET' when parts[1] == 'server-error' => '-ERR write rejected\r\n',
    'SET' => '+OK\r\n',
    'INCR' => ':2\r\n',
    'INCRBY' => ':6\r\n',
    'DECR' => ':5\r\n',
    'DECRBY' => ':2\r\n',
    'DEL' => ':1\r\n',
    'UNLINK' => ':1\r\n',
    'EXISTS' => ':2\r\n',
    'PERSIST' => ':1\r\n',
    'PEXPIRE' => ':1\r\n',
    'PTTL' => ':-2\r\n',
    'TYPE' => '+none\r\n',
    'SCAN' when parts[1] == '0' => r'*2\r\n$1\r\n7\r\n*2\r\n$1\r\na\r\n$1\r\nb\r\n'.replaceAll(
      r'\r\n',
      '\r\n',
    ),
    'SCAN' => r'*2\r\n$1\r\n0\r\n*2\r\n$1\r\nb\r\n$1\r\nc\r\n'.replaceAll(r'\r\n', '\r\n'),
    _ => '-ERR unsupported\r\n',
  };

  Future<void> close() => _peer.close();
}

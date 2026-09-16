import 'dart:convert';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('Runnel command Effects', () {
    test('should defer validation until execution without transmitting invalid input', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (!command.replyToHandshake()) command.reply(':1\r\n');
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());

      final invalid = <Effect<Object?, RunnelError>>[
        client.mget(const []),
        client.mset(const {}),
        client.del(const []),
        client.unlink(const []),
        client.exists(const []),
        client.expire('key', const Duration(microseconds: 1)),
      ];
      for (final operation in invalid) {
        final exit = await operation.runFutureExit();
        expect(
          exit,
          isA<Failed<Object?, RunnelError>>().having(
            (exit) => exit.cause.expectedErrors.single,
            'error',
            isA<RunnelInputError>(),
          ),
        );
      }
      expect(peer.commands.map((command) => command.name), ['HELLO']);
    });
    test('should snapshot bytes, lists, maps, and Stream inputs across repeated runs', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          command.reply(switch (command.name) {
            'SET' || 'MSET' => '+OK\r\n',
            'XADD' => '+1-0\r\n',
            'XREAD' => '_\r\n',
            _ => ':1\r\n',
          });
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final bytes = Uint8List.fromList([65]);
      final keys = ['first', 'first'];
      final values = {'first': 'one'};
      final members = {'first': 1.0};
      final fields = [StreamField.text('field', 'value')];
      final cursors = {'history': StreamId(BigInt.zero, BigInt.zero)};
      final operations = <Effect<Object?, RunnelError>>[
        client.setBytes('blob', bytes),
        client.del(keys),
        client.mset(values),
        client.hset('hash', values),
        client.zadd('sorted', members),
        client.xadd('history', fields),
        client.xread(cursors),
      ];
      bytes[0] = 66;
      keys.clear();
      values.clear();
      members.clear();
      fields.clear();
      cursors.clear();
      expect(peer.commands.map((command) => command.name), ['HELLO']);
      for (var run = 0; run < 2; run++) {
        for (final operation in operations) {
          await operation.runFuture();
        }
      }
      final commands = peer.commands.skip(1).map((command) => command.textArguments).toList();
      final expected = [
        ['SET', 'blob', 'A'],
        ['DEL', 'first', 'first'],
        ['MSET', 'first', 'one'],
        ['HSET', 'hash', 'first', 'one'],
        ['ZADD', 'sorted', '1.0', 'first'],
        ['XADD', 'history', '*', 'field', 'value'],
        ['XREAD', 'STREAMS', 'history', '0-0'],
      ];
      expect(commands, [...expected, ...expected]);
    });

    test('should preserve absent, empty, and caller-decoded nullable values', () async {
      final peer = await RespPeer.start(
        onCommand: (command) {
          if (command.replyToHandshake()) return;
          final key = command.textArguments[1];
          command.reply(switch (command.name) {
            'MGET' || 'HMGET' => '*3\r\n+same\r\n_\r\n+same\r\n',
            'ZSCORE' when key == 'present' => ',0\r\n',
            'ZSCORE' => '_\r\n',
            _ when key == 'missing' => '_\r\n',
            _ when key == 'json' => '\$4\r\nnull\r\n',
            _ => '\$0\r\n\r\n',
          });
        },
      );
      addTearDown(peer.close);
      final client = await Runnel.connect(peer.endpoint).runFuture();
      addTearDown(() => client.close().runFuture());
      final presentNull = (await client.get('json').runFuture()).map<Object?>(jsonDecode);
      final absent = (await client.get('missing').runFuture()).map<Object?>(jsonDecode);
      expect(presentNull, isA<Some<Object?>>().having((value) => value.value, 'value', isNull));
      expect(absent, isA<None>());
      for (final operation in [
        client.get('present'),
        client.hget('present', 'field'),
        client.lpop('present'),
        client.rpop('present'),
      ]) {
        expect(
          await operation.runFuture(),
          isA<Some<String>>().having((value) => value.value, 'value', ''),
        );
      }
      for (final operation in [
        client.get('missing'),
        client.hget('missing', 'field'),
        client.lpop('missing'),
        client.rpop('missing'),
      ]) {
        expect(await operation.runFuture(), isA<None>());
      }
      expect(
        await client.getBytes('present').runFuture(),
        isA<Some<Uint8List>>().having((value) => value.value, 'value', isEmpty),
      );
      expect(await client.getBytes('missing').runFuture(), isA<None>());
      expect(
        await client.zscore('present', 'member').runFuture(),
        isA<Some<double>>().having((value) => value.value, 'value', 0),
      );
      expect(await client.zscore('missing', 'member').runFuture(), isA<None>());
      for (final operation in [
        client.mget(['a', 'missing', 'a']),
        client.hmget('hash', ['a', 'missing', 'a']),
      ]) {
        final values = await operation.runFuture();
        expect(values, [
          isA<Some<String>>().having((value) => value.value, 'value', 'same'),
          isA<None>(),
          isA<Some<String>>().having((value) => value.value, 'value', 'same'),
        ]);
      }
    });
  });
}

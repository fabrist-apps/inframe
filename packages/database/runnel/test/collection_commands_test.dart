import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/runnel.dart';
import 'package:runnel/src/commands/collections.dart';
import 'package:test/test.dart';

void main() {
  group('RunnelCollectionCommands', () {
    late _CommandPeer peer;
    late Runnel client;

    setUp(() async {
      peer = await _CommandPeer.start();
      client = await Runnel.connect(peer.endpoint);
    });

    tearDown(() async {
      await client.close();
      await peer.close();
    });

    test('should encode and decode hash commands', () async {
      peer.queueReplies([
        ':2\r\n',
        '\$9\r\nBhaswanth\r\n',
        '*3\r\n+one\r\n_\r\n+three\r\n',
        '%2\r\n+name\r\n+Bhaswanth\r\n+plan\r\n+pro\r\n',
        ':1\r\n',
        ':0\r\n',
        ':2\r\n',
        ':3\r\n',
      ]);

      expect(await client.hset('user:42', {'name': 'Bhaswanth', 'plan': 'pro'}), 2);
      expect(await client.hget('user:42', 'name'), 'Bhaswanth');
      final values = await client.hmget('user:42', ['first', 'missing', 'third']);
      expect(values, ['one', null, 'three']);
      expect(() => values.add('four'), throwsUnsupportedError);
      final fields = await client.hgetall('user:42');
      expect(fields, {'name': 'Bhaswanth', 'plan': 'pro'});
      expect(() => fields['role'] = 'admin', throwsUnsupportedError);
      expect(await client.hdel('user:42', ['old', 'stale']), 1);
      expect(await client.hexists('user:42', 'missing'), isFalse);
      expect(await client.hlen('user:42'), 2);
      expect(await client.hincrby('user:42', 'visits', 3), 3);

      expect(peer.commands, [
        ['HSET', 'user:42', 'name', 'Bhaswanth', 'plan', 'pro'],
        ['HGET', 'user:42', 'name'],
        ['HMGET', 'user:42', 'first', 'missing', 'third'],
        ['HGETALL', 'user:42'],
        ['HDEL', 'user:42', 'old', 'stale'],
        ['HEXISTS', 'user:42', 'missing'],
        ['HLEN', 'user:42'],
        ['HINCRBY', 'user:42', 'visits', '3'],
      ]);
    });

    test('should encode and decode set commands', () async {
      peer.queueReplies([
        ':2\r\n',
        ':1\r\n',
        ':1\r\n',
        '~2\r\n+alpha\r\n+beta\r\n',
        ':2\r\n',
      ]);

      expect(await client.sadd('tags', ['alpha', 'alpha', 'beta']), 2);
      expect(await client.srem('tags', ['old', 'stale']), 1);
      expect(await client.sismember('tags', 'alpha'), isTrue);
      final members = await client.smembers('tags');
      expect(members, {'alpha', 'beta'});
      expect(() => members.add('gamma'), throwsUnsupportedError);
      expect(await client.scard('tags'), 2);

      expect(peer.commands, [
        ['SADD', 'tags', 'alpha', 'alpha', 'beta'],
        ['SREM', 'tags', 'old', 'stale'],
        ['SISMEMBER', 'tags', 'alpha'],
        ['SMEMBERS', 'tags'],
        ['SCARD', 'tags'],
      ]);
    });

    test('should encode and decode list commands', () async {
      peer.queueReplies([
        ':2\r\n',
        ':4\r\n',
        '+first\r\n',
        '_\r\n',
        '*3\r\n+first\r\n+second\r\n+second\r\n',
        ':3\r\n',
        '+OK\r\n',
      ]);

      expect(await client.lpush('jobs', ['second', 'first']), 2);
      expect(await client.rpush('jobs', ['second', 'second']), 4);
      expect(await client.lpop('jobs'), 'first');
      expect(await client.rpop('missing'), isNull);
      final range = await client.lrange('jobs', 0, -1);
      expect(range, ['first', 'second', 'second']);
      expect(() => range.add('third'), throwsUnsupportedError);
      expect(await client.llen('jobs'), 3);
      await client.ltrim('jobs', 0, -2);

      expect(peer.commands, [
        ['LPUSH', 'jobs', 'second', 'first'],
        ['RPUSH', 'jobs', 'second', 'second'],
        ['LPOP', 'jobs'],
        ['RPOP', 'missing'],
        ['LRANGE', 'jobs', '0', '-1'],
        ['LLEN', 'jobs'],
        ['LTRIM', 'jobs', '0', '-2'],
      ]);
    });

    test('should encode and decode sorted-set commands', () async {
      peer.queueReplies([
        ':2\r\n',
        ':1\r\n',
        ':2\r\n',
        '\$4\r\n1.25\r\n',
        '\$3\r\n2.5\r\n',
        '*2\r\n+first\r\n+second\r\n',
        '*2\r\n*2\r\n+first\r\n,1.25\r\n*2\r\n+second\r\n,2.5\r\n',
        '*2\r\n+first\r\n+second\r\n',
        ':1\r\n',
      ]);

      expect(await client.zadd('leases', {'first': 1.25, 'second': 2.5}), 2);
      expect(await client.zrem('leases', ['expired', 'missing']), 1);
      expect(await client.zcard('leases'), 2);
      expect(await client.zscore('leases', 'first'), 1.25);
      expect(await client.zincrby('leases', 1.25, 'first'), 2.5);
      final members = await client.zrange('leases', -2, -1);
      expect(members, ['first', 'second']);
      expect(() => members.add('third'), throwsUnsupportedError);
      final scored = await client.zrangeWithScores('leases', 0, -1);
      expect(scored, [(member: 'first', score: 1.25), (member: 'second', score: 2.5)]);
      expect(() => scored.add((member: 'third', score: 3)), throwsUnsupportedError);
      final bounded = await client.zrangebyscore('leases', 1.25, 2.5);
      expect(bounded, ['first', 'second']);
      expect(await client.zremrangebyscore('leases', 1.25, 2.5), 1);

      expect(peer.commands, [
        ['ZADD', 'leases', '1.25', 'first', '2.5', 'second'],
        ['ZREM', 'leases', 'expired', 'missing'],
        ['ZCARD', 'leases'],
        ['ZSCORE', 'leases', 'first'],
        ['ZINCRBY', 'leases', '1.25', 'first'],
        ['ZRANGE', 'leases', '-2', '-1'],
        ['ZRANGE', 'leases', '0', '-1', 'WITHSCORES'],
        ['ZRANGEBYSCORE', 'leases', '1.25', '2.5'],
        ['ZREMRANGEBYSCORE', 'leases', '1.25', '2.5'],
      ]);
    });

    test('should decode RESP2 aggregates and missing scalar values', () {
      final hash = hgetallCommand('hash').decode(
        RespArray([
          const RespSimpleString('name'),
          const RespSimpleString('Bhaswanth'),
          const RespSimpleString('plan'),
          const RespSimpleString('pro'),
        ]),
      );
      final set = smembersCommand('set').decode(
        RespArray([
          const RespSimpleString('alpha'),
          const RespSimpleString('beta'),
        ]),
      );
      final scored = zrangeWithScoresCommand('sorted', 0, -1).decode(
        RespArray([
          const RespSimpleString('first'),
          const RespSimpleString('1.25'),
          const RespSimpleString('second'),
          const RespSimpleString('2.5'),
        ]),
      );

      expect(hash, {'name': 'Bhaswanth', 'plan': 'pro'});
      expect(set, {'alpha', 'beta'});
      expect(scored, [(member: 'first', score: 1.25), (member: 'second', score: 2.5)]);
      expect(hgetCommand('hash', 'missing').decode(const RespNull()), isNull);
      expect(zscoreCommand('sorted', 'missing').decode(const RespNull()), isNull);
      expect(() => hash['name'] = 'changed', throwsUnsupportedError);
      expect(() => set.add('changed'), throwsUnsupportedError);
      expect(scored.clear, throwsUnsupportedError);
    });

    test('should reject malformed collection replies', () {
      expect(
        () => hexistsCommand('hash', 'field').decode(const RespInteger(2)),
        throwsFormatException,
      );
      expect(
        () => ltrimCommand('list', 0, -1).decode(const RespSimpleString('NO')),
        throwsFormatException,
      );
      expect(
        () => zrangeWithScoresCommand(
          'sorted',
          0,
          -1,
        ).decode(RespArray([const RespSimpleString('member')])),
        throwsFormatException,
      );
    });

    test('should validate collection inputs before transmission', () async {
      expect(() => client.hset('hash', {}), throwsArgumentError);
      expect(() => client.hmget('hash', []), throwsArgumentError);
      expect(() => client.hdel('hash', []), throwsArgumentError);
      expect(() => client.sadd('set', []), throwsArgumentError);
      expect(() => client.srem('set', []), throwsArgumentError);
      expect(() => client.lpush('list', []), throwsArgumentError);
      expect(() => client.rpush('list', []), throwsArgumentError);
      expect(() => client.zadd('sorted', {}), throwsArgumentError);
      expect(
        () => client.zadd('sorted', {'member': double.nan}),
        throwsArgumentError,
      );
      expect(
        () => client.zadd('sorted', {'member': double.infinity}),
        throwsArgumentError,
      );
      expect(() => client.zrem('sorted', []), throwsArgumentError);
      expect(
        () => client.zincrby('sorted', double.negativeInfinity, 'member'),
        throwsArgumentError,
      );
      expect(
        () => client.zrangebyscore('sorted', double.nan, 1),
        throwsArgumentError,
      );
      expect(
        () => client.zremrangebyscore('sorted', 0, double.infinity),
        throwsArgumentError,
      );

      await Future<void>.delayed(Duration.zero);
      expect(peer.commands, isEmpty);
    });

    test('should snapshot mutable inputs before queued transmission', () async {
      final fields = <String, String>{'name': 'before'};
      final members = <String>['first', 'second'];
      final scores = <String, double>{'first': 1};
      peer.queueReplies([':1\r\n', ':2\r\n', ':1\r\n']);

      final hashWrite = client.hset('hash', fields);
      final listWrite = client.rpush('list', members);
      final sortedWrite = client.zadd('sorted', scores);
      fields['name'] = 'after';
      members
        ..clear()
        ..add('changed');
      scores['first'] = 99;

      expect(await hashWrite, 1);
      expect(await listWrite, 2);
      expect(await sortedWrite, 1);
      expect(peer.commands, [
        ['HSET', 'hash', 'name', 'before'],
        ['RPUSH', 'list', 'first', 'second'],
        ['ZADD', 'sorted', '1.0', 'first'],
      ]);
    });

    test('should pass the optional command deadline to execute', () async {
      expect(
        () => client.hlen('hash', timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(peer.commands, isEmpty);
    });
  });
}

final class _CommandPeer {
  _CommandPeer._(this._server);

  final ServerSocket _server;
  final List<List<String>> commands = [];
  final List<String> _replies = [];
  Socket? _socket;

  String get endpoint => 'redis://127.0.0.1:${_server.port}';

  static Future<_CommandPeer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = _CommandPeer._(server);
    server.listen(peer._accept);
    return peer;
  }

  void queueReplies(Iterable<String> replies) => _replies.addAll(replies);

  void _accept(Socket socket) {
    _socket = socket;
    var buffer = <int>[];
    socket.listen((bytes) {
      buffer.addAll(bytes);
      while (true) {
        final parsed = _parseCommand(buffer);
        if (parsed == null) return;
        buffer = buffer.sublist(parsed.consumed);
        final command = parsed.arguments
            .map((argument) => utf8.decode(argument))
            .toList(growable: false);
        if (command.first == 'HELLO') {
          socket.add(ascii.encode('%1\r\n+proto\r\n:3\r\n'));
        } else {
          commands.add(command);
          socket.add(ascii.encode(_replies.removeAt(0)));
        }
      }
    });
  }

  Future<void> close() async {
    await _socket?.close();
    await _server.close();
  }
}

({List<Uint8List> arguments, int consumed})? _parseCommand(List<int> bytes) {
  if (bytes.isEmpty || bytes.first != 42) return null;
  final headerEnd = _findCrlf(bytes, 0);
  if (headerEnd < 0) return null;
  final count = int.parse(ascii.decode(bytes.sublist(1, headerEnd)));
  var offset = headerEnd + 2;
  final arguments = <Uint8List>[];
  for (var index = 0; index < count; index++) {
    if (offset >= bytes.length || bytes[offset] != 36) return null;
    final lengthEnd = _findCrlf(bytes, offset);
    if (lengthEnd < 0) return null;
    final length = int.parse(ascii.decode(bytes.sublist(offset + 1, lengthEnd)));
    offset = lengthEnd + 2;
    if (bytes.length < offset + length + 2) return null;
    arguments.add(Uint8List.fromList(bytes.sublist(offset, offset + length)));
    offset += length + 2;
  }
  return (arguments: arguments, consumed: offset);
}

int _findCrlf(List<int> bytes, int start) {
  for (var index = start; index + 1 < bytes.length; index++) {
    if (bytes[index] == 13 && bytes[index + 1] == 10) return index;
  }
  return -1;
}

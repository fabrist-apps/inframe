import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  final throwsInputError = throwsA(
    isA<EffectException<RunnelError>>().having(
      (error) => error.cause,
      'cause',
      isA<Expected<RunnelError>>().having(
        (cause) => cause.error,
        'error',
        isA<RunnelInputError>(),
      ),
    ),
  );

  group('RunnelCollectionCommands', () {
    late _CommandPeer peer;
    late Runnel client;

    setUp(() async {
      peer = await _CommandPeer.start();
      client = await Runnel.connect(peer.endpoint).runFuture();
    });

    tearDown(() async {
      await client.close().runFuture();
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

      expect(await client.hset('user:42', {'name': 'Bhaswanth', 'plan': 'pro'}).runFuture(), 2);
      expect(
        await client.hget('user:42', 'name').runFuture(),
        isA<Some<String>>().having((value) => value.value, 'value', 'Bhaswanth'),
      );
      final values = await client.hmget('user:42', ['first', 'missing', 'third']).runFuture();
      expect(values, [
        isA<Some<String>>().having((value) => value.value, 'value', 'one'),
        isA<None>(),
        isA<Some<String>>().having((value) => value.value, 'value', 'three'),
      ]);
      expect(() => values.add(const Some('four')), throwsUnsupportedError);
      final fields = await client.hgetall('user:42').runFuture();
      expect(fields, {'name': 'Bhaswanth', 'plan': 'pro'});
      expect(() => fields['role'] = 'admin', throwsUnsupportedError);
      expect(await client.hdel('user:42', ['old', 'stale']).runFuture(), 1);
      expect(await client.hexists('user:42', 'missing').runFuture(), isFalse);
      expect(await client.hlen('user:42').runFuture(), 2);
      expect(await client.hincrby('user:42', 'visits', 3).runFuture(), 3);

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

      expect(await client.sadd('tags', ['alpha', 'alpha', 'beta']).runFuture(), 2);
      expect(await client.srem('tags', ['old', 'stale']).runFuture(), 1);
      expect(await client.sismember('tags', 'alpha').runFuture(), isTrue);
      final members = await client.smembers('tags').runFuture();
      expect(members, {'alpha', 'beta'});
      expect(() => members.add('gamma'), throwsUnsupportedError);
      expect(await client.scard('tags').runFuture(), 2);

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

      expect(await client.lpush('jobs', ['second', 'first']).runFuture(), 2);
      expect(await client.rpush('jobs', ['second', 'second']).runFuture(), 4);
      expect(
        await client.lpop('jobs').runFuture(),
        isA<Some<String>>().having((value) => value.value, 'value', 'first'),
      );
      expect(await client.rpop('missing').runFuture(), isA<None>());
      final range = await client.lrange('jobs', 0, -1).runFuture();
      expect(range, ['first', 'second', 'second']);
      expect(() => range.add('third'), throwsUnsupportedError);
      expect(await client.llen('jobs').runFuture(), 3);
      await client.ltrim('jobs', 0, -2).runFuture();

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
        ',1.25\r\n',
        ',2.5\r\n',
        '*2\r\n+first\r\n+second\r\n',
        '*2\r\n*2\r\n+first\r\n,1.25\r\n*2\r\n+second\r\n,2.5\r\n',
        '*2\r\n+first\r\n+second\r\n',
        ':1\r\n',
      ]);

      expect(await client.zadd('leases', {'first': 1.25, 'second': 2.5}).runFuture(), 2);
      expect(await client.zrem('leases', ['expired', 'missing']).runFuture(), 1);
      expect(await client.zcard('leases').runFuture(), 2);
      expect(
        await client.zscore('leases', 'first').runFuture(),
        isA<Some<double>>().having((value) => value.value, 'value', 1.25),
      );
      expect(await client.zincrby('leases', 1.25, 'first').runFuture(), 2.5);
      final members = await client.zrange('leases', -2, -1).runFuture();
      expect(members, ['first', 'second']);
      expect(() => members.add('third'), throwsUnsupportedError);
      final scored = await client.zrangeWithScores('leases', 0, -1).runFuture();
      expect(scored, [(member: 'first', score: 1.25), (member: 'second', score: 2.5)]);
      expect(() => scored.add((member: 'third', score: 3)), throwsUnsupportedError);
      final bounded = await client.zrangebyscore('leases', 1.25, 2.5).runFuture();
      expect(bounded, ['first', 'second']);
      expect(await client.zremrangebyscore('leases', 1.25, 2.5).runFuture(), 1);

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

    test('should decode missing scalar values', () {
      expect(
        hgetCommand('hash', 'missing').decode(const RespNull()).getOrThrowWith((error) => error),
        isA<None>(),
      );
      expect(
        zscoreCommand(
          'sorted',
          'missing',
        ).decode(const RespNull()).getOrThrowWith((error) => error),
        isA<None>(),
      );
    });

    test('should reject malformed collection replies', () {
      expect(
        () => hexistsCommand(
          'hash',
          'field',
        ).decode(const RespInteger(2)).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () => ltrimCommand(
          'list',
          0,
          -1,
        ).decode(const RespSimpleString('NO')).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () => zrangeWithScoresCommand(
          'sorted',
          0,
          -1,
        ).decode(RespArray([const RespSimpleString('member')])).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () =>
            hgetallCommand(
                  'hash',
                )
                .decode(
                  RespArray([const RespSimpleString('field'), const RespSimpleString('value')]),
                )
                .getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () => smembersCommand(
          'set',
        ).decode(RespArray([const RespSimpleString('member')])).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () => zscoreCommand(
          'sorted',
          'member',
        ).decode(const RespSimpleString('1.25')).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
      expect(
        () => zincrbyCommand(
          'sorted',
          1,
          'member',
        ).decode(const RespInteger(2)).getOrThrowWith((error) => error),
        throwsA(isA<RunnelDecodingError>()),
      );
    });

    test('should validate collection inputs before transmission', () async {
      await expectLater(
        client.hset('hash', {}).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.hmget('hash', []).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.hdel('hash', []).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.sadd('set', []).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.srem('set', []).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.lpush('list', []).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.rpush('list', []).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.zadd('sorted', {}).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.zadd('sorted', {'member': double.nan}).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.zadd('sorted', {'member': double.infinity}).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.zrem('sorted', []).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.zincrby('sorted', double.negativeInfinity, 'member').runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.zrangebyscore('sorted', double.nan, 1).runFuture(),
        throwsInputError,
      );
      await expectLater(
        client.zremrangebyscore('sorted', 0, double.infinity).runFuture(),
        throwsInputError,
      );

      await Future<void>.delayed(Duration.zero);
      expect(peer.commands, isEmpty);
    });

    test('should snapshot mutable inputs before queued transmission', () async {
      final fields = <String, String>{'name': 'before'};
      final members = <String>['first', 'second'];
      final scores = <String, double>{'first': 1};
      peer.queueReplies([':1\r\n', ':2\r\n', ':1\r\n']);

      final hashWrite = client.hset('hash', fields).runFuture();
      final listWrite = client.rpush('list', members).runFuture();
      final sortedWrite = client.zadd('sorted', scores).runFuture();
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
      await expectLater(
        client.hlen('hash', timeout: Duration.zero).runFuture(),
        throwsInputError,
      );
      expect(peer.commands, isEmpty);
    });
  });
}

final class _CommandPeer {
  late final RespPeer _peer;
  final List<String> _replies = [];

  String get endpoint => _peer.endpoint;
  List<List<String>> get commands => _peer.commands
      .where((command) => command.name != 'HELLO')
      .map((command) => command.textArguments)
      .toList();

  static Future<_CommandPeer> start() async {
    final peer = _CommandPeer();
    peer._peer = await RespPeer.start(
      onCommand: (command) {
        if (!command.replyToHandshake()) command.reply(peer._replies.removeAt(0));
      },
    );
    return peer;
  }

  void queueReplies(Iterable<String> replies) => _replies.addAll(replies);

  Future<void> close() => _peer.close();
}

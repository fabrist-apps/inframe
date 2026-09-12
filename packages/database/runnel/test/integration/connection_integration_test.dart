@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

import '../fixtures/herald_consumer_fixture.dart';

void main() {
  final endpoints = <String, String?>{
    'Redis TCP': Platform.environment['RUNNEL_REDIS_URL'],
    'Redis TLS': Platform.environment['RUNNEL_REDIS_TLS_URL'],
    'Valkey TCP': Platform.environment['RUNNEL_VALKEY_URL'],
    'Valkey TLS': Platform.environment['RUNNEL_VALKEY_TLS_URL'],
  };

  group('Runnel integration', () {
    for (final MapEntry(key: name, value: endpoint) in endpoints.entries) {
      group('RESP3', () {
        test(
          'should round-trip text and binary through $name',
          () async {
            if (endpoint == null) {
              markTestSkipped('Set the Runnel integration endpoint environment variables.');
              return;
            }
            final securityContext = endpoint.startsWith('rediss://')
                ? (SecurityContext()..setTrustedCertificates(
                    Platform.environment['RUNNEL_TLS_CA'] ??
                        (throw StateError('RUNNEL_TLS_CA is required for TLS tests.')),
                  ))
                : null;
            final client = await Runnel.connect(
              endpoint,
              securityContext: securityContext,
            );
            addTearDown(client.close);
            final suffix = '${DateTime.now().microsecondsSinceEpoch}-resp3';
            final textKey = 'runnel:integration:text:$suffix';
            final bytesKey = 'runnel:integration:bytes:$suffix';

            expect(await client.ping(), isTrue);
            expect(await client.set(textKey, 'café'), isTrue);
            expect(await client.get(textKey), 'café');
            expect(await client.setBytes(bytesKey, Uint8List.fromList([0, 255, 13, 10])), isTrue);
            expect(await client.getBytes(bytesKey), [0, 255, 13, 10]);

            final conditionalKey = 'runnel:integration:conditional:$suffix';
            expect(
              await client.set(
                conditionalKey,
                'first',
                condition: SetCondition.ifAbsent,
                expiry: Expiry.after(const Duration(seconds: 5)),
              ),
              isTrue,
            );
            expect(
              await client.set(
                conditionalKey,
                'ignored',
                condition: SetCondition.ifAbsent,
              ),
              isFalse,
            );
            expect(
              await client.set(
                conditionalKey,
                'second',
                condition: SetCondition.ifPresent,
                expiry: const Expiry.keep(),
              ),
              isTrue,
            );
            expect(await client.pttl(conditionalKey), inInclusiveRange(1, 5000));
            expect(await client.set(conditionalKey, 'without-expiry'), isTrue);
            expect(await client.pttl(conditionalKey), -1);
            expect(
              await client.set(
                conditionalKey,
                'absolute-expiry',
                expiry: Expiry.at(
                  DateTime.fromMillisecondsSinceEpoch(
                    DateTime.now().millisecondsSinceEpoch + 10000,
                    isUtc: true,
                  ),
                ),
              ),
              isTrue,
            );
            expect(await client.pttl(conditionalKey), inInclusiveRange(1, 10000));
            expect(await client.persist(conditionalKey), isTrue);
            expect(await client.pttl(conditionalKey), -1);

            final first = 'runnel:integration:scalar:$suffix:first';
            final second = 'runnel:integration:scalar:$suffix:second';
            await client.mset({first: 'one', second: 'two'});
            expect(await client.mget([first, 'missing:$suffix', first]), ['one', null, 'one']);
            expect(await client.exists([first, first, second]), 3);
            expect(await client.type(first), 'string');
            expect(await client.expire(second, Duration.zero), isTrue);
            expect(await client.pttl(second), -2);
            final counter = 'runnel:integration:counter:$suffix';
            expect(await client.incr(counter), 1);
            expect(await client.incrby(counter, 4), 5);
            expect(await client.decr(counter), 4);
            expect(await client.decrby(counter, 2), 2);

            final scanned = await client
                .scan(
                  match: 'runnel:integration:scalar:$suffix:*',
                  count: 1,
                )
                .toSet();
            expect(scanned, contains(first));
            expect(await client.del([first]), 1);
            expect(await client.unlink([conditionalKey]), 1);

            expect(
              await client.execute(
                RedisCommand<String>(
                  [RedisArgument.text('ECHO'), RedisArgument.text('custom')],
                  respText,
                ),
              ),
              'custom',
            );

            final hash = 'runnel:integration:hash:$suffix';
            expect(await client.hset(hash, {'name': 'Ada', 'visits': '2'}), 2);
            expect(await client.hget(hash, 'name'), 'Ada');
            expect(await client.hmget(hash, ['name', 'missing']), ['Ada', null]);
            expect(await client.hgetall(hash), {'name': 'Ada', 'visits': '2'});
            expect(await client.hexists(hash, 'name'), isTrue);
            expect(await client.hlen(hash), 2);
            expect(await client.hincrby(hash, 'visits', 3), 5);
            expect(await client.hdel(hash, ['name']), 1);

            final set = 'runnel:integration:set:$suffix';
            expect(await client.sadd(set, ['a', 'b', 'a']), 2);
            expect(await client.sismember(set, 'a'), isTrue);
            expect(await client.smembers(set), {'a', 'b'});
            expect(await client.scard(set), 2);
            expect(await client.srem(set, ['a']), 1);

            final list = 'runnel:integration:list:$suffix';
            expect(await client.rpush(list, ['b', 'c']), 2);
            expect(await client.lpush(list, ['a']), 3);
            expect(await client.lrange(list, 0, -1), ['a', 'b', 'c']);
            expect(await client.llen(list), 3);
            await client.ltrim(list, 0, 1);
            expect(await client.lpop(list), 'a');
            expect(await client.rpop(list), 'b');
            expect(await client.lpop(list), isNull);

            final sorted = 'runnel:integration:sorted:$suffix';
            expect(await client.zadd(sorted, {'a': 1, 'b': 2, 'c': 3}), 3);
            expect(await client.zscore(sorted, 'missing'), isNull);
            expect(await client.zscore(sorted, 'b'), 2);
            expect(await client.zincrby(sorted, 0.5, 'b'), 2.5);
            expect(await client.zrange(sorted, 0, -1), ['a', 'b', 'c']);
            expect(await client.zrangeWithScores(sorted, 0, -1), [
              (member: 'a', score: 1.0),
              (member: 'b', score: 2.5),
              (member: 'c', score: 3.0),
            ]);
            expect(await client.zrangebyscore(sorted, 1, 2.5), ['a', 'b']);
            expect(await client.zremrangebyscore(sorted, 1, 1), 1);
            expect(await client.zrem(sorted, ['c']), 1);
            expect(await client.zcard(sorted), 1);

            final stream = 'runnel:integration:stream:$suffix';
            final firstStreamId = StreamId(BigInt.from(1000), BigInt.zero);
            expect(
              await client.xadd(
                stream,
                [
                  StreamField.text('event', 'created'),
                  StreamField(
                    Uint8List.fromList([0, 255]),
                    Uint8List.fromList([13, 10]),
                  ),
                  StreamField.text('event', 'duplicate'),
                ],
                id: firstStreamId,
              ),
              firstStreamId,
            );
            final secondStreamId = await client.xadd(
              stream,
              [StreamField.text('event', 'updated')],
              maxLength: 10,
            );
            expect(await client.xlen(stream), 2);
            final range = await client.xrange(
              stream,
              start: StreamBound.id(firstStreamId),
              end: StreamBound.id(secondStreamId),
            );
            expect(range.map((entry) => entry.id), [firstStreamId, secondStreamId]);
            expect(range.first.fields.map((field) => field.field), [
              utf8.encode('event'),
              [0, 255],
              utf8.encode('event'),
            ]);
            expect(
              (await client.xrevrange(stream, count: 1)).single.id,
              secondStreamId,
            );
            final reads = await client.xread({stream: firstStreamId});
            expect(reads.single.key, stream);
            expect(reads.single.entries.single.id, secondStreamId);
            expect(await client.xread({stream: secondStreamId}), isEmpty);
            expect(await client.ping(), isTrue);
            expect(await client.xtrim(stream, StreamTrim.maxLength(1)), 1);
            expect(
              await client.xtrim(stream, StreamTrim.minId(secondStreamId)),
              0,
            );

            final pipelineKey = 'runnel:integration:pipeline:$suffix';
            final pipelineCounter = 'runnel:integration:pipeline-counter:$suffix';
            await client.set(pipelineKey, 'value');
            final pipeline = client.pipeline();
            final pipelinedValue = pipeline.add(getCommand(pipelineKey));
            final pipelinedCount = pipeline.add(incrCommand(pipelineCounter));
            final pipelinedFailure = pipeline.add(incrCommand(hash));
            final pipelineResults = await pipeline.exec();
            expect(pipelineResults.value(pipelinedValue), 'value');
            expect(pipelineResults.value(pipelinedCount), 1);
            expect(
              pipelineResults.outcome(pipelinedFailure),
              isA<BatchFailure<int>>().having(
                (failure) => failure.error,
                'error',
                isA<RedisServerException>(),
              ),
            );

            final transactionCounter = 'runnel:integration:transaction:$suffix';
            final transaction = client.transaction();
            final firstIncrement = transaction.add(incrCommand(transactionCounter));
            final transactionFailure = transaction.add(incrCommand(hash));
            final secondIncrement = transaction.add(incrCommand(transactionCounter));
            final transactionResults = await transaction.exec();
            expect(transactionResults.value(firstIncrement), 1);
            expect(
              transactionResults.outcome(transactionFailure),
              isA<BatchFailure<int>>(),
            );
            expect(transactionResults.value(secondIncrement), 2);
            expect(await client.get(transactionCounter), '2');

            final rejectedTransaction = client.transaction()
              ..add(
                RedisCommand<void>(
                  [RedisArgument.text('SET')],
                  (_) {},
                ),
              );
            await expectLater(
              rejectedTransaction.exec(),
              throwsA(isA<RedisTransactionException>()),
            );

            final binaryScript = RedisScript<Uint8List>(
              'return ARGV[1]',
              (reply) => switch (reply) {
                RespBlobString(:final value) => Uint8List.fromList(value),
                _ => throw const FormatException('Expected a binary script reply.'),
              },
            );
            final scriptBytes = Uint8List.fromList([0, 255, 13, 10]);
            expect(
              await client.runScript(
                binaryScript,
                keys: [pipelineKey],
                arguments: [RedisArgument.bytes(scriptBytes)],
              ),
              scriptBytes,
            );
            expect(
              await client.runScript(
                binaryScript,
                keys: [pipelineKey],
                arguments: [RedisArgument.bytes(scriptBytes)],
              ),
              scriptBytes,
            );

            final incrementScript = RedisScript<int>(
              "return redis.call('INCR', KEYS[1])",
              (reply) => (reply as RespInteger).value,
            );
            final pipelineScriptKey = 'runnel:integration:pipeline-script:$suffix';
            final scriptPipeline = client.pipeline();
            final beforeScript = scriptPipeline.add(setCommand(pipelineScriptKey, '0'));
            final scriptResult = scriptPipeline.add(
              evalCommand(
                incrementScript,
                keys: [pipelineScriptKey],
                arguments: const [],
              ),
            );
            final afterScript = scriptPipeline.add(getCommand(pipelineScriptKey));
            final scriptPipelineResults = await scriptPipeline.exec();
            expect(scriptPipelineResults.value(beforeScript), isTrue);
            expect(scriptPipelineResults.value(scriptResult), 1);
            expect(scriptPipelineResults.value(afterScript), '1');

            final transactionScriptKey = 'runnel:integration:transaction-script:$suffix';
            final scriptTransaction = client.transaction();
            final transactionSetup = scriptTransaction.add(
              setCommand(transactionScriptKey, '0'),
            );
            final transactionScript = scriptTransaction.add(
              evalCommand(
                incrementScript,
                keys: [transactionScriptKey],
                arguments: const [],
              ),
            );
            final transactionAfterScript = scriptTransaction.add(
              getCommand(transactionScriptKey),
            );
            final scriptTransactionResults = await scriptTransaction.exec();
            expect(scriptTransactionResults.value(transactionSetup), isTrue);
            expect(scriptTransactionResults.value(transactionScript), 1);
            expect(scriptTransactionResults.value(transactionAfterScript), '1');

            final partialWriteKey = 'runnel:integration:partial-script:$suffix';
            final runtimeErrorScript = RedisScript<void>(
              "redis.call('SET', KEYS[1], 'written'); return redis.call('NO-SUCH-COMMAND')",
              (_) {},
            );
            await expectLater(
              client.runScript(
                runtimeErrorScript,
                keys: [partialWriteKey],
                arguments: const [],
              ),
              throwsA(isA<RedisServerException>()),
            );
            expect(await client.get(partialWriteKey), 'written');

            final blocking = await client.blocking();
            addTearDown(blocking.close);
            final blockingList = 'runnel:integration:blocking-list:$suffix';
            final leftPop = blocking.blpop(
              [blockingList],
              wait: const Duration(seconds: 1),
            );
            expect(await client.rpush(blockingList, ['left']), 1);
            expect(await leftPop, (key: blockingList, value: 'left'));

            final rightPop = blocking.brpop(
              [blockingList],
              wait: const Duration(seconds: 1),
            );
            expect(await client.lpush(blockingList, ['right']), 1);
            expect(await rightPop, (key: blockingList, value: 'right'));
            expect(
              await blocking.blpop(
                ['runnel:integration:empty-list:$suffix'],
                wait: const Duration(milliseconds: 1),
              ),
              isNull,
            );

            final blockingStream = 'runnel:integration:blocking-stream:$suffix';
            final blockingRead = blocking.xread(
              {blockingStream: StreamId(BigInt.zero, BigInt.zero)},
              wait: const Duration(seconds: 1),
            );
            final deliveredStreamId = await client.xadd(
              blockingStream,
              [StreamField.text('event', 'delivered')],
            );
            expect((await blockingRead).single.entries.single.id, deliveredStreamId);
            expect(
              await blocking.xread(
                {blockingStream: deliveredStreamId},
                wait: const Duration(milliseconds: 1),
              ),
              isEmpty,
            );

            final isolatedWait = blocking.blpop(
              [blockingList],
              wait: const Duration(seconds: 1),
            );
            expect(await client.set('$blockingList:ordinary', 'ready'), isTrue);
            expect(await client.get('$blockingList:ordinary'), 'ready');
            expect(await client.rpush(blockingList, ['release']), 1);
            expect(await isolatedWait, (key: blockingList, value: 'release'));

            final pubSub = await client.openPubSub();
            addTearDown(pubSub.close);
            final channelOne = 'runnel:integration:channel-one:$suffix';
            final channelTwo = 'runnel:integration:channel-two:$suffix';
            final publications = <PubSubMessage>[];
            final received = Completer<void>();
            String? coordinatedChannel;
            Completer<PubSubMessage>? coordinatedReceived;
            Completer<PubSubInterrupted>? interrupted;
            Completer<PubSubRestored>? restored;
            Completer<PubSubMessage>? restoredPublication;
            final listener = pubSub.events.listen((event) {
              if (event is PubSubMessage) {
                publications.add(event);
                if (publications.length == 2 && !received.isCompleted) received.complete();
                if (event.channel == coordinatedChannel) {
                  final completer = coordinatedReceived;
                  if (completer != null && !completer.isCompleted) completer.complete(event);
                }
                final recoveryCompleter = restoredPublication;
                if (recoveryCompleter != null &&
                    !recoveryCompleter.isCompleted &&
                    event.channel == channelTwo &&
                    event.text == 'after-recovery') {
                  recoveryCompleter.complete(event);
                }
              }
              if (event is PubSubInterrupted) {
                final completer = interrupted;
                if (completer != null && !completer.isCompleted) completer.complete(event);
              }
              if (event is PubSubRestored) {
                final completer = restored;
                if (completer != null && !completer.isCompleted) completer.complete(event);
              }
            });
            addTearDown(listener.cancel);
            await pubSub.subscribe([channelOne, channelTwo, channelOne]);
            expect(pubSub.generation, 1);
            expect(pubSub.desiredChannels, {channelOne, channelTwo});
            expect(await client.publish(channelOne, 'hello'), 1);
            expect(
              await client.publishBytes(channelTwo, Uint8List.fromList([0, 255])),
              1,
            );
            await received.future.timeout(const Duration(seconds: 2));
            expect(publications[0].channel, channelOne);
            expect(publications[0].text, 'hello');
            expect(publications[1].channel, channelTwo);
            expect(publications[1].payload, [0, 255]);
            await pubSub.unsubscribe([channelOne]);
            expect(await client.publish(channelOne, 'suppressed'), 0);
            expect(pubSub.desiredChannels, {channelTwo});

            final names = HeraldFixtureNames(appId: suffix, channel: 'orders');
            coordinatedChannel = names.channelName;
            coordinatedReceived = Completer<PubSubMessage>();
            await pubSub.subscribe([names.channelName]);
            final coordinated = await publishCoordinated(
              client,
              names,
              receiptId: 'receipt-1',
              payload: 'created',
              publishedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
              oldestRetainedMilliseconds: 0,
              maximumHistoryCount: 10,
            );
            expect(coordinated.position, 1);
            expect(coordinated.subscriberCount, 1);
            expect(coordinated.duplicate, isFalse);
            expect(
              (await coordinatedReceived.future.timeout(const Duration(seconds: 2))).text,
              '1|created',
            );
            final duplicate = await publishCoordinated(
              client,
              names,
              receiptId: 'receipt-1',
              payload: 'ignored',
              publishedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
              oldestRetainedMilliseconds: 0,
              maximumHistoryCount: 10,
            );
            expect(duplicate.position, 1);
            expect(duplicate.duplicate, isTrue);
            expect(await client.xlen(names.historyKey), 1);
            expect(await client.get(names.snapshotKey), '1|created');
            expect(await client.hget(names.metadataKey, 'position'), '1');

            expect(
              await upsertPresenceLease(
                client,
                names,
                connectionId: 'connection-a',
                userId: 'user-1',
                expiresAtMilliseconds: 1000,
              ),
              1,
            );
            await upsertPresenceLease(
              client,
              names,
              connectionId: 'connection-b',
              userId: 'user-1',
              expiresAtMilliseconds: 2000,
            );
            await upsertPresenceLease(
              client,
              names,
              connectionId: 'connection-c',
              userId: 'user-2',
              expiresAtMilliseconds: 3000,
            );
            final connections = await client.hgetall(names.presenceConnectionsKey);
            expect(connections, hasLength(3));
            expect(distinctPresenceUsers(connections), 2);
            expect(
              await removeExpiredPresenceLeases(
                client,
                names,
                nowMilliseconds: 2000,
              ),
              2,
            );
            expect(await client.hlen(names.presenceConnectionsKey), 1);

            interrupted = Completer<PubSubInterrupted>();
            restored = Completer<PubSubRestored>();
            restoredPublication = Completer<PubSubMessage>();
            expect(await client.execute(_killPubSubClientsCommand()), greaterThanOrEqualTo(1));
            final interruption = await interrupted.future.timeout(const Duration(seconds: 5));
            final restoration = await restored.future.timeout(const Duration(seconds: 5));
            expect(interruption.generation, 1);
            expect(interruption.cause, PubSubInterruptionCause.networkLoss);
            expect(restoration.generation, 2);
            expect(restoration.channels, {channelTwo, names.channelName});
            expect(pubSub.desiredChannels, {channelTwo, names.channelName});
            expect(pubSub.acknowledgedChannels, {channelTwo, names.channelName});
            expect(await client.publish(channelOne, 'still-suppressed'), 0);
            expect(await client.publish(channelTwo, 'after-recovery'), 1);
            expect(
              (await restoredPublication.future.timeout(const Duration(seconds: 2))).generation,
              2,
            );

            final probe = DeliveryPathProbe.forRunnel(publisher: client, subscriber: pubSub);
            final probeResult = await probe.check(
              channel: names.channelName,
              token: 'probe',
              awaitDelivery: (_, _) async => false,
              deliveryTimeout: const Duration(milliseconds: 10),
              reconnectTimeout: const Duration(seconds: 2),
            );
            expect(probeResult.healthBeforeRecovery, PubSubState.ready);
            expect(probeResult.reconnectRequested, isTrue);
            expect(pubSub.state, PubSubState.ready);
          },
        );
      });
    }
  });
}

RedisCommand<int> _killPubSubClientsCommand() => RedisCommand<int>(
  [
    RedisArgument.text('CLIENT'),
    RedisArgument.text('KILL'),
    RedisArgument.text('TYPE'),
    RedisArgument.text('PUBSUB'),
  ],
  (reply) => switch (reply) {
    RespInteger(:final value) => value,
    _ => throw FormatException('CLIENT KILL returned $reply instead of an integer.'),
  },
);

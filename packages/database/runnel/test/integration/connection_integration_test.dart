@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
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
            ).runFuture();
            addTearDown(() => client.close().runFuture());
            final suffix = '${DateTime.now().microsecondsSinceEpoch}-resp3';
            final textKey = 'runnel:integration:text:$suffix';
            final bytesKey = 'runnel:integration:bytes:$suffix';

            expect(await client.ping().runFuture(), isTrue);
            expect(await client.set(textKey, 'café').runFuture(), isTrue);
            expect(
              await client.get(textKey).runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', 'café'),
            );
            expect(
              await client.setBytes(bytesKey, Uint8List.fromList([0, 255, 13, 10])).runFuture(),
              isTrue,
            );
            expect(
              await client.getBytes(bytesKey).runFuture(),
              isA<Some<Uint8List>>().having((value) => value.value, 'value', [0, 255, 13, 10]),
            );

            final conditionalKey = 'runnel:integration:conditional:$suffix';
            expect(
              await client
                  .set(
                    conditionalKey,
                    'first',
                    condition: SetCondition.ifAbsent,
                    expiry: Expiry.after(const Duration(seconds: 5)),
                  )
                  .runFuture(),
              isTrue,
            );
            expect(
              await client
                  .set(
                    conditionalKey,
                    'ignored',
                    condition: SetCondition.ifAbsent,
                  )
                  .runFuture(),
              isFalse,
            );
            expect(
              await client
                  .set(
                    conditionalKey,
                    'second',
                    condition: SetCondition.ifPresent,
                    expiry: const Expiry.keep(),
                  )
                  .runFuture(),
              isTrue,
            );
            expect(await client.pttl(conditionalKey).runFuture(), inInclusiveRange(1, 5000));
            expect(await client.set(conditionalKey, 'without-expiry').runFuture(), isTrue);
            expect(await client.pttl(conditionalKey).runFuture(), -1);
            expect(
              await client
                  .set(
                    conditionalKey,
                    'absolute-expiry',
                    expiry: Expiry.at(
                      DateTime.fromMillisecondsSinceEpoch(
                        DateTime.now().millisecondsSinceEpoch + 10000,
                        isUtc: true,
                      ),
                    ),
                  )
                  .runFuture(),
              isTrue,
            );
            expect(await client.pttl(conditionalKey).runFuture(), inInclusiveRange(1, 10000));
            expect(await client.persist(conditionalKey).runFuture(), isTrue);
            expect(await client.pttl(conditionalKey).runFuture(), -1);

            final first = 'runnel:integration:scalar:$suffix:first';
            final second = 'runnel:integration:scalar:$suffix:second';
            await client.mset({first: 'one', second: 'two'}).runFuture();
            expect(await client.mget([first, 'missing:$suffix', first]).runFuture(), [
              isA<Some<String>>().having((value) => value.value, 'value', 'one'),
              isA<None>(),
              isA<Some<String>>().having((value) => value.value, 'value', 'one'),
            ]);
            expect(await client.exists([first, first, second]).runFuture(), 3);
            expect(await client.type(first).runFuture(), 'string');
            expect(await client.expire(second, Duration.zero).runFuture(), isTrue);
            expect(await client.pttl(second).runFuture(), -2);
            final counter = 'runnel:integration:counter:$suffix';
            expect(await client.incr(counter).runFuture(), 1);
            expect(await client.incrby(counter, 4).runFuture(), 5);
            expect(await client.decr(counter).runFuture(), 4);
            expect(await client.decrby(counter, 2).runFuture(), 2);

            final scanned = await client
                .scan(
                  match: 'runnel:integration:scalar:$suffix:*',
                  count: 1,
                )
                .toStream()
                .toSet();
            expect(scanned, contains(first));
            expect(await client.del([first]).runFuture(), 1);
            expect(await client.unlink([conditionalKey]).runFuture(), 1);

            expect(
              await client
                  .execute(
                    RedisCommand<String>(
                      [RedisArgument.text('ECHO'), RedisArgument.text('custom')],
                      (reply) => Success(respText(reply)),
                    ),
                  )
                  .runFuture(),
              'custom',
            );

            final hash = 'runnel:integration:hash:$suffix';
            expect(await client.hset(hash, {'name': 'Ada', 'visits': '2'}).runFuture(), 2);
            expect(
              await client.hget(hash, 'name').runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', 'Ada'),
            );
            expect(await client.hmget(hash, ['name', 'missing']).runFuture(), [
              isA<Some<String>>().having((value) => value.value, 'value', 'Ada'),
              isA<None>(),
            ]);
            expect(await client.hgetall(hash).runFuture(), {'name': 'Ada', 'visits': '2'});
            expect(await client.hexists(hash, 'name').runFuture(), isTrue);
            expect(await client.hlen(hash).runFuture(), 2);
            expect(await client.hincrby(hash, 'visits', 3).runFuture(), 5);
            expect(await client.hdel(hash, ['name']).runFuture(), 1);

            final set = 'runnel:integration:set:$suffix';
            expect(await client.sadd(set, ['a', 'b', 'a']).runFuture(), 2);
            expect(await client.sismember(set, 'a').runFuture(), isTrue);
            expect(await client.smembers(set).runFuture(), {'a', 'b'});
            expect(await client.scard(set).runFuture(), 2);
            expect(await client.srem(set, ['a']).runFuture(), 1);

            final list = 'runnel:integration:list:$suffix';
            expect(await client.rpush(list, ['b', 'c']).runFuture(), 2);
            expect(await client.lpush(list, ['a']).runFuture(), 3);
            expect(await client.lrange(list, 0, -1).runFuture(), ['a', 'b', 'c']);
            expect(await client.llen(list).runFuture(), 3);
            await client.ltrim(list, 0, 1).runFuture();
            expect(
              await client.lpop(list).runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', 'a'),
            );
            expect(
              await client.rpop(list).runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', 'b'),
            );
            expect(await client.lpop(list).runFuture(), isA<None>());

            final sorted = 'runnel:integration:sorted:$suffix';
            expect(await client.zadd(sorted, {'a': 1, 'b': 2, 'c': 3}).runFuture(), 3);
            expect(await client.zscore(sorted, 'missing').runFuture(), isA<None>());
            expect(
              await client.zscore(sorted, 'b').runFuture(),
              isA<Some<double>>().having((value) => value.value, 'value', 2),
            );
            expect(await client.zincrby(sorted, 0.5, 'b').runFuture(), 2.5);
            expect(await client.zrange(sorted, 0, -1).runFuture(), ['a', 'b', 'c']);
            expect(await client.zrangeWithScores(sorted, 0, -1).runFuture(), [
              (member: 'a', score: 1.0),
              (member: 'b', score: 2.5),
              (member: 'c', score: 3.0),
            ]);
            expect(await client.zrangebyscore(sorted, 1, 2.5).runFuture(), ['a', 'b']);
            expect(await client.zremrangebyscore(sorted, 1, 1).runFuture(), 1);
            expect(await client.zrem(sorted, ['c']).runFuture(), 1);
            expect(await client.zcard(sorted).runFuture(), 1);

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
              ).runFuture(),
              firstStreamId,
            );
            final secondStreamId = await client.xadd(
              stream,
              [StreamField.text('event', 'updated')],
              maxLength: 10,
            ).runFuture();
            expect(await client.xlen(stream).runFuture(), 2);
            final range = await client
                .xrange(
                  stream,
                  start: StreamBound.id(firstStreamId),
                  end: StreamBound.id(secondStreamId),
                )
                .runFuture();
            expect(range.map((entry) => entry.id), [firstStreamId, secondStreamId]);
            expect(range.first.fields.map((field) => field.field), [
              utf8.encode('event'),
              [0, 255],
              utf8.encode('event'),
            ]);
            expect(
              (await client.xrevrange(stream, count: 1).runFuture()).single.id,
              secondStreamId,
            );
            final reads = await client.xread({stream: firstStreamId}).runFuture();
            expect(reads.single.key, stream);
            expect(reads.single.entries.single.id, secondStreamId);
            expect(await client.xread({stream: secondStreamId}).runFuture(), isEmpty);
            expect(await client.ping().runFuture(), isTrue);
            expect(await client.xtrim(stream, StreamTrim.maxLength(1)).runFuture(), 1);
            expect(
              await client.xtrim(stream, StreamTrim.minId(secondStreamId)).runFuture(),
              0,
            );

            final pipelineKey = 'runnel:integration:pipeline:$suffix';
            final pipelineCounter = 'runnel:integration:pipeline-counter:$suffix';
            await client.set(pipelineKey, 'value').runFuture();
            final pipeline = client.pipeline();
            final pipelinedValue = pipeline.add(getCommand(pipelineKey));
            final pipelinedCount = pipeline.add(incrCommand(pipelineCounter));
            final pipelinedFailure = pipeline.add(incrCommand(hash));
            final pipelineResults = await pipeline.exec().runFuture();
            expect(
              pipelineResults.outcome(pipelinedValue).getOrThrowWith((error) => error),
              isA<Some<String>>().having((value) => value.value, 'value', 'value'),
            );
            expect(pipelineResults.outcome(pipelinedCount).getOrThrowWith((error) => error), 1);
            expect(
              pipelineResults.outcome(pipelinedFailure),
              isA<Failure<int, RunnelError>>().having(
                (failure) => failure.error,
                'error',
                isA<RunnelServerError>(),
              ),
            );

            final transactionCounter = 'runnel:integration:transaction:$suffix';
            final transaction = client.transaction();
            final firstIncrement = transaction.add(incrCommand(transactionCounter));
            final transactionFailure = transaction.add(incrCommand(hash));
            final secondIncrement = transaction.add(incrCommand(transactionCounter));
            final transactionResults = await transaction.exec().runFuture();
            expect(transactionResults.outcome(firstIncrement).getOrThrowWith((error) => error), 1);
            expect(
              transactionResults.outcome(transactionFailure),
              isA<Failure<int, RunnelError>>(),
            );
            expect(transactionResults.outcome(secondIncrement).getOrThrowWith((error) => error), 2);
            expect(
              await client.get(transactionCounter).runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', '2'),
            );

            final rejectedTransaction = client.transaction()
              ..add(
                RedisCommand<void>(
                  [RedisArgument.text('SET')],
                  (_) => const Success(null),
                ),
              );
            await expectLater(
              rejectedTransaction.exec().runFuture(),
              throwsA(
                isA<EffectException<RunnelError>>().having(
                  (error) => error.cause.expectedErrors.single,
                  'error',
                  isA<RunnelTransactionError>(),
                ),
              ),
            );

            final binaryScript = RedisScript<Uint8List>(
              'return ARGV[1]',
              (reply) => switch (reply) {
                RespBlobString(:final value) => Success(Uint8List.fromList(value)),
                _ => throw const FormatException('Expected a binary script reply.'),
              },
            );
            final scriptBytes = Uint8List.fromList([0, 255, 13, 10]);
            expect(
              await client
                  .runScript(
                    binaryScript,
                    keys: [pipelineKey],
                    arguments: [RedisArgument.bytes(scriptBytes)],
                  )
                  .runFuture(),
              scriptBytes,
            );
            expect(
              await client
                  .runScript(
                    binaryScript,
                    keys: [pipelineKey],
                    arguments: [RedisArgument.bytes(scriptBytes)],
                  )
                  .runFuture(),
              scriptBytes,
            );

            final incrementScript = RedisScript<int>(
              "return redis.call('INCR', KEYS[1])",
              (reply) => Success((reply as RespInteger).value),
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
            final scriptPipelineResults = await scriptPipeline.exec().runFuture();
            expect(
              scriptPipelineResults.outcome(beforeScript).getOrThrowWith((error) => error),
              isTrue,
            );
            expect(scriptPipelineResults.outcome(scriptResult).getOrThrowWith((error) => error), 1);
            expect(
              scriptPipelineResults.outcome(afterScript).getOrThrowWith((error) => error),
              isA<Some<String>>().having((value) => value.value, 'value', '1'),
            );

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
            final scriptTransactionResults = await scriptTransaction.exec().runFuture();
            expect(
              scriptTransactionResults.outcome(transactionSetup).getOrThrowWith((error) => error),
              isTrue,
            );
            expect(
              scriptTransactionResults.outcome(transactionScript).getOrThrowWith((error) => error),
              1,
            );
            expect(
              scriptTransactionResults
                  .outcome(transactionAfterScript)
                  .getOrThrowWith((error) => error),
              isA<Some<String>>().having((value) => value.value, 'value', '1'),
            );

            final partialWriteKey = 'runnel:integration:partial-script:$suffix';
            final runtimeErrorScript = RedisScript<void>(
              "redis.call('SET', KEYS[1], 'written'); return redis.call('NO-SUCH-COMMAND')",
              (_) => const Success(null),
            );
            await expectLater(
              client
                  .runScript(
                    runtimeErrorScript,
                    keys: [partialWriteKey],
                    arguments: const [],
                  )
                  .runFuture(),
              throwsA(
                isA<EffectException<RunnelError>>().having(
                  (error) => error.cause.expectedErrors.single,
                  'error',
                  isA<RunnelServerError>(),
                ),
              ),
            );
            expect(
              await client.get(partialWriteKey).runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', 'written'),
            );

            final blocking = await client.blocking().runFuture();
            addTearDown(() => blocking.close().runFuture());
            final blockingList = 'runnel:integration:blocking-list:$suffix';
            final leftPop = blocking.blpop(
              [blockingList],
              wait: const Duration(seconds: 1),
            ).runFuture();
            expect(await client.rpush(blockingList, ['left']).runFuture(), 1);
            expect(
              await leftPop,
              isA<Some<({String key, String value})>>().having((s) => s.value, 'value', (
                key: blockingList,
                value: 'left',
              )),
            );

            final rightPop = blocking.brpop(
              [blockingList],
              wait: const Duration(seconds: 1),
            ).runFuture();
            expect(await client.lpush(blockingList, ['right']).runFuture(), 1);
            expect(
              await rightPop,
              isA<Some<({String key, String value})>>().having((s) => s.value, 'value', (
                key: blockingList,
                value: 'right',
              )),
            );
            expect(
              await blocking.blpop(
                ['runnel:integration:empty-list:$suffix'],
                wait: const Duration(milliseconds: 1),
              ).runFuture(),
              isA<None>(),
            );

            final blockingStream = 'runnel:integration:blocking-stream:$suffix';
            final blockingRead = blocking.xread(
              {blockingStream: StreamId(BigInt.zero, BigInt.zero)},
              wait: const Duration(seconds: 1),
            ).runFuture();
            final deliveredStreamId = await client.xadd(
              blockingStream,
              [StreamField.text('event', 'delivered')],
            ).runFuture();
            expect((await blockingRead).single.entries.single.id, deliveredStreamId);
            expect(
              await blocking.xread(
                {blockingStream: deliveredStreamId},
                wait: const Duration(milliseconds: 1),
              ).runFuture(),
              isEmpty,
            );

            final isolatedWait = blocking.blpop(
              [blockingList],
              wait: const Duration(seconds: 1),
            ).runFuture();
            expect(await client.set('$blockingList:ordinary', 'ready').runFuture(), isTrue);
            expect(
              await client.get('$blockingList:ordinary').runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', 'ready'),
            );
            expect(await client.rpush(blockingList, ['release']).runFuture(), 1);
            expect(
              await isolatedWait,
              isA<Some<({String key, String value})>>().having((value) => value.value, 'value', (
                key: blockingList,
                value: 'release',
              )),
            );

            final pubSub = await client.openPubSub().runFuture();
            addTearDown(() => pubSub.close().runFuture());
            final channelOne = 'runnel:integration:channel-one:$suffix';
            final channelTwo = 'runnel:integration:channel-two:$suffix';
            final publications = <PubSubMessage>[];
            final received = Completer<void>();
            String? coordinatedChannel;
            Completer<PubSubMessage>? coordinatedReceived;
            Completer<PubSubInterrupted>? interrupted;
            Completer<PubSubRestored>? restored;
            Completer<PubSubMessage>? restoredPublication;
            final listener = pubSub.events.toStream().listen((event) {
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
                    event.decodeText().getOrThrowWith((error) => error) == 'after-recovery') {
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
            await pubSub.subscribe([channelOne, channelTwo, channelOne]).runFuture();
            expect(pubSub.generation, 1);
            expect(pubSub.desiredChannels, {channelOne, channelTwo});
            expect(await client.publish(channelOne, 'hello').runFuture(), 1);
            expect(
              await client.publishBytes(channelTwo, Uint8List.fromList([0, 255])).runFuture(),
              1,
            );
            await received.future.timeout(const Duration(seconds: 2));
            expect(publications[0].channel, channelOne);
            expect(publications[0].decodeText().getOrThrowWith((error) => error), 'hello');
            expect(publications[1].channel, channelTwo);
            expect(publications[1].payload, [0, 255]);
            await pubSub.unsubscribe([channelOne]).runFuture();
            expect(await client.publish(channelOne, 'suppressed').runFuture(), 0);
            expect(pubSub.desiredChannels, {channelTwo});

            final names = HeraldFixtureNames(appId: suffix, channel: 'orders');
            coordinatedChannel = names.channelName;
            coordinatedReceived = Completer<PubSubMessage>();
            await pubSub.subscribe([names.channelName]).runFuture();
            final coordinated = await publishCoordinated(
              client,
              names,
              receiptId: 'receipt-1',
              payload: 'created',
              publishedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
              oldestRetainedMilliseconds: 0,
              maximumHistoryCount: 10,
            ).runFuture();
            expect(coordinated.position, 1);
            expect(coordinated.subscriberCount, 1);
            expect(coordinated.duplicate, isFalse);
            expect(
              (await coordinatedReceived.future.timeout(const Duration(seconds: 2)))
                  .decodeText()
                  .getOrThrowWith((error) => error),
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
            ).runFuture();
            expect(duplicate.position, 1);
            expect(duplicate.duplicate, isTrue);
            expect(await client.xlen(names.historyKey).runFuture(), 1);
            expect(
              await client.get(names.snapshotKey).runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', '1|created'),
            );
            expect(
              await client.hget(names.metadataKey, 'position').runFuture(),
              isA<Some<String>>().having((value) => value.value, 'value', '1'),
            );

            expect(
              await upsertPresenceLease(
                client,
                names,
                connectionId: 'connection-a',
                userId: 'user-1',
                expiresAtMilliseconds: 1000,
              ).runFuture(),
              1,
            );
            await upsertPresenceLease(
              client,
              names,
              connectionId: 'connection-b',
              userId: 'user-1',
              expiresAtMilliseconds: 2000,
            ).runFuture();
            await upsertPresenceLease(
              client,
              names,
              connectionId: 'connection-c',
              userId: 'user-2',
              expiresAtMilliseconds: 3000,
            ).runFuture();
            final connections = await client.hgetall(names.presenceConnectionsKey).runFuture();
            expect(connections, hasLength(3));
            expect(distinctPresenceUsers(connections), 2);
            expect(
              await removeExpiredPresenceLeases(
                client,
                names,
                nowMilliseconds: 2000,
              ).runFuture(),
              2,
            );
            expect(await client.hlen(names.presenceConnectionsKey).runFuture(), 1);

            interrupted = Completer<PubSubInterrupted>();
            restored = Completer<PubSubRestored>();
            restoredPublication = Completer<PubSubMessage>();
            expect(
              await client.execute(_killPubSubClientsCommand()).runFuture(),
              greaterThanOrEqualTo(1),
            );
            final interruption = await interrupted.future.timeout(const Duration(seconds: 5));
            final restoration = await restored.future.timeout(const Duration(seconds: 5));
            expect(interruption.generation, 1);
            expect(interruption.cause, PubSubInterruptionCause.networkLoss);
            expect(restoration.generation, 2);
            expect(restoration.channels, {channelTwo, names.channelName});
            expect(pubSub.desiredChannels, {channelTwo, names.channelName});
            expect(pubSub.acknowledgedChannels, {channelTwo, names.channelName});
            expect(await client.publish(channelOne, 'still-suppressed').runFuture(), 0);
            expect(await client.publish(channelTwo, 'after-recovery').runFuture(), 1);
            expect(
              (await restoredPublication.future.timeout(const Duration(seconds: 2))).generation,
              2,
            );

            final probe = DeliveryPathProbe.forRunnel(publisher: client, subscriber: pubSub);
            final probeResult = await probe
                .check(
                  channel: names.channelName,
                  token: 'probe',
                  awaitDelivery: (_, _) async => false,
                  deliveryTimeout: const Duration(milliseconds: 10),
                  reconnectTimeout: const Duration(seconds: 2),
                )
                .runFuture();
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
    RespInteger(:final value) => Success(value),
    _ => throw FormatException('CLIENT KILL returned $reply instead of an integer.'),
  },
);

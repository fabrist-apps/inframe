// Analyzer fixture: only public entrypoints and narrow Conflux imports.
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';

void verifyPublicSignatures(
  Runnel client,
  BlockingSession blocking,
  PubSubSession subscription,
  BatchResults results,
  BatchRef<Option<String?>> presenceRef,
  BatchRef<String?> nullableRef,
) {
  _accept<Effect<Runnel, RunnelError>>(Runnel.connect('redis://localhost'));
  _accept<Effect<BlockingSession, RunnelError>>(client.blocking());
  _accept<Effect<PubSubSession, RunnelError>>(client.openPubSub());
  _accept<Effect<void, Never>>(client.close());
  _accept<Effect<void, Never>>(blocking.close());
  _accept<Effect<void, Never>>(subscription.close());
  _accept<Effect<void, RunnelError>>(subscription.subscribe(['channel']));
  _accept<Effect<void, RunnelError>>(subscription.unsubscribe(['channel']));
  _accept<Effect<void, RunnelError>>(subscription.reconnect());
  _accept<Flow<PubSubEvent, RunnelError>>(subscription.events);
  _accept<Flow<String, RunnelError>>(client.scan());
  _accept<Effect<Option<String>, RunnelError>>(client.get('key'));
  _accept<Effect<Option<String>, RunnelError>>(client.hget('key', 'field'));
  _accept<Effect<Option<String>, RunnelError>>(client.lpop('key'));
  _accept<Effect<Option<String>, RunnelError>>(client.rpop('key'));
  _accept<Effect<Option<Uint8List>, RunnelError>>(client.getBytes('key'));
  _accept<Effect<Option<double>, RunnelError>>(client.zscore('key', 'member'));
  _accept<Effect<List<Option<String>>, RunnelError>>(client.mget(['key']));
  _accept<Effect<List<Option<String>>, RunnelError>>(client.hmget('key', ['field']));
  _accept<Effect<Option<({String key, String value})>, RunnelError>>(
    blocking.blpop(['key'], wait: const Duration(seconds: 1)),
  );
  _accept<Effect<Option<({String key, String value})>, RunnelError>>(
    blocking.brpop(['key'], wait: const Duration(seconds: 1)),
  );
  _accept<Effect<List<StreamRead>, RunnelError>>(
    client.xread({'key': StreamId(BigInt.zero, BigInt.zero)}),
  );
  _accept<Effect<bool, RunnelError>>(client.set('key', 'value'));
  _accept<Effect<int, RunnelError>>(client.pttl('key'));
  final command = RedisCommand<String?>([
    RedisArgument.text('GET'),
    RedisArgument.text('key'),
  ], (_) => const Success(null));
  final script = RedisScript<Option<String?>>('return nil', (_) => const Success(Some(null)));
  _accept<Result<String?, RunnelError>>(command.decode(const RespNull()));
  _accept<Result<Option<String?>, RunnelError>>(script.decode(const RespNull()));
  _accept<Effect<String?, RunnelError>>(client.execute(command));
  _accept<Effect<Option<String?>, RunnelError>>(
    client.runScript(script, keys: [], arguments: []),
  );
  _accept<Effect<BatchResults, RunnelError>>(client.pipeline().exec());
  _accept<Effect<BatchResults, RunnelError>>(client.transaction().exec());
  _accept<Result<Option<String?>, RunnelError>>(results.outcome(presenceRef));
  _accept<Result<String?, RunnelError>>(results.outcome(nullableRef));
}

void _accept<T>(T value) {}

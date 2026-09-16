import 'dart:async';
import 'dart:collection';

import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';

/// One position-addressed publication owned by the consumer fixture.
final class HeraldEvent {
  const HeraldEvent({required this.epoch, required this.position, required this.payload});

  final String epoch;
  final int position;
  final String payload;
}

/// A history response read after the live subscription acknowledgement.
final class HeraldHistoryPage {
  HeraldHistoryPage({required this.epoch, required Iterable<HeraldEvent> events})
    : events = List.unmodifiable(events);

  final String epoch;
  final List<HeraldEvent> events;
}

/// The result of merging stored history with publications buffered during the read.
final class HistoryHandoverResult {
  HistoryHandoverResult._({required Iterable<HeraldEvent> events, required this.reloadRequired})
    : events = List.unmodifiable(events);

  factory HistoryHandoverResult.ready(Iterable<HeraldEvent> events) =>
      HistoryHandoverResult._(events: events, reloadRequired: false);

  factory HistoryHandoverResult.reload() =>
      HistoryHandoverResult._(events: const [], reloadRequired: true);

  final List<HeraldEvent> events;
  final bool reloadRequired;
}

/// Consumer-owned subscribe-before-read history handover logic.
final class HistoryHandoverFixture {
  Effect<HistoryHandoverResult, HeraldConsumerError> recover({
    required String expectedEpoch,
    required int lastSeenPosition,
    required Effect<void, HeraldConsumerError> Function(
      void Function(HeraldEvent event) onLiveEvent,
    )
    subscribe,
    required Effect<HeraldHistoryPage, HeraldConsumerError> Function() readHistory,
  }) => Effect.build(($) async {
    final buffered = <HeraldEvent>[];
    await $(subscribe(buffered.add));
    final history = await $(readHistory());
    if (history.epoch != expectedEpoch) return HistoryHandoverResult.reload();

    final byPosition = SplayTreeMap<int, HeraldEvent>();
    for (final event in [...history.events, ...buffered]) {
      if (event.epoch != expectedEpoch || event.position <= 0) {
        return HistoryHandoverResult.reload();
      }
      if (event.position <= lastSeenPosition) continue;
      final previous = byPosition[event.position];
      if (previous != null && previous.payload != event.payload) {
        return HistoryHandoverResult.reload();
      }
      byPosition[event.position] = event;
    }

    var expectedPosition = lastSeenPosition + 1;
    for (final event in byPosition.values) {
      if (event.position != expectedPosition) return HistoryHandoverResult.reload();
      expectedPosition++;
    }
    return HistoryHandoverResult.ready(byPosition.values);
  });
}

/// A complete latest-state snapshot.
final class VersionedSnapshot {
  const VersionedSnapshot({required this.epoch, required this.version, required this.state});

  final String epoch;
  final int version;
  final String state;
}

/// A live state replacement that is valid only for [baseVersion].
final class VersionedDelta {
  const VersionedDelta({
    required this.epoch,
    required this.baseVersion,
    required this.version,
    required this.state,
  });

  final String epoch;
  final int baseVersion;
  final int version;
  final String state;
}

/// The result of applying buffered deltas to a complete snapshot.
final class LatestStateResult {
  const LatestStateResult({
    required this.epoch,
    required this.version,
    required this.state,
    required this.reloadRequired,
  });

  final String epoch;
  final int version;
  final String state;
  final bool reloadRequired;
}

/// Consumer-owned snapshot and delta handover logic.
final class LatestStateFixture {
  Effect<LatestStateResult, HeraldConsumerError> recover({
    required Effect<void, HeraldConsumerError> Function(
      void Function(VersionedDelta delta) onLiveDelta,
    )
    subscribe,
    required Effect<VersionedSnapshot, HeraldConsumerError> Function() readSnapshot,
  }) => Effect.build(($) async {
    final buffered = <VersionedDelta>[];
    await $(subscribe(buffered.add));
    final snapshot = await $(readSnapshot());
    var version = snapshot.version;
    var state = snapshot.state;
    for (final delta in buffered) {
      if (delta.epoch != snapshot.epoch) {
        return LatestStateResult(
          epoch: snapshot.epoch,
          version: version,
          state: state,
          reloadRequired: true,
        );
      }
      if (delta.version <= version) continue;
      if (delta.baseVersion != version) {
        return LatestStateResult(
          epoch: snapshot.epoch,
          version: version,
          state: state,
          reloadRequired: true,
        );
      }
      version = delta.version;
      state = delta.state;
    }
    return LatestStateResult(
      epoch: snapshot.epoch,
      version: version,
      state: state,
      reloadRequired: false,
    );
  });
}

/// Exact app-scoped names passed unchanged to Runnel.
final class HeraldFixtureNames {
  HeraldFixtureNames({required this.appId, required this.channel}) {
    if (appId.isEmpty) throw ArgumentError.value(appId, 'appId', 'must not be empty');
    if (channel.isEmpty) throw ArgumentError.value(channel, 'channel', 'must not be empty');
  }

  final String appId;
  final String channel;

  String get channelName => 'app:$appId:herald:$channel';
  String get historyKey => '$channelName:history';
  String get metadataKey => '$channelName:metadata';
  String get snapshotKey => '$channelName:snapshot';
  String get receiptsKey => '$channelName:receipts';
  String get presenceConnectionsKey => '$channelName:presence:connections';
  String get presenceLeasesKey => '$channelName:presence:leases';

  List<String> get publicationScriptKeys =>
      List.unmodifiable([historyKey, metadataKey, snapshotKey, receiptsKey]);

  List<String> get presenceScriptKeys =>
      List.unmodifiable([presenceConnectionsKey, presenceLeasesKey]);
}

/// The typed result of one consumer-coordinated publication.
final class CoordinatedPublication {
  const CoordinatedPublication({
    required this.position,
    required this.subscriberCount,
    required this.streamId,
    required this.duplicate,
  });

  final int position;
  final int subscriberCount;
  final String streamId;
  final bool duplicate;
}

final RedisScript<CoordinatedPublication> coordinatedPublicationScript = RedisScript(
  '''
local function key_type(key)
  local result = redis.call('TYPE', key)
  if type(result) == 'table' then return result.ok end
  return result
end

local expected_types = {'stream', 'hash', 'string', 'hash'}
for index = 1, 4 do
  local actual = key_type(KEYS[index])
  if actual ~= 'none' and actual ~= expected_types[index] then
    return redis.error_reply('WRONGTYPE unexpected Herald fixture key type')
  end
end

local receipt_id = ARGV[1]
local payload = ARGV[2]
local published_at = tonumber(ARGV[3])
local oldest_retained = tonumber(ARGV[4])
local maximum_count = tonumber(ARGV[5])
local channel = ARGV[6]
if receipt_id == '' or channel == '' or published_at == nil or oldest_retained == nil or
   maximum_count == nil or published_at < 0 or oldest_retained < 0 or maximum_count < 1 or
   published_at % 1 ~= 0 or oldest_retained % 1 ~= 0 or maximum_count % 1 ~= 0 then
  return redis.error_reply('ERR invalid Herald fixture input')
end

local existing = redis.call('HGET', KEYS[4], receipt_id)
if existing then
  local existing_position = tonumber(existing)
  if existing_position == nil or existing_position < 1 or existing_position % 1 ~= 0 then
    return redis.error_reply('ERR invalid Herald fixture receipt')
  end
  return {existing_position, -1, '', 1}
end

local position = redis.call('HINCRBY', KEYS[2], 'position', 1)
local stream_id = redis.call(
  'XADD', KEYS[1], '*',
  'position', tostring(position),
  'publishedAt', tostring(published_at),
  'payload', payload
)
redis.call('XTRIM', KEYS[1], 'MINID', tostring(oldest_retained) .. '-0')
redis.call('XTRIM', KEYS[1], 'MAXLEN', tostring(maximum_count))
redis.call('SET', KEYS[3], tostring(position) .. '|' .. payload)
local subscribers = redis.call('PUBLISH', channel, tostring(position) .. '|' .. payload)
redis.call('HSET', KEYS[4], receipt_id, tostring(position))
return {position, subscribers, stream_id, 0}
''',
  (reply) => _decodeResult(() => _decodeCoordinatedPublication(reply)),
);

/// Coordinates history, a complete snapshot, publication, and a retry receipt.
Effect<CoordinatedPublication, RunnelError> publishCoordinated(
  Runnel redis,
  HeraldFixtureNames names, {
  required String receiptId,
  required String payload,
  required int publishedAtMilliseconds,
  required int oldestRetainedMilliseconds,
  required int maximumHistoryCount,
  Duration? timeout,
}) => redis.runScript(
  coordinatedPublicationScript,
  keys: names.publicationScriptKeys,
  arguments: [
    RedisArgument.text(receiptId),
    RedisArgument.text(payload),
    RedisArgument.text('$publishedAtMilliseconds'),
    RedisArgument.text('$oldestRetainedMilliseconds'),
    RedisArgument.text('$maximumHistoryCount'),
    RedisArgument.text(names.channelName),
  ],
  timeout: timeout,
);

final RedisScript<int> upsertPresenceLeaseScript = RedisScript(
  '''
local function key_type(key)
  local result = redis.call('TYPE', key)
  if type(result) == 'table' then return result.ok end
  return result
end
local hash_type = key_type(KEYS[1])
local leases_type = key_type(KEYS[2])
if (hash_type ~= 'none' and hash_type ~= 'hash') or
   (leases_type ~= 'none' and leases_type ~= 'zset') then
  return redis.error_reply('WRONGTYPE unexpected Herald presence key type')
end
local connection_id = ARGV[1]
local user_id = ARGV[2]
local expires_at = tonumber(ARGV[3])
if connection_id == '' or user_id == '' or expires_at == nil or expires_at < 0 or
   expires_at % 1 ~= 0 then
  return redis.error_reply('ERR invalid Herald presence lease')
end
redis.call('HSET', KEYS[1], connection_id, user_id)
redis.call('ZADD', KEYS[2], expires_at, connection_id)
return redis.call('HLEN', KEYS[1])
''',
  (reply) => _decodeResult(() => _decodeInteger(reply)),
);

/// Atomically stores one connection-to-user mapping and its lease expiration.
Effect<int, RunnelError> upsertPresenceLease(
  Runnel redis,
  HeraldFixtureNames names, {
  required String connectionId,
  required String userId,
  required int expiresAtMilliseconds,
  Duration? timeout,
}) => redis.runScript(
  upsertPresenceLeaseScript,
  keys: names.presenceScriptKeys,
  arguments: [
    RedisArgument.text(connectionId),
    RedisArgument.text(userId),
    RedisArgument.text('$expiresAtMilliseconds'),
  ],
  timeout: timeout,
);

final RedisScript<int> removeExpiredPresenceLeasesScript = RedisScript(
  '''
local function key_type(key)
  local result = redis.call('TYPE', key)
  if type(result) == 'table' then return result.ok end
  return result
end
local hash_type = key_type(KEYS[1])
local leases_type = key_type(KEYS[2])
if (hash_type ~= 'none' and hash_type ~= 'hash') or
   (leases_type ~= 'none' and leases_type ~= 'zset') then
  return redis.error_reply('WRONGTYPE unexpected Herald presence key type')
end
local now = tonumber(ARGV[1])
if now == nil or now < 0 or now % 1 ~= 0 then
  return redis.error_reply('ERR invalid Herald lease cutoff')
end
local expired = redis.call('ZRANGEBYSCORE', KEYS[2], 0, now)
for _, connection_id in ipairs(expired) do
  redis.call('HDEL', KEYS[1], connection_id)
  redis.call('ZREM', KEYS[2], connection_id)
end
return #expired
''',
  (reply) => _decodeResult(() => _decodeInteger(reply)),
);

/// Removes every expired connection from both consumer-owned presence structures.
Effect<int, RunnelError> removeExpiredPresenceLeases(
  Runnel redis,
  HeraldFixtureNames names, {
  required int nowMilliseconds,
  Duration? timeout,
}) => redis.runScript(
  removeExpiredPresenceLeasesScript,
  keys: names.presenceScriptKeys,
  arguments: [RedisArgument.text('$nowMilliseconds')],
  timeout: timeout,
);

/// Counts users without collapsing their independently leased connections.
int distinctPresenceUsers(Map<String, String> connections) => connections.values.toSet().length;

/// The observable result of a delivery-path probe.
final class DeliveryProbeResult {
  const DeliveryProbeResult({
    required this.delivered,
    required this.healthBeforeRecovery,
    required this.reconnectRequested,
  });

  final bool delivered;
  final PubSubState healthBeforeRecovery;
  final bool reconnectRequested;
}

/// Consumer-owned probe that exercises normal publication and requests recovery on a stall.
final class DeliveryPathProbe {
  factory DeliveryPathProbe({
    required Effect<int, RunnelError> Function(String channel, String payload) publish,
    required PubSubState Function() health,
    required Effect<void, RunnelError> Function(Duration timeout) reconnect,
  }) => DeliveryPathProbe._(publish, health, reconnect);

  const DeliveryPathProbe._(this._publish, this._health, this._reconnect);

  factory DeliveryPathProbe.forRunnel({
    required Runnel publisher,
    required PubSubSession subscriber,
  }) => DeliveryPathProbe(
    publish: (channel, payload) => publisher.publish(channel, payload),
    health: () => subscriber.state,
    reconnect: (timeout) => subscriber.reconnect(timeout: timeout),
  );

  final Effect<int, RunnelError> Function(String channel, String payload) _publish;
  final PubSubState Function() _health;
  final Effect<void, RunnelError> Function(Duration timeout) _reconnect;

  Effect<DeliveryProbeResult, HeraldConsumerError> check({
    required String channel,
    required String token,
    required Future<bool> Function(String token, Duration timeout) awaitDelivery,
    required Duration deliveryTimeout,
    required Duration reconnectTimeout,
  }) => Effect.build(($) async {
    if (deliveryTimeout <= Duration.zero) {
      throw ArgumentError.value(deliveryTimeout, 'deliveryTimeout', 'must be positive');
    }
    if (reconnectTimeout <= Duration.zero) {
      throw ArgumentError.value(reconnectTimeout, 'reconnectTimeout', 'must be positive');
    }
    await $(_consumer(_publish(channel, token)));
    final delivered = await $(
      consumerFuture(
        () => awaitDelivery(
          token,
          deliveryTimeout,
        ).timeout(deliveryTimeout, onTimeout: () => false),
      ),
    );
    final health = _health();
    if (delivered) {
      return DeliveryProbeResult(
        delivered: true,
        healthBeforeRecovery: health,
        reconnectRequested: false,
      );
    }
    await $(_consumer(_reconnect(reconnectTimeout)));
    return DeliveryProbeResult(
      delivered: false,
      healthBeforeRecovery: health,
      reconnectRequested: true,
    );
  });
}

CoordinatedPublication _decodeCoordinatedPublication(RespValue reply) {
  final values = switch (reply) {
    RespArray(:final values) when values.length == 4 => values,
    _ => throw const FormatException('Expected a four-element publication result.'),
  };
  return CoordinatedPublication(
    position: _decodeInteger(values[0]),
    subscriberCount: _decodeInteger(values[1]),
    streamId: respText(values[2]),
    duplicate: _decodeInteger(values[3]) == 1,
  );
}

int _decodeInteger(RespValue reply) => switch (reply) {
  RespInteger(:final value) => value,
  _ => throw FormatException('Expected an integer, received ${reply.runtimeType}.'),
};

/// The consumer retains a typed storage failure for its own recovery policy.
final class HeraldConsumerError {
  const HeraldConsumerError(this.failure);
  final RunnelError failure;
}

Effect<T, HeraldConsumerError> _consumer<T>(Effect<T, RunnelError> operation) =>
    operation.mapError((error, _) => HeraldConsumerError(error));

/// Adapts a consumer-owned Future; unexpected callback throws remain defects.
Effect<T, HeraldConsumerError> consumerFuture<T>(Future<T> Function() work) => Effect.tryFuture(
  (_) => work(),
  onError: (error, stack, _) => Error.throwWithStackTrace(error, stack),
);

Result<T, RunnelError> _decodeResult<T>(T Function() decode) {
  try {
    return Success(decode());
  } on FormatException catch (error, stack) {
    return Failure(RunnelDecodingError(error.message, cause: error, stackTrace: stack));
  }
}

/// A finite history/live handover that borrows the client and owns its subscriber.
final class HeraldScopedConsumerFixture {
  Effect<HistoryHandoverResult, HeraldConsumerError> recover({
    required Runnel redis,
    required HeraldFixtureNames names,
    required String expectedEpoch,
    required int lastSeenPosition,
    required int liveMessageCount,
    required Effect<HeraldHistoryPage, HeraldConsumerError> readHistory,
  }) => Effect.build(($) async {
    final session = await $.acquireRelease(
      _consumer(redis.openPubSub()),
      release: (session, _) => session.close(),
    );
    await $(_consumer(session.subscribe([names.channelName])));
    final history = await $(readHistory);
    final publications = await $(
      session.events
          .filter((event, _) => event is PubSubMessage)
          .take(liveMessageCount)
          .runCollect()
          .mapError((error, _) => HeraldConsumerError(error)),
    );
    final live = <HeraldEvent>[];
    for (final publication in publications.cast<PubSubMessage>()) {
      final text = $.sync(publication.decodeText().mapError(HeraldConsumerError.new));
      final separator = text.indexOf('|');
      final position = separator < 0 ? null : int.tryParse(text.substring(0, separator));
      if (position == null || position <= 0) {
        return HistoryHandoverResult.reload();
      }
      live.add(
        HeraldEvent(
          epoch: expectedEpoch,
          position: position,
          payload: text.substring(separator + 1),
        ),
      );
    }
    return $(
      HistoryHandoverFixture().recover(
        expectedEpoch: expectedEpoch,
        lastSeenPosition: lastSeenPosition,
        subscribe: (onLive) => Effect.sync((_) {
          live.forEach(onLive);
        }),
        readHistory: () => Effect.succeed(history),
      ),
    );
  });
}

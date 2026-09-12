# Runnel

Runnel is Inframe's internal pure Dart client for one standalone Redis or Valkey primary endpoint.
It supports RESP3 over TCP and trusted TLS, with ACL credentials.

## Quick start

```dart
import 'package:runnel/runnel.dart';

final redis = await Runnel.connect('redis://localhost:6379');
try {
  await redis.set('user:42:name', 'Bhaswanth');
  final name = await redis.get('user:42:name');

  final batch = redis.pipeline();
  final savedName = batch.add(Get('user:42:name'));
  final visits = batch.add(Incr('user:42:visits'));
  final results = await batch.exec();
  print(results.value(savedName)); // String?
  print(results.value(visits)); // int
} finally {
  await redis.close();
}
```

Connections accept `redis://` and `rediss://` URLs with an optional port, percent-encoded ACL
credentials, and a nonnegative database path. For example,
`rediss://user:password@cache.internal:6380/2` selects database 2. Supply a `SecurityContext` to
customize trust or client certificates for TLS.

## Supported commands

Every convenience accepts an optional command timeout. Collection inputs are copied before
transmission, binary inputs retain exact bytes, and returned collections are immutable.

| Family | Commands |
| --- | --- |
| Connection | `ping` |
| Strings and keys | `get`, `getBytes`, `set`, `setBytes`, `mget`, `mset`, `incr`, `incrby`, `decr`, `decrby`, `del`, `unlink`, `exists`, `persist`, `expire`, `pttl`, `type`, `scan` |
| Hashes | `hset`, `hget`, `hmget`, `hgetall`, `hdel`, `hexists`, `hlen`, `hincrby` |
| Sets | `sadd`, `srem`, `sismember`, `smembers`, `scard` |
| Lists | `lpush`, `rpush`, `lpop`, `rpop`, `lrange`, `llen`, `ltrim` |
| Sorted sets | `zadd`, `zrem`, `zcard`, `zscore`, `zincrby`, `zrange`, `zrangeWithScores`, `zrangebyscore`, `zremrangebyscore` |
| Streams | `xadd`, `xrange`, `xrevrange`, `xtrim`, `xlen`, nonblocking `xread` |
| Publishing | `publish`, `publishBytes` |
| Scripts | `runScript`, `evalCommand`, `evalshaCommand` |

`RedisCommand<T>` supports custom nonblocking, one-command/one-reply operations. Runnel rejects
session controls, reply suppression, and known blocking forms on the ordinary executor because
they would break reply ownership. It preserves keys and channels exactly; callers own namespacing
and authorization.

## Pipelines, transactions, and scripts

`pipeline()` sends a prevalidated batch in wire order. `transaction()` uses `MULTI`/`EXEC` on a
dedicated connection. Both return typed `BatchRef<T>` values and retain each entry's success or
failure. Redis transaction errors do not roll back successful commands.

`RedisScript<T>` stores Lua source and a typed decoder. `runScript` tries `EVALSHA`, then sends the
source only after `NOSCRIPT`; both attempts share one deadline. A timeout or connection loss never
triggers fallback. Use `evalCommand` inside a pipeline or transaction so a cold cache cannot move
the script from its batch position. Lua does not roll back writes made before a runtime error, so
callers validate inputs and key types before mutation.

## Dedicated sessions

`openPubSub()` creates one bounded subscriber socket for a changing channel set. `subscribe`
completes after every relevant acknowledgement. The event stream preserves message and lifecycle
order, binary payloads, and connection generations. Network recovery restores the current desired
channels and emits `PubSubInterrupted` followed by `PubSubRestored`; it does not recover missed
publications. A buffer overflow terminates the session so the consumer can replace it and recover
from durable state. `publish` returns Redis's subscriber count, which is not an End User delivery
receipt or persistence proof.

`blocking()` creates a dedicated `BlockingSession` for `blpop`, `brpop`, or blocking `xread`. One
operation may be active on a session. Server wait time must be a positive whole number of
milliseconds. Connection loss or a client deadline terminates the session without replaying the
operation.

Closing the parent closes its Pub/Sub and blocking sessions immediately, releases transaction
connections, and drains ordinary commands within `shutdownTimeout`.

## Failure and resource contracts

Commands accepted while ready are coalesced at the next microtask boundary while retaining order.
A submitted command without a conclusive reply fails with
`RedisDeliveryStatus.outcomeUnknown` and is never replayed. Work attempted during ordinary-client
reconnection fails immediately with `RedisDeliveryStatus.notSent`; Runnel has no offline queue. A
submitted command timeout closes that physical connection so a late reply cannot shift reply
ownership.

Default connection, ordinary-command, Pub/Sub control, and shutdown deadlines are five seconds.
Blocking operations default to their server wait plus the ordinary-command timeout. Per physical
connection, the defaults allow 1,024 pending commands, 16 MiB of pending encoded bytes, 16 MiB per
incoming frame, and 64 aggregate nesting levels. Pub/Sub defaults allow 1,024 undelivered events,
8 MiB of undelivered event data, and 16,384 desired channels. Exact boundaries are accepted.

Runnel reconnects ordinary and Pub/Sub connections with capped full-jitter backoff and repeats the
complete authentication, RESP3, and database handshake. It never replays uncertain operations.

## Topology

Runnel connects to one externally managed primary endpoint. It does not discover Cluster or
Sentinel topology, follow `MOVED` or `ASK` redirects, implement consumer groups, or expose a
Flutter/browser transport. Deployments must provide primary routing and failover outside Runnel.

## Tested compatibility

The integration suite verifies RESP3 over TCP and TLS against:

- Redis 8.2.1, image index digest
  `sha256:5fa2edb1e408fa8235e6db8fab01d1afaaae96c9403ba67b70feceb8661e8621`.
- Valkey 8.1.3, image index digest
  `sha256:fea8b3e67b15729d4bb70589eb03367bab9ad1ee89c876f54327fc7c6e618571`.

Run unit tests with:

```sh
dart test packages/database/runnel/test --exclude-tags integration --chain-stack-traces
```

Run the disposable Docker integration environment with:

```sh
packages/database/runnel/tool/run_integration.sh
```

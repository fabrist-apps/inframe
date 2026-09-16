# Runnel

Runnel is Inframe's internal pure Dart client for one standalone Redis or Valkey primary endpoint.
It supports RESP3 over TCP and trusted TLS, with ACL credentials.

## Quick start

Operations return Conflux `Effect` values. Constructing an Effect captures inputs without opening
sockets, submitting commands, starting deadlines, or changing subscription intent. Run the program
at an explicit application boundary. This example writes to a local or disposable endpoint:

```dart
import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/runnel.dart';

final program = Effect.build<Option<String>, RunnelError>(($) async {
  final redis = await $.acquireRelease(
    Runnel.connect('redis://localhost:6379'),
    release: (redis, _) => redis.close(),
  );
  await $(redis.set('user:42:name', 'Bhaswanth'));
  return $(redis.get('user:42:name'));
});
final exit = await program.runFutureExit();
// The client has been released before this exit is returned.
```

`runFutureExit()` returns `Succeeded` or `Failed` with a Conflux `Cause`. `runFuture()` returns the
value or throws `EffectException`. Plain `Runnel.connect(...).runFuture()` transfers ownership to
the caller; use `try`/`finally` and `await redis.close().runFuture()` if you acquire that way.
Closing a command's scope does not close the client it borrows. Client and session `close()`
Effects have no expected error, but cleanup defects remain visible.

Every run of an ordinary Effect submits fresh work. Running a write twice can apply it twice;
repeated connect runs create independent clients. Sequential binds establish command order.
Deadlines start when each execution is admitted, including time spent waiting locally.

See [the complete example](example/runnel_example.dart) for batch Results and a custom decoder.

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

## Presence and decoding

Missing command values use `Option`: `get`, `hget`, `lpop`, and `rpop` return `Option<String>`;
`getBytes` returns `Option<Uint8List>`; `zscore` returns `Option<double>`. `mget` and `hmget` retain
every position as `List<Option<String>>`. An empty string or byte array is present. Blocking pops
return `None` when their server wait expires without an item. `xread` returns an empty list when
there are no entries. Conditional `set` returns `false` when its condition does not apply, and
`pttl` retains Redis's `-1` and `-2` values.

`Option<T?>` distinguishes absence from a present nullable value:

```dart
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';

Option<String?> missing = const None();
Option<String?> presentNull = const Some(null);
Result<Option<String?>, RunnelError> decoded = Success(presentNull);
Result<String?, RunnelError> nullableSuccess = const Success(null);
```

Neither `Some` nor `Success` converts null to absence. JSON decoding stays caller-owned: mapping
`jsonDecode` over `Some('null')` produces `Some(null)`, while mapping over `None` retains absence.
A custom protocol must encode the distinction if it promises both states.

`RedisCommand<T>` and `RedisScript<T>` decoder callbacks return `Result<T, RunnelError>` and retain
exactly `T`, including nullable values and nested Options. Return `Failure` for expected decoding
errors. Unexpected callback throws remain Conflux defects with their stack traces. Built-in
reply-shape and UTF-8 failures are typed `RunnelDecodingError` values.

## Pipelines, transactions, and scripts

`pipeline()` sends a prevalidated batch in wire order. `transaction()` uses `MULTI`/`EXEC` on a
dedicated connection. Both return typed `BatchRef<T>` values. Inside an Effect program:

```dart
final batch = redis.pipeline();
final name = batch.add(Get('user:42:name'));
final visits = batch.add(Incr('user:42:visits'));
final results = await $(batch.exec());
final savedName = $.sync(results.outcome(name)); // Option<String>
final count = $.sync(results.outcome(visits)); // int
```

`outcome(ref)` returns `Result<T, RunnelError>`. Binding it with `$.sync` propagates an expected
entry failure. When entries can be settled, the batch retains each entry's success or failure;
failures that prevent producing batch results use the outer Effect error channel. Decoder defects
fail the outer Effect after observing the other requests. A reference from another batch is a
programmer error. Redis transaction errors do not roll back successful commands.

Batches are single-use. Calling `exec()` freezes the builder without I/O. Its first execution
claims the batch; repeated or concurrent execution fails with `RunnelUsageError` before submission.
Once claimed, a batch stays consumed after failure or interruption. Build a fresh batch to submit
new work.

`runScript` tries `EVALSHA`, then sends the source only after `NOSCRIPT`; both attempts share one
deadline. A timeout, cancellation, or connection loss never triggers fallback. Use `evalCommand`
inside a pipeline or transaction so a cold cache cannot move the script from its batch position.
Lua does not roll back writes made before a runtime error, so callers validate inputs and key
types before mutation.

## Flows and dedicated sessions

`scan()` returns a cold `Flow<String, RunnelError>`. Each consumption starts at cursor zero,
consumes the current page before requesting another, and stops fetching on early completion.
Redis SCAN can return duplicates and is not a snapshot. Inside an Effect program, collect a bounded
prefix with `await $(redis.scan(match: 'user:*').take(100).runCollect())`.

`openPubSub()` acquires one bounded subscriber socket. Acquire sessions through `$.acquireRelease`
with `(session, _) => session.close()` when their lifetime should end before the parent client's.
`subscribe`, `unsubscribe`, and `reconnect` return Effects; subscribe completes after every relevant
acknowledgement. Reading `session.events` creates no connection or subscription intent.

`events` is a hot `Flow<PubSubEvent, RunnelError>` backed directly by the session's one bounded
queue. Each session permits one successful consumer acquisition during its lifetime. A second
consumer gets `RunnelUsageError` without disturbing the owner. Owner early completion,
cancellation, or scope exit closes the session. Use Flow operations directly; `events.toStream()`
is the explicit Dart Stream boundary, and its subscription must be cancelled when finished.

Events preserve binary payloads, lifecycle order, and connection generations.
`PubSubMessage.decodeText()` returns `Result<String, RunnelError>`; `payload` retains exact bytes.
Network recovery restores current desired channels and emits `PubSubInterrupted` followed by
`PubSubRestored`; it does not recover missed publications. `PubSubInterrupted.error` is `None` for
explicit reconnect without failure and `Some(error)` for failures. Terminal faults release the
socket immediately, discard normal queued publications, deliver one reserved terminal event, then
fail the next pull with the typed error. Normal close completes normally.

`publish` returns Redis's subscriber count. That count does not prove End User delivery or
persistence. A consumer recovering from overflow or a network gap must use its durable state.

`blocking()` acquires a dedicated `BlockingSession` for `blpop`, `brpop`, or blocking `xread`. One
operation may be active on a session. Server wait time must be a positive whole number of
milliseconds. Connection loss, a client deadline, or interruption terminates the session without
replaying the operation; a destructive pop may already have happened.

Closing the parent closes its Pub/Sub and blocking sessions, releases transaction connections,
and drains ordinary commands within `shutdownTimeout`.

## Failure and resource contracts

Expected failures use the sealed `RunnelError` family inside Conflux `Expected`. Unexpected
implementation and callback failures use `Defect`; cancellation uses `Interrupted`. Operation and
cleanup failures can produce combined causes. None of these failures becomes an absent value.

`RunnelError.deliveryStatus` is `Option<RedisDeliveryStatus>`:

| Metadata | Meaning |
| --- | --- |
| `Some(notSent)` | The operation was not submitted. |
| `Some(outcomeUnknown)` | Submission occurred without a conclusive reply. |
| `None` | Delivery metadata is absent or inapplicable, including a conclusive server rejection. |

A received server error is not `notSent` and does not prove rollback. `Interrupted` alone does not
say whether bytes were sent; treat an interrupted write as potentially applied.

Commands accepted while ready are coalesced at the next microtask boundary while retaining order.
Cancellation before submission removes only that request. Cancellation after ordinary submission
closes the physical connection to protect FIFO reply alignment: unanswered submitted siblings fail
with `outcomeUnknown`, and unsent siblings fail with `notSent`. A submitted command timeout also
closes that physical connection. Reconnect never replays these operations.

Work attempted during ordinary-client reconnection fails immediately with `notSent`; there is no
offline queue. Cancelling an admitted Pub/Sub control closes its session and stops restoration;
cancellation before admission leaves the session untouched. Runnel deadlines produce typed timeout
errors. An enclosing Conflux timeout interrupts the work and cannot undo a server write.

Default connection, ordinary-command, Pub/Sub control, and shutdown deadlines are five seconds.
Blocking operations default to their server wait plus the ordinary-command timeout. Per physical
connection, the defaults allow 1,024 pending commands, 16 MiB of pending encoded bytes, 16 MiB per
incoming frame, and 64 aggregate nesting levels. Pub/Sub defaults allow 1,024 undelivered events,
8 MiB of undelivered event data, and 16,384 desired channels. Exact boundaries are accepted.

Runnel reconnects ordinary and Pub/Sub connections with capped full-jitter backoff and repeats the
complete authentication, RESP3, and database handshake. It never replays uncertain operations.

## Implementation reading path

Start with [client.dart](lib/src/client.dart). It owns the ordinary connection, reconnects, and
child-session lifetimes. Follow the operation into its owner:

| Responsibility | Implementation |
| --- | --- |
| Endpoint parsing and handshake commands | [connection/configuration.dart](lib/src/connection/configuration.dart) |
| Socket establishment and cancellation | [connection/socket.dart](lib/src/connection/socket.dart), [connection/connection_attempt.dart](lib/src/connection/connection_attempt.dart) |
| Ordinary command admission, reply order, and pending deadlines | [connection/redis_connection.dart](lib/src/connection/redis_connection.dart) |
| Typed batch results and MULTI/EXEC decoding | [batch.dart](lib/src/batch.dart), [transaction.dart](lib/src/transaction.dart) |
| Subscription intent, control operations, and recovery | [pubsub/session.dart](lib/src/pubsub/session.dart) |
| Pub/Sub socket replies and acknowledgements | [pubsub/transport.dart](lib/src/pubsub/transport.dart) |
| Bounded pull delivery and reserved terminal events | [pubsub/event_queue.dart](lib/src/pubsub/event_queue.dart) |
| Command construction and common reply shapes | [commands/](lib/src/commands/), [commands/reply_decoding.dart](lib/src/commands/reply_decoding.dart) |

The event queue owns retained Pub/Sub events and wakes pending pulls without polling. The session
owns overflow policy, consumer ownership, and channel reconciliation. `Flow.fromPull` consumes the
queue without adding a second buffer.

Commands snapshot arguments at construction. `RedisCommand.encodedLength` measures the exact wire
size without building the encoded command, so batch and subscription admission can check capacity
before allocating transmission buffers. Public binary getters still return owned copies.

Tests share a disposable TCP peer in [test/support/resp_peer.dart](test/support/resp_peer.dart).
Each scenario supplies its own replies, delayed acknowledgements, or disconnect behavior. The peer
parses outgoing commands independently of the production RESP parser.

## Herald consumer boundary

The [Herald fixture](test/fixtures/herald_consumer_fixture.dart) demonstrates the dependency
contract: Herald binds Runnel Effects and maps `RunnelError` into its own error domain. It borrows
the client, owns a dedicated Pub/Sub session, and consumes that session's Flow once. Subscription
acknowledgement precedes history or snapshot reads; the consumer merges buffered publications
and detects epoch, position, or delta-base gaps. Receipts, presence leases, app-scoped names, and
authoritative recovery remain consumer responsibilities. This fixture does not implement Herald.

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

From the repository root, run unit tests with:

```sh
dart test packages/database/runnel/test --exclude-tags integration --chain-stack-traces
```

Run the disposable Docker integration environment with:

```sh
packages/database/runnel/tool/run_integration.sh
```

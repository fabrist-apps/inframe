# ClickHouse

Internal Dart HTTP client for bounded ClickHouse queries and batch inserts. The package targets Dart
servers and is not published.

```dart
import 'package:clickhouse/clickhouse.dart';

final client = ClickHouseClient(
  endpoint: 'http://localhost:8123',
  database: 'analytics',
  username: 'default',
  password: password,
);

try {
  await client.insert(
    table: 'events',
    rows: encodedEvents,
    deduplicationToken: batchId,
  );

  final result = await client.query(
    'SELECT event_name FROM events WHERE app_id = {appId:String}',
    parameters: {'appId': appId},
  );
  print(result.rows);
} finally {
  await client.close();
}
```

SQL declares each parameter type with ClickHouse `{name:Type}` syntax. Parameter values are sent
separately: strings are the actual unquoted values, numbers use their textual representation, and
composites use ClickHouse textual syntax. The server validates declared types. Repositories remain
responsible for App authorization and schema-specific date, time, decimal, and domain conversion.
Quoted large integers and explicitly string-selected decimals remain strings.

`insert` validates and encodes the complete batch as JSONEachRow before it sends a request. The table
argument names one identifier in the configured database, so a dot remains part of the table name.
Successful completion means ClickHouse acknowledged the synchronous insert. It does not establish
that rows were new or replicated everywhere. The optional deduplication token is useful only with a
supporting table engine and settings, inside the configured finite deduplication window. A retry must
preserve both its token and batch contents. The caller owns retries, Kafka offsets, and event-level
deduplication; the client never retries automatically.

Use `command` for SQL without row results, such as migrations scheduled by the consuming service.
Commands also use separate parameter binding and complete after server acknowledgement. A failed
write can have an unknown outcome and does not imply rollback.

## Limits and failures

Requests and responses default to a 16 MiB limit. The request limit counts the encoded body before
compression and excludes headers and URL parameters. The response limit counts decompressed bytes,
including error bodies, while they are consumed. A payload exactly at its limit is accepted. These
limits bound payloads, not the total Dart heap used while validating, encoding, or decoding them.

`ClickHouseException` separates the failure category from whether the request was definitely
`notSent` or `mayHaveReachedServer`. Server, transport, timeout, protocol, and size-limit failures
remain distinct. A failed command or insert marked `mayHaveReachedServer` has an unknown outcome and
may have had partial effects. Failure releases local request resources but does not prove that the
server cancelled work or rolled it back.

## Deadlines and shutdown

The default operation deadline is 30 seconds. A positive `timeout` on `query`, `command`, or
`insert` overrides it for that operation. The deadline covers validation, encoding, request work,
response consumption, and decoding. Synchronous JSON work cannot be interrupted by a timer, so the
client checks elapsed time after encoding and decoding before it sends a request or publishes a
result. This detects overruns but cannot provide a strict wall-clock bound while the isolate is
blocked.

Create one client when a service starts and close it during shutdown. `close` immediately rejects new
operations, lets accepted operations finish under their existing deadlines, then releases the owned
connection pool. Repeated calls await the same shutdown. A local timeout releases that operation's
HTTP resources without claiming server-side cancellation or rollback.

## Tested server

Integration tests target the official `clickhouse:26.8.2.7` image, pinned to the multi-platform
digest `sha256:2c0ce0d50655752e01b859cbbaf275f6c8009be7178e48e9113b060cb472bf25`.

Run the isolated server on a non-production port, then run the integration tests from the repository
root:

```sh
docker run --rm --name inframe-clickhouse-test \
  -p 18123:8123 \
  -e CLICKHOUSE_PASSWORD=test-password \
  clickhouse:26.8.2.7@sha256:2c0ce0d50655752e01b859cbbaf275f6c8009be7178e48e9113b060cb472bf25

CLICKHOUSE_URL=http://127.0.0.1:18123 \
CLICKHOUSE_PASSWORD=test-password \
dart test packages/database/clickhouse/test/integration
```

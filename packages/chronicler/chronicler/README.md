# Chronicler

Chronicler records structured telemetry through the repository's explicit `Context` and delivers
immutable batches through an application-owned exporter.

```dart
import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';

final chronicler = Chronicler(
  appId: 'app_123',
  release: '1.0.0',
  source: ChroniclerSource.server,
  exporter: exporter,
);
final context = Context().withChronicler(chronicler.recorder);

context.logs.info('Order created', attributes: {'orderId': 'order_123'});
```

The application creates the exporter and gives Chronicler exclusive ownership of it. Recording is
synchronous: Chronicler validates and snapshots the payload, then schedules transport work. It never
retains live request objects. The queue is bounded by record count and canonical encoded bytes, and
in-flight records continue to consume that capacity.

The base queue is in memory. Process termination can lose unsent telemetry, so analytics emission is
not durable application storage. Diagnostics use a payload-free callback and exact counters rather
than entering the telemetry path recursively.

## Capture policy and privacy

All signal types are enabled and sampled at 100% by default. Applications must configure consent
before binding the recorder. Logs and ordinary product events can be sampled independently; errors
are retained and metric measurements are aggregated without random sampling.

Before buffering, Chronicler recursively redacts fields whose names contain a configured sensitive
term. Matching is case-insensitive and deliberately broad: the default `auth` term also matches
`author`. A matching map or list value is replaced in full. Applications can replace the defaults,
pass an empty term list, or use the synchronous `beforeRecord` hook to change message text and other
payload content. The built-in rules run again after the hook. Invalid, null, or throwing hook results
drop the record without exposing payload content in diagnostics.

## Delivery outcomes and retries

An exporter completes each attempt with one disposition for the whole batch or one disposition per
submitted event ID. `accepted` means the destination acknowledged the record. `rejected` drops it
permanently, while `retryable` keeps its original event ID and occurrence timestamp and retries it
within the configured attempt limit.

Retries use full-jitter exponential delays. Because a transport can deliver a request before its
result fails or times out, a retry can duplicate delivery outside the process. Destinations should
deduplicate on `eventId`. A timed-out attempt keeps its concurrency slot until `result` completes;
`ExportAttempt.result` must therefore complete only after all transport work for that attempt has
stopped. Cancellation is a prompt, idempotent request and does not itself release the slot.

Collection switches apply synchronously per signal. Disabling a signal discards its queued records
from the in-memory buffer and prevents retries for its in-flight records. Re-enabling permits new
captures but does not revive discarded records or restore retry eligibility to records that were
already in flight. Disabling collection cannot recall data that an exporter may already have sent.
Tracing propagation has its own switch and does not change collection settings.

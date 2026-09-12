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
final request = context.withIdentity(
  userId: authenticatedUser.id,
  sessionId: clientSessionId,
);
request.events.track(
  'purchase_completed',
  properties: {'orderId': 'order_123', 'amountMinor': 1200},
);
await request.trace('checkout', run: (trace) async {
  await trace.span('inventory.reserve', run: (span) async {
    span.tracing.setAttribute('warehouse', 'east');
    span.logs.info('Inventory reserved');
  });
});
final report = await chronicler.flush();
await chronicler.close();
```

The application creates the exporter and gives Chronicler exclusive ownership of it. Recording is
synchronous: Chronicler validates and snapshots the payload, then schedules transport work. It never
retains live request objects. The queue is bounded by record count and canonical encoded bytes, and
in-flight records continue to consume that capacity.

`withIdentity` derives a new Context for analytics attribution. It replaces the complete identity,
so omitted user, anonymous, and session IDs are cleared. The original Context and sibling request
contexts remain unchanged. Pass the returned Context downstream. Chronicler accepts caller-supplied
IDs without generating, persisting, expiring, or authenticating them; authentication remains an
application concern. Calling `withIdentity()` clears attribution on the derived Context and emits no
record.

Identity assignment and anonymous-to-user linking are separate operations. Client integration can
emit a link explicitly, then pass a newly derived Context for subsequent records:

```dart
context.events.identify(anonymousId: anonymousId, userId: userId);
final identified = context.withIdentity(userId: userId, sessionId: sessionId);
```

The link is scoped to the configured App and travels through normal bounded delivery. It expresses
association intent for downstream processing; it does not mutate any Context, merge accounts,
authenticate the supplied IDs, or confirm that stored history has been updated.

User-property updates also name their target explicitly:

```dart
context.events.setUserProperties(
  userId: userId,
  properties: {'plan': 'pro', 'companySize': 12},
);
context.events.unsetUserProperties(
  userId: userId,
  keys: ['companySize'],
);
```

A set operation replaces only the supplied keys when processed. Omitted keys remain untouched, and
null is a stored value rather than deletion intent. An unset operation explicitly removes its keys,
collapsing duplicates in first-appearance order. Sensitive names such as `password` remain intact in
the removal list. Empty updates are no-ops. Updates use bounded event delivery but bypass random
sampling; enqueueing does not confirm a stored profile change.

The defaults retain up to 5,000 records or 8 MiB, export batches of up to 100 records or 512 KiB
within five seconds, run one export at a time, and make five total attempts. An attempt times out
after ten seconds. `ChroniclerOptions` can change those bounds, sampling, redaction, diagnostics,
signal collection, and tracing behavior during construction.

The base queue is in memory. Process termination can lose unsent telemetry, so analytics emission is
not durable application storage. Diagnostics use a payload-free callback and exact counters rather
than entering the telemetry path recursively.

## Metric instruments

Metric instruments are shared by the Chronicler runtime, so request Contexts contribute to the same
bounded interval aggregates without adding request identity as a dimension. Repeating a compatible
lookup returns the registered instrument:

```dart
final completed = context.metrics.counter('orders.completed', unit: 'orders');
completed.add(1, attributes: {'channel': 'mobile'});
final active = context.metrics.upDownCounter('connections.active');
active.add(1);
active.add(-1);
final depth = context.metrics.gauge('queue.depth');
depth.set(42);
final latency = context.metrics.histogram(
  'request.duration',
  unit: 'ms',
  boundaries: [10, 50, 100, 250, 500, 1000],
);
latency.record(125);
```

Counters export nonnegative changes measured during each interval rather than lifetime totals. The
default interval is ten seconds. Recording zero still produces an aggregate, while an interval with
no measurements produces none. Metric measurements are aggregated without random sampling.

Names and units are case-sensitive. Values use finite double precision, so large integer inputs may
be approximate and business-critical accounting belongs in application storage. Dimensions accept
bounded strings, booleans, and portable finite numbers. Attribute order, `1` versus `1.0`, and signed
zero select the same series. Chronicler validates and redacts dimensions before series selection;
different sensitive values replaced by `[REDACTED]` therefore intentionally share a series. The
configured total and per-instrument series limits reject new dimensions while existing series remain
usable.

Up/down counters accept signed changes and export their interval net change, including an observed
zero when changes cancel. They do not represent an absolute current count. Setter gauges do: each
series exports its latest accepted value and observation time for the interval. A gauge value is not
repeated in later intervals, so applications call `set` periodically when regular observations are
needed. Callback and automatically polled gauges are not part of the base SDK.

Histograms require at least one finite, strictly increasing boundary chosen for the measured value.
Each boundary is an inclusive upper bound; values above the final boundary enter an overflow bucket.
Every measured interval exports immutable bucket counts, total count, sum, minimum, and maximum.
Chronicler supplies no implicit bucket ranges, and repeated lookup cannot change registered boundaries.

`flush()` closes the current partial metric interval before taking its delivery snapshot. New
measurements immediately enter a fresh full interval and cannot extend that flush. `close()` seals
the final partial interval after blocking new recording, then sends it through the same bounded
shutdown path. Retries keep the finalized aggregate ID, interval boundaries, and contents unchanged.

Disabling metric collection discards queued metric records and unfinished aggregates. Existing
instrument handles remain valid; re-enabling starts a fresh empty interval and accepts only new
measurements. A timer superseded by a flush or collection change cannot finalize the old interval.

Active series are bounded separately from finalized delivery records. A series becomes idle after
five minutes by default, measured from its last accepted observation with monotonic time. Chronicler
checks for expired series at interval boundaries and before admitting a new series, finalizes any
pending observation, then releases that aggregation state. Invalid observations and instrument
lookup do not refresh the deadline. Queue or policy rejection of the final aggregate does not restore
the expired state, and the registered instrument handle can create fresh state later within capacity.

## Error occurrences

Capture an error occurrence explicitly when an application boundary handles or observes it:

```dart
try {
  await reserveInventory();
} catch (error, stackTrace) {
  context.errors.capture(
    error,
    stackTrace: stackTrace,
    causes: [
      ChroniclerCause(databaseError, stackTrace: databaseStackTrace),
    ],
    attributes: {'feature': 'checkout'},
  );
}

context.errors.capture(
  unhandledError,
  stackTrace: unhandledStackTrace,
  handled: false,
);
```

Capture accepts any Dart `Object` and converts its type, message, and optional supplied stack before
returning. It does not inspect object fields, discover causes, generate a missing stack, or retain the
original error object. The raw stack text is preserved with configured release, optional build ID,
identity, session, and trace correlation. Error occurrences are distinct from error-level logs and
failed spans; neither creates an occurrence automatically.

Supply causes explicitly from the immediate cause to the deepest cause. Chronicler preserves their
order and repetitions, snapshots their converted text during capture, and does not walk application
error objects for an implicit chain. By default, root and cause messages are limited to 8 KiB of
UTF-8, stacks to 16 KiB, and a chain to four causes after the root. Exceeding a field, chain, or
complete-record limit drops the whole occurrence without truncation.

Errors bypass random sampling but still obey collection, validation, redaction, queue, and delivery
limits. A capture call creates a new occurrence ID, while retries preserve its ID, timestamp, and
payload. The base SDK does not group or deduplicate occurrences, upload source maps, or install
platform error hooks.

## Tracing and propagation

`trace` and `traceSync` create explicit trace boundaries. `span` and `spanSync` create a child of
the active span, or a new root when no span is active. Each wrapper passes a derived Context to its
callback, records the callback's monotonic duration, and preserves its result or original failure.
Escaping failures become Error unless `TracingOptions.isCancellation` classifies them as Cancelled.
Use `context.tracing.setError()` for a handled failure and `setAttribute` or `setAttributes` for
atomic active-span updates. Chronicler ends spans when callbacks finish; there is no manual span
lifecycle.

Use W3C Trace Context at a transport boundary without giving headers identity or authorization
meaning:

```dart
final parent = TracePropagation.extract(requestHeaders);
await context.trace(
  'POST /orders',
  parent: parent,
  kind: SpanKind.server,
  run: (server) => server.span(
    'payments.create',
    kind: SpanKind.client,
    run: (client) => sendPayment(client.tracing.inject(outgoingHeaders)),
  ),
);
```

`inject` returns a mutable copy, removes stale trace headers case-insensitively, and inserts lowercase
`traceparent` and valid `tracestate` for the active span. The input map is unchanged. Incoming
sampling is honored by default; set `honorRemoteSampling` to false to use the local trace rate while
keeping valid remote correlation.

Trace sampling is chosen once at a root and inherited by descendants. Unsampled or collection-
suppressed traces still run callbacks and keep lightweight IDs for propagation and independently
captured logs, events, and errors. Disabling trace collection discards queued spans and permanently
suppresses active lineages, even after re-enablement. New trace boundaries use the current policy.
Propagation has its own runtime switch and can remain enabled while span collection is disabled.

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

## Flush reports

`flush()` snapshots the records currently queued or in flight and asks the existing worker to drain
that fixed set. Records captured after the call do not extend it. Concurrent calls keep separate
snapshots and deadlines while sharing the same worker. If a flush deadline expires, unresolved
records are reported as `pending` and remain under the normal queue, collection, and retry rules.

`DeliveryReport.accepted` counts destination acknowledgements. `dropped` groups terminal discards by
`DropReason`, and `uncertainDropped` counts the subset whose earlier attempt may have delivered data.
`pending` remains a separate unresolved disposition. `timedOut` refers to the flush or close deadline,
while `cleanupIncomplete` is reserved for incomplete shutdown cleanup. Every report is an immutable
snapshot and does not change when a late exporter result arrives.

## Exporter ownership and shutdown

The application supplies a cancelable exporter. Each result must settle only after that attempt has
stopped all transport work, including after cancellation:

```dart
final class AppExporter implements ChroniclerExporter {
  AppExporter(this.transport);

  final TelemetryTransport transport;

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    final operation = transport.send(batch);
    return AppExportAttempt(operation.result, operation.cancel);
  }

  @override
  Future<void> close() => transport.close();
}

final class AppExportAttempt implements ExportAttempt {
  AppExportAttempt(this.result, this._cancel);

  @override
  final Future<ExportResult> result;
  final void Function() _cancel;
  var _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}
```

Cancellation must abort transport work and settle the attempt's result. Until settlement, the attempt
retains its concurrency slot and record capacity so a retry cannot overlap it. An exporter that never
settles can therefore exhaust delivery capacity; `flush()` reports pending records within its timeout.
The SDK cannot forcibly stop application I/O. The exporter must also support `close()` while attempts
are unresolved, and Chronicler bounds the cleanup wait with its total shutdown deadline.

The component that creates Chronicler also calls `close()`. Closing blocks new application records,
seals internal finalization state, attempts final delivery, and invokes the exporter cleanup exactly
once. Repeated calls return the same future. The default ten-second total budget reserves two seconds
for cleanup; if delivery finishes early, cleanup receives the remaining time. A shutdown report marks
unresolved records as dropped and sets `cleanupIncomplete` when exporter work or resources remain at
the total deadline. Recording after shutdown is a non-throwing diagnostic drop, while configuration
changes after shutdown starts throw `ChroniclerConfigurationException`.

## Implementation reading path

Start with [`lib/chronicler.dart`](lib/chronicler.dart) for the supported API and
[`src/context_integration.dart`](lib/src/context_integration.dart) for Context bindings.
[`src/runtime.dart`](lib/src/runtime.dart) defines the owner and borrowed recorder API.
Its internal implementation is organized by responsibility:

| Responsibility | Implementation |
| --- | --- |
| Capture policy and runtime coordination | [`runtime/capture.dart`](lib/src/runtime/capture.dart) |
| Configuration validation and snapshots | [`runtime/configuration.dart`](lib/src/runtime/configuration.dart) |
| Trace lifetimes, sampling, and active span state | [`runtime/tracing.dart`](lib/src/runtime/tracing.dart) |
| Record validation, redaction, and application hooks | [`runtime/record_processing.dart`](lib/src/runtime/record_processing.dart) |
| Queue capacity, retries, flush snapshots, and exporter shutdown | [`runtime/delivery_queue.dart`](lib/src/runtime/delivery_queue.dart) |
| Instrument registry and interval aggregation | [`metrics/aggregation.dart`](lib/src/metrics/aggregation.dart) |

[`src/codec.dart`](lib/src/codec.dart) owns canonical record encoding. Its
[`codec/record_decoder.dart`](lib/src/codec/record_decoder.dart) parses untrusted bytes, and
[`codec/record_schema.dart`](lib/src/codec/record_schema.dart) enforces the model contract in both
directions. [`src/record_validation.dart`](lib/src/record_validation.dart) handles bounded attribute
snapshots and Unicode validation shared by capture, metrics, and the codec.

[`src/models.dart`](lib/src/models.dart) keeps the sealed record family and mapped payloads with their
generated mapper library. The handwritten codec defines the version-one wire format; generated
mapping supports model operations such as copying and equality.

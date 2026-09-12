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
final report = await chronicler.flush();
await chronicler.close();
```

The application creates the exporter and gives Chronicler exclusive ownership of it. Recording is
synchronous: Chronicler validates and snapshots the payload, then schedules transport work. It never
retains live request objects. The queue is bounded by record count and canonical encoded bytes, and
in-flight records continue to consume that capacity.

The defaults retain up to 5,000 records or 8 MiB, export batches of up to 100 records or 512 KiB
within five seconds, run one export at a time, and make five total attempts. An attempt times out
after ten seconds. `ChroniclerOptions` can change those bounds, sampling, redaction, diagnostics,
signal collection, and tracing behavior during construction.

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

The component that creates Chronicler also calls `close()`. Closing blocks new application records,
seals internal finalization state, attempts final delivery, and invokes the exporter cleanup exactly
once. Repeated calls return the same future. The default ten-second total budget reserves two seconds
for cleanup; if delivery finishes early, cleanup receives the remaining time. A shutdown report marks
unresolved records as dropped and sets `cleanupIncomplete` when exporter work or resources remain at
the total deadline. Recording after shutdown is a non-throwing diagnostic drop, while configuration
changes after shutdown starts throw `ChroniclerConfigurationException`.

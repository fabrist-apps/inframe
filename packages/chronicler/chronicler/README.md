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

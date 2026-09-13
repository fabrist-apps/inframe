# Chronicler for Conflux

`chronicler_conflux` records scoped Conflux Effect lifetimes as Chronicler
spans. The adapter borrows the recorder already registered in the execution
`Context`.

```dart
final chronicler = Chronicler(
  appId: 'checkout',
  release: '1.0.0',
  source: ChroniclerSource.server,
  exporter: exporter,
);
final runtime = Runtime(
  context: Context().withChronicler(chronicler.recorder),
);

final checkout = Effect.build<Order, CheckoutError>(($) async {
  $.context.logs.info('Checkout started');
  return $(reserveInventory().withSpan('inventory.reserve'));
}).withSpan('checkout');

final exit = await runtime.run(checkout);
await runtime.close();
await chronicler.close();
```

`withSpan` creates a child of the active span, or a root when none is active.
Use `withRootSpan` for an explicit trace boundary or to continue a validated
`RemoteTraceParent`.

Each wrapper creates a child resource scope. Resources acquired inside the
wrapper finish before its span ends. Expected errors and defects end the span
as `Error`; an interruption-only cause ends it as `Cancelled`. The wrapper
preserves the Effect's value or complete Cause and does not automatically
capture an error occurrence.

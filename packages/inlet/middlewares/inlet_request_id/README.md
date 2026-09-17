# inlet_request_id

Generates a fresh ChronoID for each Inlet request and attaches it to the downstream context, request headers, and returned response headers.

```dart
import 'package:inlet/inlet.dart';
import 'package:inlet_request_id/inlet_request_id.dart';

final app = Inlet()
  ..use(requestId)
  ..get('/', (context, request) {
    return Response.json({'requestId': context.requestId});
  });
```

Register `requestId` before middleware that needs the ID. The `x-request-id` header replaces any incoming ID and any ID set on a downstream response. Each invocation generates its own ID. The original context and request remain unchanged; request and response bodies retain their existing ownership and streaming behavior.

For tracing, register [httpTracing](../inlet_tracing/README.md) before `requestId`.
When Chronicler is bound, request ID middleware adds the generated ID to the
active span with `setAttribute('requestId', id)`. Without an active span,
Chronicler records a `noActiveSpan` diagnostic without throwing. Without a
Chronicler binding, the attribute update is skipped. Optional consumers can read
`context.requestIdOrNull`, which returns null before the middleware runs.

`context.requestId` throws `MissingContextValue` when the middleware has not run. Uncaught errors propagate to Inlet's application error handler, whose response bypasses middleware unwinding. To include the ID on those responses, attach it in `onError`:

```dart
final app = Inlet(
  onError: (context, request, error, stackTrace) => Response.empty(
    status: 500,
    headers: const Headers.empty().set('x-request-id', context.requestId),
  ),
)..use(requestId);
```

From the workspace root:

```sh
dart test packages/inlet/middlewares/inlet_request_id/test --chain-stack-traces
```

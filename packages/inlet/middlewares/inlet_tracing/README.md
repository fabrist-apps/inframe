# inlet_tracing

Chronicler server spans for Inlet HTTP request handling. Each invocation starts
an explicit trace boundary and passes the span's context to downstream handlers.

Configure a Chronicler runtime and register tracing before request ID middleware:

```dart
import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:inlet/inlet.dart';
import 'package:inlet_request_id/inlet_request_id.dart';
import 'package:inlet_tracing/inlet_tracing.dart';

Inlet createApp(Chronicler chronicler) => Inlet(
  context: Context().withChronicler(chronicler.recorder),
)
  ..use(httpTracing)
  ..use(requestId)
  ..get('/items/:id', (context, request) {
    context.logs.info('Item requested');
    return Response.json({'id': request.pathParameters['id']});
  });
```

The application calls `Chronicler.initialize()` at startup and owns flushing and
closing its Chronicler runtime. Without a bound recorder, `httpTracing` forwards
requests without tracing. Request ID middleware is optional; when omitted, no
`requestId` attribute is recorded. Incoming request ID headers alone are not used.

## Recorded data

The span name is the method and matched route template, such as
`GET /items/:id`. Unmatched requests use only the method. Inlet exposes the
matched template through `Request.routeTemplate`, including mount prefixes.

| Attribute | Value |
| --- | --- |
| `http.request.method` | Request method |
| `http.route` | Matched route template, when available |
| `http.response.status_code` | Status returned by downstream middleware or handler |
| `requestId` | Added to the active span by downstream request ID middleware |

Logs and child spans created with the supplied context share the trace. Returned
5xx responses mark the server span as failed; returned 4xx responses do not.
Thrown errors propagate unchanged and use Chronicler's failure classification.
Raw URLs, query strings, headers, bodies, and exception messages are not captured.

## Propagation

Valid `chronicler-trace-id`, `chronicler-span-id`, and `chronicler-sampled` headers
continue a remote parent, including its sampling decision. Missing, malformed,
or repeated propagation headers cause a new trace to start. An unrelated span
already bound to the application context is not used as the HTTP request parent.

These are Chronicler's correlation headers, not W3C `traceparent` / `tracestate`.
The middleware does not add response propagation headers. Handlers can use
`context.tracing.inject(headers)` for outgoing requests.

## Lifetime and errors

The span measures downstream handler work and ends when that work returns or
throws. It does not consume response bodies or measure streaming delivery, SSE
subscriptions, or WebSocket sessions.

Inlet's outer error handler runs after middleware unwinds. An escaped error marks
the span as failed, but the later error response status is unavailable and is
omitted. Transport finalization can also change a returned status, for example
when rejecting a WebSocket handshake. The recorded status describes the response
seen by this middleware, not necessarily the final wire response.

From the workspace root:

```sh
dart test packages/inlet/middlewares/inlet_tracing/test --chain-stack-traces
```

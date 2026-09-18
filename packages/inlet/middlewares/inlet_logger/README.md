# inlet_logger

Terminal output and structured Chronicler logs for completed Inlet dispatches.
Register `logger()` early to include short circuits and error recovery:

```dart
import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:inlet/inlet.dart';
import 'package:inlet_logger/inlet_logger.dart';
import 'package:inlet_request_id/inlet_request_id.dart';
import 'package:inlet_tracing/inlet_tracing.dart';

Inlet createApp(Chronicler chronicler) => Inlet(
  context: Context().withChronicler(chronicler.recorder),
)
  ..use(logger())
  ..use(httpTracing)
  ..use(requestId)
  ..get('/items/:id', (context, request) => Response.empty());
```

The application initializes and owns its Chronicler runtime. Tracing and request
ID middleware are optional. Place CORS after the logger to include preflights.

## Terminal output

Terminal logging is enabled by default and works without a Chronicler recorder:

```text
┌─ HTTP 200 GET /items/:id
│ 2026-09-18T10:30:00.000Z · 1.42 ms
│ requestId: req_...
└─
```

Status colors are green for 1xx/2xx, cyan for 3xx, yellow for 4xx, and red for
5xx. Colors are enabled automatically when stdout supports ANSI, unless
`NO_COLOR` is present. Redirected output is plain text. UTC timestamps show
completion time. Durations measure dispatch time, and unmatched requests print
`<unmatched>` rather than their raw path. Control characters in metadata are escaped.

Durations display as whole microseconds below 1 ms, milliseconds below 1 second,
and seconds thereafter. Milliseconds and seconds use two decimal places.
Chronicler's `durationMicros` remains an integer in microseconds.

Disable terminal output when only structured logs are wanted:

```dart
app.use(logger(console: false));
```

`console` is the only option. Colors follow stdout ANSI support and `NO_COLOR`.
Chronicler logging follows `context.hasChronicler`, independently of `console`.
Neither stdout nor Chronicler recorders are flushed or closed by the middleware.

## Chronicler output

The informational `HTTP request completed` record contains:

| Attribute | Value |
| --- | --- |
| `http.request.method` | Request method |
| `http.route` | Matched route template, when available |
| `http.response.status_code` | Status after dispatch error recovery and HEAD finalization |
| `requestId` | Bound request ID, when available |
| `durationMicros` | Monotonic microseconds from middleware entry to response hook execution |

The latest forwarded context supplies the logger and request ID, preserving trace
correlation. Without a recorder, only terminal output runs. Logs remain independent of
trace sampling; Chronicler log collection, filtering, and delivery policies apply.
Raw URLs, query strings, headers, request/response bodies, and exception messages
are not recorded.

The response hook runs once before delivery and does not consume the body.
Duration excludes streamed delivery and WebSocket sessions. Status reflects the
completed dispatch, not later transport recovery or WebSocket negotiation.
Synchronous terminal output failures still allow Chronicler logging; callback
failures are reported by Inlet without changing the response.
Register the middleware once per chain to avoid duplicate records.

From the workspace root:

```sh
dart test packages/inlet/middlewares/inlet_logger/test --chain-stack-traces
dart run packages/inlet/middlewares/inlet_logger/example/logger_example.dart
```

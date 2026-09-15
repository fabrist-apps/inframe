# Inlet

Inlet routes the same Dart handler in process or through an HTTP/TLS listener. It supports scoped middleware, bounded request bodies, streaming responses, server-sent events, and WebSockets.

## Start here

From the repository root, run a complete example:

```sh
dart run packages/inlet/example/inlet_example.dart
```

Register routes before the first dispatch or successful listener bind:

```dart
import 'package:inlet/inlet.dart';

final app = Inlet()
  ..post('/echo', (_, request) async {
    final value = await request.json(maxBytes: 64 * 1024);
    return Response.json(value);
  });

final server = await app.serve(port: 0);
try {
  print('Listening on http://${server.address.address}:${server.port}');
  // Keep application work inside this lifetime.
} finally {
  await server.close();
}
```

HTTP defaults to `127.0.0.1:8080`. `serveSecure` takes a `SecurityContext` and defaults to port 8443. A failed first bind leaves registration editable.

## Ownership

The HTTP adapter closes network requests and responses. In-process callers own both: close the response before its request, since a response may stream from the request body.

```dart
final request = Request(
  method: 'POST',
  uri: Uri.parse('/echo'),
  body: Stream.value([123, 125]), // {}
);
Response? response;
try {
  response = await app.handle(request);
  print(await response.json());
} finally {
  try {
    await response?.close();
  } finally {
    await request.close();
  }
}
```

Body buffering defaults to 1 MiB. The first buffering call selects the physical read limit; later readers share that read and enforce their own limits. Raw streaming and buffering are exclusive. Closing an untouched body does not subscribe to it.

A normal listener close stops admission without waiting for handlers. A later `close(force: true)` closes active HTTP and SSE connections. Upgraded WebSockets remain application-owned. See [InletServer.close](lib/src/transport/server.dart) for shutdown semantics.

## Routes and middleware

Literal segments precede `:parameters`, then final `*wildcards`. `Inlet(strict: false)` ignores one trailing slash. `route` snapshots a child's registrations and middleware under a prefix:

```dart
final documents = Router()
  ..get('/:documentId', (_, request) => Response.json(request.pathParameters));
final app = Inlet()..route('/api/:tenant/documents', documents);
```

Middleware enters root, mounted-child, and route scopes, then unwinds in reverse. Forward context derivations and request header views explicitly with `next(context, request)`. Call `next` at most once while the invocation is active, and await or return its work. Returning without calling it is allowed.

Malformed UTF-8 or JSON defaults to an empty 400 response; request body limits to 413; unexpected escaped errors to 500. `onError` can replace those responses. `onReportError` observes unexpected failures. Delivery failures can be recovered only before the response commits.

## Live responses

- `Response.stream(bytes)` stays lazy after handler completion. Keep its resources alive through delivery or cancellation.
- `Response.sse(events)` encodes typed events and flushes each event over HTTP. Producers own heartbeats, replay, and slow-client policy.
- `Response.webSocket(onConnect: ...)` upgrades a GET request. The callback owns the entire session and must stay pending while the socket is in use. Acquire session resources inside that callback, after middleware has unwound.

See [Response](lib/src/response.dart) for headers, limits, negotiation, and lifecycle contracts, and [SseEvent](lib/src/sse_event.dart) for event encoding. Runnable examples:

```sh
dart run packages/inlet/example/stream_transfers.dart
dart run packages/inlet/example/live_events.dart
dart run packages/inlet/example/web_socket_chat.dart
```

The examples use ephemeral listeners or in-process dispatch and release their resources before exiting.

## Implementation reading path

[Inlet](lib/src/inlet.dart) resolves a route, runs middleware, and applies error recovery. [Router](lib/src/router.dart) owns registration and its private route trie. [Body](lib/src/body.dart) owns application consumption; the separate [HTTP request body](lib/src/transport/request_body.dart) owns the physical upload subscription.

Network delivery starts in [server.dart](lib/src/transport/server.dart), which binds listeners and admits [HTTP exchanges](lib/src/transport/http_exchange.dart). Each exchange owns commit state and response cleanup. [SSE connections](lib/src/transport/sse.dart) and [WebSocket sessions](lib/src/transport/web_socket.dart) own their respective transport lifetimes.

The public entrypoint exports only supported API types. Internal runtime extensions connect ordinary libraries without exposing those operations to package consumers.

## Verify

From the repository root:

```sh
dart test packages/inlet/test --chain-stack-traces
dart analyze packages/inlet --fatal-infos
```

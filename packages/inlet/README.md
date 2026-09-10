# Inlet

Inlet routes the same Dart handler in process or through an HTTP/TLS listener. It provides immutable request metadata, scoped middleware, bounded body buffering, and lazy byte streams without application-level retries or automatic compression.

## JSON endpoint

```dart
import 'dart:convert';

import 'package:context/context.dart';
import 'package:inlet/inlet.dart';

final app = Inlet()
  ..post('/echo', (_, request) async {
    final value = await request.json(maxBytes: 64 * 1024);
    return Response.json(value);
  });
```

In-process callers own both sides of the exchange. Close the response before the request so a response may stream from its request body:

```dart
final request = Request(
  method: 'POST',
  uri: Uri.parse('/echo'),
  body: Stream.value(utf8.encode('{"message":"hello"}')),
);
Response? response;
try {
  response = await app.handle(request);
  print(await response.json());
} finally {
  await response?.close();
  await request.close();
}
```

The HTTP adapter owns network requests and responses. The application owns the returned listener:

```dart
final server = await app.serve(port: 0);
try {
  print('Listening on http://${server.address.address}:${server.port}');
} finally {
  await server.close();
}
```

`serve` defaults to `127.0.0.1:8080`. `serveSecure` accepts a `SecurityContext` and defaults to `127.0.0.1:8443`. Both accept an explicit address, port, backlog, shared binding, and nullable keep-alive idle timeout. A normal close stops admission and leaves active connections to finish. A later `close(force: true)` closes that listener's active connections. Repeated calls return the first close future.

## Routes and middleware

Literal segments take precedence over `:parameters`, then final `*wildcards`. Strict routing distinguishes a trailing slash; create `Inlet(strict: false)` to ignore one trailing slash. Mount a prepared child router with `route`:

```dart
final documents = Router()
  ..get('/:documentId', (_, request) {
    return Response.json(request.pathParameters);
  });

final app = Inlet()
  ..route('/api/:tenant/documents', documents);
```

Middleware enters from the root through mounted child scopes and route middleware, then unwinds in reverse. Forward immutable context derivations and request views explicitly:

```dart
final requestIdKey = ContextKey<String>('request ID');

app.use((context, request, next) {
  final requestId = request.headers['x-request-id'] ?? 'local';
  return next(
    context.withBinding(requestIdKey.bind(requestId)),
    request,
  );
});
```

Call `next` at most once while that middleware invocation is active. A middleware may return early without calling it.

## Bodies and errors

`Request.bytes`, `text`, and `json` share one buffered source read and default to a 1 MiB limit. The first buffering call selects the physical limit; each caller still enforces its own limit. Raw streaming and buffering are exclusive.

Malformed UTF-8 or JSON maps to an empty 400 response. A selected request limit maps to empty 413. Other escaped failures map to empty 500 and are reported. `onError` may replace any of those responses.

`Response.stream` stays lazy through handler completion. Keep resources needed by the stream alive until delivery completes or its subscription is cancelled. HEAD, 204, 205, and 304 responses never subscribe to a suppressed source.

## Public API

`package:inlet/inlet.dart` exposes `Inlet`, `Router`, `Request`, `Response`, `Headers`, `ConnectionInfo`, `InletServer`, the handler and middleware callback types, and the request/response body-limit exceptions. Server-sent events and WebSockets are not part of this core API.

## Run the package

From `packages/inlet` in the repository workspace:

```sh
dart run example/inlet_example.dart
dart run example/stream_transfers.dart
dart test
dart analyze --fatal-infos
```

The examples use ephemeral listeners or in-process dispatch and exit after releasing their resources.

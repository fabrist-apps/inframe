# Inlet

Inlet routes the same Dart handler in process or through an HTTP/TLS listener. It provides immutable request metadata, scoped middleware, bounded body buffering, lazy byte streams, server-sent events, and WebSocket sessions without application-level retries or automatic compression.

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
  try {
    await response?.close();
  } finally {
    await request.close();
  }
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

`serve` defaults to `127.0.0.1:8080`. `serveSecure` accepts a `SecurityContext` and defaults to `127.0.0.1:8443`. Both accept an explicit address, port, backlog, shared binding, and nullable keep-alive idle timeout. A normal close stops admission and leaves active connections to finish. Its future marks the listener admission boundary, not completion of application handlers. A later `close(force: true)` closes that listener's active connections. Repeated calls return the first close future.

## Server-sent events

Return `Response.sse` from a route to deliver typed events and comments:

```dart
Stream<SseEvent> documentUpdates() async* {
  yield SseEvent.json(
    {'title': 'Ready'},
    event: 'document',
    id: 'event-1',
  );
  await Future<void>.delayed(const Duration(seconds: 15));
  yield SseEvent.comment('keep-alive');
}

final app = Inlet()
  ..get('/events', (_, _) => Response.sse(documentUpdates()));
```

`SseEvent` supports text data, immediate JSON snapshots, event names, IDs, whole-millisecond retry delays, and single-line comments. Data line endings are normalized to LF and empty data lines and IDs remain explicit in the wire format. Event names and IDs reject CR, LF, and NUL. Comments reject CR and LF.

An SSE response always has status 200 and `text/event-stream; charset=utf-8`. It adds `cache-control: no-cache` only when the supplied headers contain no cache policy. SSE rejects content encoding and caller-owned framing headers. `withHeaders` restores the canonical SSE headers and keeps the same delivery policy and source owner.

In-process delivery emits one complete encoded event or comment per body chunk. The usual response buffering limit and raw-versus-buffered exclusivity still apply. Over HTTP, Inlet flushes headers before subscribing, then writes and flushes one complete event before requesting the next one. A successful socket flush cannot guarantee that a proxy or browser has already delivered the event.

The event producer owns heartbeat timing, replay and `Last-Event-ID` handling, event limits, resources, and any slow-consumer policy beyond transport backpressure. Inlet adds no replay store, output queue, automatic heartbeat, compression, or cancellation deadline. Pause, resume, cancellation, disconnects observed by Dart, and source failures propagate through the event subscription. Cleanup still depends on the producer cooperating with cancellation; Inlet cannot interrupt an arbitrary pending future.

HEAD returns the SSE headers without subscribing to the source. Closing an untouched response also avoids subscription. Return an ordinary `Response.empty()` with status 204 when an EventSource client should stop reconnecting.

## WebSocket sessions

Return `Response.webSocket` from a GET route. The callback owns the complete session and must remain pending while application code uses the socket:

```dart
import 'dart:io';

import 'package:inlet/inlet.dart';

final sessions = <WebSocket>{};

final app = Inlet()
  ..get('/chat', (_, request) {
    if (request.headers['origin'] != 'https://app.example.com') {
      return Response.empty(status: HttpStatus.forbidden);
    }
    return Response.webSocket(
      selectProtocol: (offered) {
        if (offered.contains('chat.v1')) return 'chat.v1';
        throw const WebSocketException('chat.v1 is required.');
      },
      maxFrameBytes: 64 * 1024,
      onConnect: (socket) async {
        sessions.add(socket);
        try {
          await socket.forEach(socket.add);
        } finally {
          sessions.remove(socket);
        }
      },
    );
  });
```

Inlet invokes a supplied selector once with an immutable ordered list, including an empty list. Return `null` to negotiate no subprotocol. A selected value must exactly match an offered token. Invalid offered tokens and a selector's `WebSocketException` default to empty 400 responses; unoffered results and other selector failures use the normal error boundary and default to 500. `onError` can replace a preflight rejection with an ordinary response, but cannot recursively return another upgrade intent.

Compression is off by default. `maxFrameBytes` defaults to 1 MiB and controls Dart's incoming uncompressed frame payload limit. It is not a total fragmented-message or connection-memory limit because Dart may assemble messages before delivering them.

When `onConnect` completes, Inlet closes an open socket with code 1000. If it fails, Inlet reports the error and closes an open socket with 1011. Cleanup does not overwrite a close code or reason already chosen by callback code. Returning while another owner continues to use the socket is unsupported because callback completion ends the session.

Middleware has already unwound when `onConnect` starts, so acquire and release session resources inside the callback. `InletServer.close()`, including forced close, does not close or wait for upgraded sockets. Track them in an application registry when coordinated shutdown is required. Origin checks, application message protocols, outgoing queue limits, slow-client policy, and shutdown deadlines remain application responsibilities.

In-process dispatch returns the same intent without parsing a handshake or invoking the selector or session callback. It has status 101 and `isWebSocketUpgrade == true`. Its application headers remain inspectable, while body access and buffering throw `StateError`; `sec-websocket-*` response headers are rejected because Dart owns them. Closing an unused intent is side-effect free. A HEAD fallback to a GET handler that returns an intent becomes an empty 405 response with `Allow: GET`.

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

`package:inlet/inlet.dart` exposes `Inlet`, `Router`, `Request`, `Response`, `SseEvent`, `Headers`, `ConnectionInfo`, `InletServer`, the handler, middleware, WebSocket callback types, and the request/response body-limit exceptions.

## Run the package

From `packages/inlet` in the repository workspace:

```sh
dart run example/inlet_example.dart
dart run example/stream_transfers.dart
dart run example/live_events.dart
dart run example/web_socket_chat.dart
dart test
dart analyze --fatal-infos
```

The examples use ephemeral listeners or in-process dispatch and exit after releasing their resources.

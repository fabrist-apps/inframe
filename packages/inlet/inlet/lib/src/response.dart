import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:inlet/src/body.dart';
import 'package:inlet/src/headers.dart';
import 'package:inlet/src/sse_event.dart';

/// Runs application work for the full lifetime of an upgraded WebSocket.
///
/// Inlet closes the socket when this callback completes. Keep the returned
/// future pending while application code uses the session.
typedef WebSocketCallback = FutureOr<void> Function(WebSocket socket);

/// Selects one of the subprotocols offered by a WebSocket client.
///
/// Inlet invokes the selector once with an immutable ordered list, including
/// an empty list when the client offered no protocols. Return `null` to select
/// none, return an offered value, or throw [WebSocketException] to reject the
/// handshake with the default status 400 response.
/// Invalid offered tokens also default to 400. Selecting an unoffered token
/// or throwing another error uses the application error boundary (500 by
/// default). An error hook may replace the rejection with an ordinary response,
/// but cannot return another upgrade intent.
typedef WebSocketProtocolSelector = FutureOr<String?> Function(List<String> offered);

/// A response body that exceeded a consumer-selected buffering limit.
final class ResponseBodyLimitExceededException implements Exception {
  /// Creates a response body limit failure for [maxBytes].
  const ResponseBodyLimitExceededException(this.maxBytes);

  /// The limit selected by the failed consumer.
  final int maxBytes;

  @override
  String toString() => 'ResponseBodyLimitExceededException: Body exceeds $maxBytes bytes.';
}

/// A content response or an inspectable WebSocket upgrade intent.
final class Response {
  Response._({
    required this.statusCode,
    required this.headers,
    required this._delivery,
    this._suppressBody = false,
  });

  /// Creates an empty response.
  factory Response.empty({
    int status = HttpStatus.noContent,
    Headers headers = const Headers.empty(),
  }) => Response._create(status: status, headers: headers, body: Body.bytes(const []));

  /// Creates a binary response, copying [value] at construction.
  factory Response.bytes(
    List<int> value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
    String? contentType = 'application/octet-stream',
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, contentType),
    body: Body.bytes(value),
  );

  /// Creates a UTF-8 text response.
  factory Response.text(
    String value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, 'text/plain; charset=utf-8'),
    body: Body.bytes(utf8.encode(value)),
  );

  /// Creates a UTF-8 JSON response, encoding [value] immediately.
  factory Response.json(
    Object? value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, 'application/json; charset=utf-8'),
    body: Body.bytes(utf8.encode(jsonEncode(value))),
  );

  /// Creates a lazy binary response.
  ///
  /// Resources used by [value] must outlive the handler and remain available
  /// until delivery finishes or is cancelled. HEAD, 204, 205, and 304 responses
  /// never subscribe to a suppressed source.
  factory Response.stream(
    Stream<List<int>> value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
    String? contentType = 'application/octet-stream',
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, contentType),
    body: Body(value),
  );

  /// Creates a lazy server-sent event response with fixed HTTP metadata.
  ///
  /// The response always uses status 200 and
  /// `text/event-stream; charset=utf-8`. It adds `cache-control: no-cache`
  /// when [headers] contains no cache policy. The event source is subscribed
  /// only when a consumer reads the body; HEAD never subscribes.
  ///
  /// In process, each event is one complete body chunk. HTTP delivery commits
  /// headers before subscription and awaits one socket flush per event. Closing
  /// or cancelling delivery requests cancellation of the event source.
  /// A flush does not guarantee delivery through a proxy to a client.
  ///
  /// Content encoding and transport-owned framing headers are rejected.
  /// [withHeaders] restores SSE metadata while sharing the same source owner.
  /// The producer owns heartbeat timing, replay, event limits, and slow-client
  /// policy beyond transport backpressure. Inlet provides no output queue or
  /// cancellation deadline; cancellation requires producer cooperation.
  factory Response.sse(
    Stream<SseEvent> events, {
    Headers headers = const Headers.empty(),
  }) => Response._(
    statusCode: HttpStatus.ok,
    headers: _sseHeaders(headers),
    delivery: ContentDelivery(Body(events.map((event) => event.encoded)), flushEvents: true),
  );

  /// Creates an inspectable intent to upgrade a GET request to WebSocket.
  ///
  /// Network delivery requires a valid WebSocket handshake. [selectProtocol]
  /// runs before the upgrade, while [onConnect] owns the complete upgraded
  /// session. Inlet closes with code 1000 when the callback completes and
  /// reports then closes with 1011 when it fails, unless callback code already
  /// selected a close reason.
  ///
  /// [maxFrameBytes] limits one incoming frame's uncompressed payload through
  /// Dart's transport. It does not bound a fragmented message or total
  /// connection memory. Compression is disabled unless [compression] enables
  /// it. The application owns origin policy, message protocols, outgoing queue
  /// limits, slow clients, and coordinated shutdown.
  ///
  /// In process this remains an inspectable intent: no handshake is parsed and
  /// neither callback runs. Body access throws [StateError]. Application
  /// headers are visible, but `sec-websocket-*` headers are handshake-owned and
  /// rejected.
  ///
  /// Middleware has unwound before [onConnect] runs; acquire session resources
  /// inside the callback. Listener shutdown does not close or wait for upgraded
  /// sockets. A HEAD fallback to a GET route returning this intent becomes an
  /// empty 405 response with `Allow: GET`.
  factory Response.webSocket({
    required WebSocketCallback onConnect,
    Headers headers = const Headers.empty(),
    WebSocketProtocolSelector? selectProtocol,
    int maxFrameBytes = defaultBodyLimit,
    CompressionOptions compression = CompressionOptions.compressionOff,
  }) {
    if (maxFrameBytes <= 0) {
      throw ArgumentError.value(maxFrameBytes, 'maxFrameBytes', 'must be positive');
    }

    return Response._(
      statusCode: HttpStatus.switchingProtocols,
      headers: _webSocketHeaders(headers),
      delivery: WebSocketDelivery(
        onConnect: onConnect,
        selectProtocol: selectProtocol,
        maxFrameBytes: maxFrameBytes,
        compression: compression,
      ),
    );
  }

  factory Response._create({required int status, required Headers headers, required Body body}) {
    _validateStatus(status);
    _validateResponseHeaders(headers);

    return Response._(
      statusCode: status,
      headers: headers,
      delivery: ContentDelivery(body),
      suppressBody: _statusSuppressesBody(status),
    );
  }

  /// The status delivered to the consumer.
  final int statusCode;

  /// Application response headers.
  final Headers headers;

  final ResponseDelivery _delivery;
  final bool _suppressBody;

  /// Whether this response represents a WebSocket upgrade intent.
  bool get isWebSocketUpgrade => _delivery is WebSocketDelivery;

  Body get _body => switch (_delivery) {
    ContentDelivery(:final body) => body,
    WebSocketDelivery() => throw StateError('A WebSocket upgrade response has no body.'),
  };

  /// The body stream, claimed when it is first listened to.
  ///
  /// Accessing the body of a WebSocket upgrade intent throws [StateError].
  Stream<List<int>> get body {
    if (isWebSocketUpgrade) {
      throw StateError('A WebSocket upgrade response has no body.');
    }

    return _suppressBody ? const Stream.empty() : _body.stream;
  }

  /// Creates a metadata view sharing this response's body owner.
  Response withHeaders(Headers headers) {
    final validatedHeaders = switch (_delivery) {
      ContentDelivery(flushEvents: true) => _sseHeaders(headers),
      ContentDelivery() => _validateResponseHeaders(headers),
      WebSocketDelivery() => _webSocketHeaders(headers),
    };

    return Response._(
      statusCode: statusCode,
      headers: validatedHeaders,
      delivery: _delivery,
      suppressBody: _suppressBody,
    );
  }

  /// Buffers the body once and returns a private byte copy.
  ///
  /// A WebSocket upgrade intent has no body and throws [StateError].
  Future<List<int>> bytes({int maxBytes = defaultBodyLimit}) async {
    if (isWebSocketUpgrade) {
      throw StateError('A WebSocket upgrade response has no body.');
    }

    validateMaxBytes(maxBytes);
    if (_suppressBody) {
      return Uint8List(0);
    }

    try {
      return await _body.bytes(maxBytes: maxBytes);
    } on BodyLimitFailure catch (error) {
      throw ResponseBodyLimitExceededException(error.maxBytes);
    }
  }

  /// Strictly decodes the buffered body as UTF-8.
  Future<String> text({int maxBytes = defaultBodyLimit}) async =>
      utf8.decode(await bytes(maxBytes: maxBytes), allowMalformed: false);

  /// Strictly decodes the buffered body as UTF-8 JSON.
  Future<Object?> json({int maxBytes = defaultBodyLimit}) async =>
      jsonDecode(await text(maxBytes: maxBytes));

  /// Releases body resources without subscribing to an untouched source.
  Future<void> close() => _delivery.close();

  static Headers _withDefaultContentType(Headers headers, String? contentType) {
    if (contentType == null || headers.contains(HttpHeaders.contentTypeHeader)) {
      return headers;
    }

    return headers.set(HttpHeaders.contentTypeHeader, contentType);
  }

  static void _validateStatus(int status) {
    if (status < 200 || status > 599) {
      throw ArgumentError.value(status, 'status', 'must be from 200 through 599');
    }
  }

  static bool _statusSuppressesBody(int status) =>
      status == HttpStatus.noContent ||
      status == HttpStatus.resetContent ||
      status == HttpStatus.notModified;

  static Headers _validateResponseHeaders(Headers headers) {
    const forbidden = <String>{
      HttpHeaders.contentLengthHeader,
      HttpHeaders.transferEncodingHeader,
      HttpHeaders.connectionHeader,
      'keep-alive',
      'proxy-connection',
      HttpHeaders.trailerHeader,
      HttpHeaders.upgradeHeader,
    };
    for (final name in forbidden) {
      if (headers.contains(name)) {
        throw ArgumentError.value(name, 'headers', 'is owned by the HTTP adapter');
      }
    }

    return headers;
  }

  static Headers _sseHeaders(Headers headers) {
    _validateResponseHeaders(headers);
    if (headers.contains(HttpHeaders.contentEncodingHeader)) {
      throw ArgumentError.value(
        HttpHeaders.contentEncodingHeader,
        'headers',
        'is not supported for server-sent events',
      );
    }

    var result = headers.set(
      HttpHeaders.contentTypeHeader,
      'text/event-stream; charset=utf-8',
    );
    if (!result.contains(HttpHeaders.cacheControlHeader)) {
      result = result.set(HttpHeaders.cacheControlHeader, 'no-cache');
    }

    return result;
  }

  static Headers _webSocketHeaders(Headers headers) {
    _validateResponseHeaders(headers);
    for (final name in headers.toMap().keys) {
      if (name.startsWith('sec-websocket-')) {
        throw ArgumentError.value(name, 'headers', 'is owned by the WebSocket handshake');
      }
    }

    return headers;
  }
}

/// Transport-only access, excluded from the public entrypoint.
extension ResponseRuntime on Response {
  /// Whether this view preserves another response's status and body ownership.
  bool isHeaderViewOf(Response other) =>
      identical(_delivery, other._delivery) &&
      statusCode == other.statusCode &&
      _suppressBody == other._suppressBody;

  /// Shared content or upgrade owner behind response metadata views.
  ResponseDelivery get delivery => _delivery;

  /// Whether delivery must omit payload bytes, as for HEAD responses.
  bool get suppressBody => _suppressBody;

  /// Creates a bodyless view without replacing the shared delivery owner.
  Response withoutBody() => _suppressBody
      ? this
      : Response._(
          statusCode: statusCode,
          headers: headers,
          delivery: _delivery,
          suppressBody: true,
        );
}

/// One shared delivery owner for every metadata view of a response.
sealed class ResponseDelivery {
  /// Base constructor for content and upgrade delivery owners.
  const ResponseDelivery();

  /// Releases pending delivery resources once across all response views.
  Future<void> close();
}

/// Byte content with an optional per-event flushing policy for SSE.
final class ContentDelivery extends ResponseDelivery {
  /// Owns [body] until response cleanup completes.
  const ContentDelivery(this.body, {this.flushEvents = false});

  /// Shared stream consumption and buffering state.
  final Body body;

  /// Whether transport flushes every chunk as an SSE event.
  final bool flushEvents;

  @override
  Future<void> close() => body.close();
}

/// Upgrade configuration and pre-handshake lifetime shared by response views.
final class WebSocketDelivery extends ResponseDelivery {
  /// Records negotiation and session settings without opening a socket.
  WebSocketDelivery({
    required this.onConnect,
    required this.selectProtocol,
    required this.maxFrameBytes,
    required this.compression,
  });

  /// Runs after a successful upgrade; transport owns the session lifetime.
  final WebSocketCallback onConnect;

  /// Chooses a protocol from the client's offer, when supplied.
  final WebSocketProtocolSelector? selectProtocol;

  /// Maximum received frame size in bytes.
  final int maxFrameBytes;

  /// Compression settings passed to the platform handshake.
  final CompressionOptions compression;
  Future<void>? _closeFuture;

  /// Whether response cleanup has invalidated this pending upgrade.
  bool get isClosed => _closeFuture != null;

  @override
  Future<void> close() => _closeFuture ??= Future<void>.value();
}

part of 'inlet.dart';

/// A response body that exceeded a consumer-selected buffering limit.
final class ResponseBodyLimitExceededException implements Exception {
  /// Creates a response body limit failure for [maxBytes].
  const ResponseBodyLimitExceededException(this.maxBytes);

  /// The limit selected by the failed consumer.
  final int maxBytes;

  @override
  String toString() => 'ResponseBodyLimitExceededException: Body exceeds $maxBytes bytes.';
}

/// A buffered, streamed, or server-sent event response.
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
  }) => Response._create(status: status, headers: headers, body: _Body.bytes(const []));

  /// Creates a binary response, copying [value] at construction.
  factory Response.bytes(
    List<int> value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
    String? contentType = 'application/octet-stream',
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, contentType),
    body: _Body.bytes(value),
  );

  /// Creates a UTF-8 text response.
  factory Response.text(
    String value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, 'text/plain; charset=utf-8'),
    body: _Body.bytes(utf8.encode(value)),
  );

  /// Creates a UTF-8 JSON response, encoding [value] immediately.
  factory Response.json(
    Object? value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, 'application/json; charset=utf-8'),
    body: _Body.bytes(utf8.encode(jsonEncode(value))),
  );

  /// Creates a lazy binary response.
  factory Response.stream(
    Stream<List<int>> value, {
    int status = HttpStatus.ok,
    Headers headers = const Headers.empty(),
    String? contentType = 'application/octet-stream',
  }) => Response._create(
    status: status,
    headers: _withDefaultContentType(headers, contentType),
    body: _Body(value),
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
  factory Response.sse(
    Stream<SseEvent> events, {
    Headers headers = const Headers.empty(),
  }) => Response._(
    statusCode: HttpStatus.ok,
    headers: _sseHeaders(headers),
    delivery: _SseDelivery(_Body(events.map((event) => event._encoded))),
  );

  factory Response._create({required int status, required Headers headers, required _Body body}) {
    _validateStatus(status);
    _validateResponseHeaders(headers);
    return Response._(
      statusCode: status,
      headers: headers,
      delivery: _OrdinaryDelivery(body),
      suppressBody: _statusSuppressesBody(status),
    );
  }

  /// The status delivered to the consumer.
  final int statusCode;

  /// Application response headers.
  final Headers headers;

  final _ResponseDelivery _delivery;
  final bool _suppressBody;

  _Body get _body => _delivery.body;

  /// The body stream, claimed when it is first listened to.
  Stream<List<int>> get body => _suppressBody ? const Stream.empty() : _body.stream;

  /// Creates a metadata view sharing this response's body owner.
  Response withHeaders(Headers headers) {
    final validatedHeaders = switch (_delivery) {
      _OrdinaryDelivery() => _validatedResponseHeaders(headers),
      _SseDelivery() => _sseHeaders(headers),
    };
    return Response._(
      statusCode: statusCode,
      headers: validatedHeaders,
      delivery: _delivery,
      suppressBody: _suppressBody,
    );
  }

  Response _withoutBody() => _suppressBody
      ? this
      : Response._(
          statusCode: statusCode,
          headers: headers,
          delivery: _delivery,
          suppressBody: true,
        );

  /// Buffers the body once and returns a private byte copy.
  Future<List<int>> bytes({int maxBytes = _defaultBodyLimit}) async {
    _validateMaxBytes(maxBytes);
    if (_suppressBody) {
      return Uint8List(0);
    }
    try {
      return await _body.bytes(maxBytes: maxBytes);
    } on _BodyLimitFailure catch (error) {
      throw ResponseBodyLimitExceededException(error.maxBytes);
    }
  }

  /// Strictly decodes the buffered body as UTF-8.
  Future<String> text({int maxBytes = _defaultBodyLimit}) async =>
      utf8.decode(await bytes(maxBytes: maxBytes), allowMalformed: false);

  /// Strictly decodes the buffered body as UTF-8 JSON.
  Future<Object?> json({int maxBytes = _defaultBodyLimit}) async =>
      jsonDecode(await text(maxBytes: maxBytes));

  /// Releases body resources without subscribing to an untouched source.
  Future<void> close() => _body.close();
}

sealed class _ResponseDelivery {
  const _ResponseDelivery(this.body);

  final _Body body;
}

final class _OrdinaryDelivery extends _ResponseDelivery {
  const _OrdinaryDelivery(super.body);
}

final class _SseDelivery extends _ResponseDelivery {
  const _SseDelivery(super.body);
}

Headers _withDefaultContentType(Headers headers, String? contentType) {
  if (contentType == null || headers.contains(HttpHeaders.contentTypeHeader)) {
    return headers;
  }
  return headers.set(HttpHeaders.contentTypeHeader, contentType);
}

void _validateStatus(int status) {
  if (status < 200 || status > 599) {
    throw ArgumentError.value(status, 'status', 'must be from 200 through 599');
  }
}

bool _statusSuppressesBody(int status) =>
    status == HttpStatus.noContent || status == HttpStatus.resetContent || status == 304;

void _validateResponseHeaders(Headers headers) {
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
}

Headers _validatedResponseHeaders(Headers headers) {
  _validateResponseHeaders(headers);
  return headers;
}

Headers _sseHeaders(Headers headers) {
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

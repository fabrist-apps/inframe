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

/// An ordinary buffered or streamed response.
final class Response {
  Response._({
    required this.statusCode,
    required this.headers,
    required this._body,
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

  factory Response._create({required int status, required Headers headers, required _Body body}) {
    _validateStatus(status);
    _validateResponseHeaders(headers);
    return Response._(
      statusCode: status,
      headers: headers,
      body: body,
      suppressBody: _statusSuppressesBody(status),
    );
  }

  /// The status delivered to the consumer.
  final int statusCode;

  /// Application response headers.
  final Headers headers;

  final _Body _body;
  final bool _suppressBody;

  /// The body stream, claimed when it is first listened to.
  Stream<List<int>> get body => _suppressBody ? const Stream.empty() : _body.stream;

  /// Creates a metadata view sharing this response's body owner.
  Response withHeaders(Headers headers) {
    _validateResponseHeaders(headers);
    return Response._(
      statusCode: statusCode,
      headers: headers,
      body: _body,
      suppressBody: _suppressBody,
    );
  }

  Response _withoutBody() => _suppressBody
      ? this
      : Response._(statusCode: statusCode, headers: headers, body: _body, suppressBody: true);

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

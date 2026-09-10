part of 'inlet.dart';

/// A malformed UTF-8 or JSON request body.
final class MalformedBodyException implements Exception {
  /// Creates a malformed-body failure without retaining submitted content.
  const MalformedBodyException();

  @override
  String toString() => 'MalformedBodyException: The request body is malformed.';
}

/// A request body that exceeded the selected buffering limit.
final class BodyLimitExceededException implements Exception {
  /// Creates a body-limit failure for [maxBytes].
  const BodyLimitExceededException(this.maxBytes);

  /// The limit selected by the failed reader.
  final int maxBytes;

  @override
  String toString() => 'BodyLimitExceededException: Body exceeds $maxBytes bytes.';
}

/// Transport facts associated with one request.
final class ConnectionInfo {
  /// Creates validated connection facts.
  ConnectionInfo({
    required this.remoteAddress,
    required this.remotePort,
    required this.localPort,
    required this.isSecure,
  }) {
    _validatePort(remotePort, 'remotePort');
    _validatePort(localPort, 'localPort');
  }

  /// The peer address reported by the transport.
  final InternetAddress remoteAddress;

  /// The peer port reported by the transport.
  final int remotePort;

  /// The local listener port.
  final int localPort;

  /// Whether the request arrived through TLS.
  final bool isSecure;
}

/// A request that can be dispatched by [Inlet].
final class Request {
  /// Creates a request.
  Request({
    required String method,
    required Uri uri,
    Headers headers = const Headers.empty(),
    Stream<List<int>> body = const Stream.empty(),
    ConnectionInfo? connection,
  }) : this._(
         method: _validateMethod(method),
         uri: _validateUri(uri),
         headers: headers,
         connection: connection,
         pathParameters: const {},
         exchange: _RequestExchange(_Body(body)),
       );

  Request._({
    required this.method,
    required this.uri,
    required this.headers,
    required this.connection,
    required Map<String, String> pathParameters,
    required this._exchange,
  }) : pathParameters = Map.unmodifiable(pathParameters);

  /// The case-sensitive HTTP method.
  final String method;

  /// The request URI.
  final Uri uri;

  /// Application-visible request headers.
  final Headers headers;

  /// Immutable captures from the selected route.
  final Map<String, String> pathParameters;

  /// Transport facts, when supplied by the request owner.
  final ConnectionInfo? connection;

  final _RequestExchange _exchange;

  /// Creates a metadata view with [headers] and the same body and exchange identity.
  Request withHeaders(Headers headers) => Request._(
    method: method,
    uri: uri,
    headers: headers,
    connection: connection,
    pathParameters: pathParameters,
    exchange: _exchange,
  );

  /// Buffers the body once and returns a private byte copy.
  Future<List<int>> bytes({int maxBytes = _defaultBodyLimit}) async {
    try {
      return await _exchange.body.bytes(maxBytes: maxBytes);
    } on _BodyLimitFailure {
      throw BodyLimitExceededException(maxBytes);
    }
  }

  /// Strictly decodes the buffered body as UTF-8.
  Future<String> text({int maxBytes = _defaultBodyLimit}) async {
    final bodyBytes = await bytes(maxBytes: maxBytes);
    try {
      return utf8.decode(bodyBytes, allowMalformed: false);
    } on FormatException {
      throw const MalformedBodyException();
    }
  }

  /// Strictly decodes the buffered body as UTF-8 JSON.
  Future<Object?> json({int maxBytes = _defaultBodyLimit}) async {
    try {
      return jsonDecode(await text(maxBytes: maxBytes));
    } on MalformedBodyException {
      rethrow;
    } on FormatException {
      throw const MalformedBodyException();
    }
  }

  /// Releases body resources without subscribing to an untouched source.
  Future<void> close() => _exchange.body.close();

  void _admit() {
    if (_exchange.admitted) {
      throw StateError('A Request can be admitted only once.');
    }
    _exchange.admitted = true;
  }
}

final class _RequestExchange {
  _RequestExchange(this.body);

  final _Body body;
  bool admitted = false;
}

String _validateMethod(String method) {
  if (method.isEmpty || method.codeUnits.any((unit) => !_isMethodTokenCodeUnit(unit))) {
    throw ArgumentError.value(method, 'method', 'must be a nonempty HTTP token');
  }
  return method;
}

bool _isMethodTokenCodeUnit(int unit) {
  const separators = <int>{
    0x28,
    0x29,
    0x3c,
    0x3e,
    0x40,
    0x2c,
    0x3b,
    0x3a,
    0x5c,
    0x22,
    0x2f,
    0x5b,
    0x5d,
    0x3f,
    0x3d,
    0x7b,
    0x7d,
  };
  return unit > 0x20 && unit < 0x7f && !separators.contains(unit);
}

Uri _validateUri(Uri uri) {
  if (!uri.path.startsWith('/')) {
    throw ArgumentError.value(uri, 'uri', 'must have an absolute path');
  }
  if (uri.hasFragment || uri.userInfo.isNotEmpty) {
    throw ArgumentError.value(uri, 'uri', 'must not contain a fragment or user information');
  }
  if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
    throw ArgumentError.value(uri, 'uri', 'absolute URIs must use HTTP or HTTPS');
  }
  return uri;
}

void _validatePort(int port, String name) {
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, name, 'must be from 0 through 65535');
  }
}

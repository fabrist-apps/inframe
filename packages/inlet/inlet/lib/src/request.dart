import 'dart:convert';
import 'dart:io';

import 'package:context/context.dart';
import 'package:inlet/src/body.dart';
import 'package:inlet/src/headers.dart';
import 'package:inlet/src/http_token.dart';
import 'package:inlet/src/response.dart';

/// Observes a completed dispatch and optionally replaces its response headers.
///
/// Return [response] or a header view made with [Response.withHeaders].
typedef ResponseHook = Response Function(Context context, Request request, Response response);

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
    validatePort(remotePort, 'remotePort');
    validatePort(localPort, 'localPort');
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

/// A request that can be dispatched by an Inlet application.
final class Request {
  /// Creates a request.
  Request({
    required String method,
    required Uri uri,
    Headers headers = const Headers.empty(),
    Stream<List<int>> body = const Stream.empty(),
    ConnectionInfo? connection,
  }) : this._(
         method: validateMethod(method),
         uri: _validateUri(uri),
         headers: headers,
         connection: connection,
         pathParameters: const {},
         exchange: _RequestExchange(Body(body)),
       );

  Request._({
    required this.method,
    required this.uri,
    required this.headers,
    required this.connection,
    required this.pathParameters,
    required this._exchange,
    this.routeTemplate,
  });

  /// The case-sensitive HTTP method.
  final String method;

  /// The request URI.
  final Uri uri;

  /// Application-visible request headers.
  final Headers headers;

  /// Immutable captures from the selected route.
  final Map<String, String> pathParameters;

  /// The matched route template, including mount prefixes, or null if unmatched.
  ///
  /// Available during dispatch; contains parameter names instead of values.
  final String? routeTemplate;

  /// Transport facts, when supplied by the request owner.
  final ConnectionInfo? connection;

  final _RequestExchange _exchange;

  /// Registers a synchronous hook after middleware, error recovery, and HEAD handling.
  ///
  /// Hooks run once in reverse registration order with the latest forwarded
  /// context and request. Return the response or a view from `withHeaders`;
  /// changing status or body ownership is rejected. Hook failures are reported
  /// without replacing the response, and remaining hooks still run.
  ///
  /// This observes dispatch completion before transport delivery. It excludes
  /// streamed body work, WebSocket sessions, and transport error recovery.
  /// Header views share registrations. Register before dispatch completes;
  /// registration during or after hook execution throws [StateError].
  void onResponse(ResponseHook hook) {
    if (_exchange.responseCompleted) {
      throw StateError('Response hooks must be registered before dispatch completes.');
    }
    _exchange.responseHooks.add(hook);
  }

  /// Creates a metadata view with [headers] and the same body and exchange identity.
  Request withHeaders(Headers headers) => Request._(
    method: method,
    uri: uri,
    headers: headers,
    connection: connection,
    pathParameters: pathParameters,
    exchange: _exchange,
    routeTemplate: routeTemplate,
  );

  /// The body stream, claimed when it is first listened to.
  Stream<List<int>> get body => _exchange.body.stream;

  /// Buffers the body once and returns a private byte copy.
  ///
  /// The default limit is 1 MiB. The first buffering call selects the physical
  /// read limit; later callers share that read but enforce their own limits.
  /// Raw streaming and buffering are exclusive, even after reading completes.
  Future<List<int>> bytes({int maxBytes = defaultBodyLimit}) async {
    try {
      return await _exchange.body.bytes(maxBytes: maxBytes);
    } on BodyLimitFailure catch (error) {
      throw BodyLimitExceededException(error.maxBytes);
    }
  }

  /// Strictly decodes the buffered body as UTF-8.
  Future<String> text({int maxBytes = defaultBodyLimit}) async {
    final bodyBytes = await bytes(maxBytes: maxBytes);

    try {
      return utf8.decode(bodyBytes, allowMalformed: false);
    } on FormatException {
      throw const MalformedBodyException();
    }
  }

  /// Strictly decodes the buffered body as UTF-8 JSON.
  Future<Object?> json({int maxBytes = defaultBodyLimit}) async {
    try {
      return jsonDecode(await text(maxBytes: maxBytes));
    } on FormatException {
      throw const MalformedBodyException();
    }
  }

  /// Releases body resources without subscribing to an untouched source.
  Future<void> close() => _exchange.body.close();

  static Uri _validateUri(Uri uri) {
    if (!uri.path.startsWith('/')) {
      throw ArgumentError.value(uri, 'uri', 'must have an absolute path');
    }

    if (uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(uri, 'uri', 'must not contain a fragment or user information');
    }

    if (uri.hasAuthority && !uri.hasScheme) {
      throw ArgumentError.value(
        uri,
        'uri',
        'an authority requires an absolute HTTP or HTTPS URI',
      );
    }

    if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(uri, 'uri', 'absolute URIs must use HTTP or HTTPS');
    }

    return uri;
  }
}

final class _RequestExchange {
  _RequestExchange(this.body);

  final Body body;
  bool admitted = false;
  bool responseCompleted = false;
  final responseHooks = <ResponseHook>[];
}

/// Dispatch-only operations, excluded from the public entrypoint.
extension RequestRuntime on Request {
  /// Finalizes dispatch metadata without transferring response body ownership.
  Future<Response> completeResponse(
    Context context,
    Response response,
    void Function(Object, StackTrace) report,
  ) async {
    if (_exchange.responseCompleted) return response;
    _exchange.responseCompleted = true;
    final hooks = _exchange.responseHooks.reversed.toList();
    _exchange.responseHooks.clear();
    var current = response;
    for (final hook in hooks) {
      try {
        final viewed = hook(context, this, current);
        if (!viewed.isHeaderViewOf(current)) {
          if (!identical(viewed.delivery, current.delivery)) {
            try {
              await viewed.close();
            } on Object catch (error, stackTrace) {
              report(error, stackTrace);
            }
          }
          throw StateError('Response hooks may only replace headers.');
        }
        current = viewed;
      } on Object catch (error, stackTrace) {
        report(error, stackTrace);
      }
    }
    return current;
  }

  /// Adds route captures while retaining exchange and body ownership.
  Request withPathParameters(
    Map<String, String> pathParameters, {
    String? routeTemplate,
  }) => Request._(
    method: method,
    uri: uri,
    headers: headers,
    connection: connection,
    pathParameters: pathParameters,
    exchange: _exchange,
    routeTemplate: routeTemplate,
  );

  /// Whether both views share an exchange and the current route captures.
  bool isViewOf(Request other) =>
      identical(_exchange, other._exchange) && identical(pathParameters, other.pathParameters);

  /// Claims this exchange for dispatch, rejecting reuse through any view.
  void admit() {
    if (_exchange.admitted) {
      throw StateError('A Request can be admitted only once.');
    }

    _exchange.admitted = true;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:context/context.dart';

import 'package:inlet/src/headers.dart';
import 'package:inlet/src/http_token.dart';

part 'body.dart';
part 'middleware.dart';
part 'request.dart';
part 'response.dart';
part 'router.dart';
part 'server.dart';
part 'sse_event.dart';

/// A request handler.
typedef Handler = FutureOr<Response> Function(Context context, Request request);

/// Continues a middleware chain with an explicitly forwarded context and request.
typedef Next = Future<Response> Function(Context context, Request request);

/// Work that runs around a matched handler.
typedef Middleware = FutureOr<Response> Function(Context context, Request request, Next next);

/// Replaces the default response for an escaped dispatch failure.
typedef ErrorHandler = FutureOr<Response> Function(
  Context context,
  Request request,
  Object error,
  StackTrace stackTrace,
);

/// Observes an unexpected runtime failure.
typedef ErrorReporter = void Function(Object error, StackTrace stackTrace);

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
typedef WebSocketProtocolSelector = FutureOr<String?> Function(List<String> offered);

/// An application that dispatches registered routes in process or over HTTP.
final class Inlet extends Router {
  /// Creates an editable application.
  Inlet({Context? context, bool strict = true, this.onError, this.onReportError})
    : context = context ?? Context(),
      super._(strict);

  /// The port used by [serve] when no port is supplied.
  static const int defaultHttpPort = 8080;

  /// The port used by [serveSecure] when no port is supplied.
  static const int defaultHttpsPort = 8443;

  /// The context used when a dispatch does not provide its own context.
  final Context context;

  /// The optional application error hook.
  final ErrorHandler? onError;

  /// The optional unexpected-error reporter.
  final ErrorReporter? onReportError;

  /// Dispatches [request] without a network listener.
  Future<Response> handle(Request request, {Context? context}) async =>
      (await _dispatch(request, context: context)).response;

  /// Starts an HTTP listener.
  Future<InletServer> serve({
    InternetAddress? address,
    int port = defaultHttpPort,
    int backlog = 0,
    bool shared = false,
    Duration? idleTimeout = const Duration(seconds: 120),
  }) => _startServer(
    address: address,
    port: port,
    backlog: backlog,
    idleTimeout: idleTimeout,
    isSecure: false,
    bind: (bindAddress) => HttpServer.bind(
      bindAddress,
      port,
      backlog: backlog,
      shared: shared,
    ),
  );

  /// Starts an HTTPS listener using [securityContext].
  Future<InletServer> serveSecure(
    SecurityContext securityContext, {
    InternetAddress? address,
    int port = defaultHttpsPort,
    int backlog = 0,
    bool shared = false,
    Duration? idleTimeout = const Duration(seconds: 120),
  }) => _startServer(
    address: address,
    port: port,
    backlog: backlog,
    idleTimeout: idleTimeout,
    isSecure: true,
    bind: (bindAddress) => HttpServer.bindSecure(
      bindAddress,
      port,
      securityContext,
      backlog: backlog,
      shared: shared,
    ),
  );

  Future<_DispatchResult> _dispatch(Request request, {Context? context}) async {
    final router = await _admit(request);
    final dispatchContext = context ?? this.context;
    final resolution = router.resolve(request);
    final (:middleware, :terminal, :dispatchRequest) = switch (resolution) {
      _BadRoutePath() => (
        middleware: router.rootMiddleware,
        terminal: _badRequest,
        dispatchRequest: request,
      ),
      _RouteNotFound() => (
        middleware: router.rootMiddleware,
        terminal: _notFound,
        dispatchRequest: request,
      ),
      _MethodNotAllowed(:final allowedMethods) => (
        middleware: router.rootMiddleware,
        terminal: _methodNotAllowed(allowedMethods),
        dispatchRequest: request,
      ),
      _MatchedRoute(:final registration, :final pathParameters) => (
        middleware: <Middleware>[
          ...router.rootMiddleware,
          ...registration.middleware,
        ],
        terminal: registration.handler,
        dispatchRequest: request._withPathParameters(pathParameters),
      ),
    };
    final dispatch = _DispatchState(dispatchContext, dispatchRequest, _report);

    late final Response response;

    try {
      response = await _runMiddleware(
        middleware,
        terminal,
        dispatch,
        dispatchContext,
        dispatchRequest,
      );
    } on Object catch (error, stackTrace) {
      response = await _recover(
        dispatch.context,
        dispatch.request,
        error,
        stackTrace,
      );
    }

    var finalizedResponse = response;
    if (request.method == 'HEAD') {
      if (resolution case _MatchedRoute(isHeadFallback: true) when response.isWebSocketUpgrade) {
        await response.close();
        finalizedResponse = _headWebSocketRejected();
      } else {
        finalizedResponse = response._withoutBody();
      }
    }

    return _DispatchResult(
      finalizedResponse,
      dispatch.context,
      dispatch.request,
    );
  }

  Future<Response> _recover(
    Context context,
    Request request,
    Object error,
    StackTrace stackTrace,
  ) async {
    if (_isUnexpected(error) && !_wasReported(error)) {
      _report(error, stackTrace);
    }

    final errorHandler = onError;
    if (errorHandler == null) {
      return _defaultErrorResponse(error);
    }

    try {
      return await errorHandler(context, request, error, stackTrace);
    } on Object catch (hookError, hookStackTrace) {
      _report(hookError, hookStackTrace);

      return Response.empty(status: HttpStatus.internalServerError);
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    final reporter = onReportError;
    if (reporter == null) {
      stderr
        ..writeln(error)
        ..writeln(stackTrace);
      return;
    }

    try {
      reporter(error, stackTrace);
    } on Object catch (reporterError, reporterStackTrace) {
      stderr
        ..writeln(reporterError)
        ..writeln(reporterStackTrace);
    }
  }
}

Response _headWebSocketRejected() => Response.empty(
  status: HttpStatus.methodNotAllowed,
  headers: const Headers.empty().set(HttpHeaders.allowHeader, 'GET'),
);

final class _DispatchResult {
  const _DispatchResult(this.response, this.context, this.request);

  final Response response;
  final Context context;
  final Request request;
}

Response _badRequest(Context _, Request _) => Response.empty(status: HttpStatus.badRequest);

Response _notFound(Context _, Request _) => Response.empty(status: HttpStatus.notFound);

Handler _methodNotAllowed(List<String> allowedMethods) =>
    (_, _) => Response.empty(
      status: HttpStatus.methodNotAllowed,
      headers: const Headers.empty().set(
        HttpHeaders.allowHeader,
        allowedMethods.join(', '),
      ),
    );

Response _defaultErrorResponse(Object error) => switch (error) {
  _WebSocketHandshakeRejected() => Response.empty(status: HttpStatus.badRequest),
  MalformedBodyException() => Response.empty(status: HttpStatus.badRequest),
  BodyLimitExceededException() => Response.empty(
    status: HttpStatus.requestEntityTooLarge,
  ),
  _ => Response.empty(status: HttpStatus.internalServerError),
};

bool _isUnexpected(Object error) =>
    error is! _WebSocketHandshakeRejected &&
    error is! MalformedBodyException &&
    error is! BodyLimitExceededException;

bool _wasReported(Object error) => error is _ContinuationStateError && error.wasReported;

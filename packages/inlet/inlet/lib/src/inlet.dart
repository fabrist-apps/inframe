import 'dart:io';

import 'package:context/context.dart';
import 'package:inlet/src/errors.dart';
import 'package:inlet/src/handler.dart';
import 'package:inlet/src/headers.dart';
import 'package:inlet/src/middleware.dart';
import 'package:inlet/src/request.dart';
import 'package:inlet/src/response.dart';
import 'package:inlet/src/router.dart';
import 'package:inlet/src/transport/server.dart';

/// An application that dispatches registered routes in process or over HTTP.
final class Inlet extends Router {
  /// Creates an editable application.
  Inlet({Context? context, super.strict, this.onError, this.onReportError})
    : context = context ?? Context();

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

  Future<InletServer> _startServer({
    required InternetAddress? address,
    required int port,
    required int backlog,
    required Duration? idleTimeout,
    required bool isSecure,
    required Future<HttpServer> Function(InternetAddress address) bind,
  }) async {
    InletServerRuntime.validateOptions(port, backlog, idleTimeout);
    final bindAddress = address ?? InternetAddress.loopbackIPv4;

    return freezeAfter(
      () => InletServerRuntime.bind(
        bind: () => bind(bindAddress),
        idleTimeout: idleTimeout,
        isSecure: isSecure,
        dispatch: _dispatch,
        recover: _recover,
        report: _report,
      ),
    );
  }

  Future<DispatchResult> _dispatch(Request request, {Context? context}) async {
    final router = await admit(request);
    final dispatchContext = context ?? this.context;
    final resolution = router.resolve(request);
    final (:middleware, :terminal, :dispatchRequest) = switch (resolution) {
      BadRoutePath() => (
        middleware: router.rootMiddleware,
        terminal: _badRequest,
        dispatchRequest: request,
      ),
      RouteNotFound() => (
        middleware: router.rootMiddleware,
        terminal: _notFound,
        dispatchRequest: request,
      ),
      MethodNotAllowed(:final allowedMethods) => (
        middleware: router.rootMiddleware,
        terminal: _methodNotAllowed(allowedMethods),
        dispatchRequest: request,
      ),
      MatchedRoute(:final registration, :final pathParameters) => (
        middleware: <Middleware>[
          ...router.rootMiddleware,
          ...registration.middleware,
        ],
        terminal: registration.handler,
        dispatchRequest: request.withPathParameters(
          pathParameters,
          routeTemplate: registration.rawPath,
        ),
      ),
    };
    final dispatch = DispatchState(dispatchContext, dispatchRequest, _report);

    late final Response response;

    try {
      response = await runMiddleware(
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
      if (resolution case MatchedRoute(isHeadFallback: true) when response.isWebSocketUpgrade) {
        await response.close();
        finalizedResponse = _headWebSocketRejected();
      } else {
        finalizedResponse = response.withoutBody();
      }
    }

    finalizedResponse = await dispatch.request.completeResponse(
      dispatch.context,
      finalizedResponse,
      _report,
    );

    return DispatchResult(
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
    if (isUnexpected(error) && !wasReported(error)) {
      _report(error, stackTrace);
    }

    final errorHandler = onError;
    if (errorHandler == null) {
      return defaultErrorResponse(error);
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

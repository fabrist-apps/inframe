import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:context/context.dart';

import 'package:inlet/src/headers.dart';

part 'body.dart';
part 'middleware.dart';
part 'request.dart';
part 'response.dart';
part 'router.dart';

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

/// An application that dispatches registered routes in process or over HTTP.
final class Inlet extends Router {
  /// Creates an editable application.
  // `Router` keeps its strictness private, so a super parameter would expose `_strict`.
  // ignore: use_super_parameters
  Inlet({Context? context, bool strict = true, this.onError, this.onReportError})
    : context = context ?? Context(),
      super._(strict: strict);

  /// The context used when a dispatch does not provide its own context.
  final Context context;

  /// The optional application error hook.
  final ErrorHandler? onError;

  /// The optional unexpected-error reporter.
  final ErrorReporter? onReportError;

  /// Dispatches [request] without a network listener.
  Future<Response> handle(Request request, {Context? context}) async {
    final router = _admit(request);
    final dispatchContext = context ?? this.context;
    final resolution = router.resolve(request);
    final (:middleware, :terminal, :dispatchRequest, :suppressBody) = switch (resolution) {
      _BadRoutePath() => (
        middleware: router.rootMiddleware,
        terminal: _badRequest,
        dispatchRequest: request,
        suppressBody: false,
      ),
      _RouteNotFound() => (
        middleware: router.rootMiddleware,
        terminal: _notFound,
        dispatchRequest: request,
        suppressBody: false,
      ),
      _MethodNotAllowed(:final allowedMethods) => (
        middleware: router.rootMiddleware,
        terminal: _methodNotAllowed(allowedMethods),
        dispatchRequest: request,
        suppressBody: false,
      ),
      _MatchedRoute(:final registration, :final pathParameters, :final suppressBody) => (
        middleware: <Middleware>[
          ...router.rootMiddleware,
          for (final scope in registration.scopes) ...scope,
          ...registration.middleware,
        ],
        terminal: registration.handler,
        dispatchRequest: request._withPathParameters(pathParameters),
        suppressBody: suppressBody,
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
      if (_isUnexpected(error) && !_wasReported(error)) {
        _report(error, stackTrace);
      }
      final errorHandler = onError;
      if (errorHandler != null) {
        try {
          response = await errorHandler(
            dispatch.context,
            dispatch.request,
            error,
            stackTrace,
          );
        } on Object catch (hookError, hookStackTrace) {
          _report(hookError, hookStackTrace);
          response = Response.empty(status: HttpStatus.internalServerError);
        }
      } else {
        response = _defaultErrorResponse(error);
      }
    }
    return suppressBody ? response._withoutBody() : response;
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
  MalformedBodyException() => Response.empty(status: HttpStatus.badRequest),
  BodyLimitExceededException() => Response.empty(
    status: HttpStatus.requestEntityTooLarge,
  ),
  _ => Response.empty(status: HttpStatus.internalServerError),
};

bool _isUnexpected(Object error) =>
    error is! MalformedBodyException && error is! BodyLimitExceededException;

bool _wasReported(Object error) => error is _ContinuationStateError && error.wasReported;

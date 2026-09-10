import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:context/context.dart';

import 'package:inlet/src/headers.dart';

part 'body.dart';
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
    if (resolution case _BadRoutePath()) {
      return Response.empty(status: HttpStatus.badRequest);
    }
    if (resolution case _RouteNotFound()) {
      return Response.empty(status: HttpStatus.notFound);
    }
    if (resolution case _MethodNotAllowed(:final allowedMethods)) {
      return Response.empty(
        status: HttpStatus.methodNotAllowed,
        headers: const Headers.empty().set(HttpHeaders.allowHeader, allowedMethods.join(', ')),
      );
    }
    final matched = resolution as _MatchedRoute;
    final matchedRequest = request._withPathParameters(matched.pathParameters);
    try {
      final response = await matched.registration.handler(dispatchContext, matchedRequest);
      return matched.suppressBody ? response._withoutBody() : response;
    } on MalformedBodyException {
      return Response.empty(status: HttpStatus.badRequest);
    } on BodyLimitExceededException {
      return Response.empty(status: HttpStatus.requestEntityTooLarge);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      final errorHandler = onError;
      if (errorHandler != null) {
        try {
          final response = await errorHandler(dispatchContext, matchedRequest, error, stackTrace);
          return matched.suppressBody ? response._withoutBody() : response;
        } on Object catch (hookError, hookStackTrace) {
          _report(hookError, hookStackTrace);
        }
      }
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

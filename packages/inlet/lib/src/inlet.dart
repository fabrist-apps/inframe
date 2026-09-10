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
  Inlet({Context? context, this.strict = true, this.onError, this.onReportError})
    : context = context ?? Context();

  /// The context used when a dispatch does not provide its own context.
  final Context context;

  /// Whether one trailing slash remains significant while matching.
  final bool strict;

  /// The optional application error hook.
  final ErrorHandler? onError;

  /// The optional unexpected-error reporter.
  final ErrorReporter? onReportError;

  /// Dispatches [request] without a network listener.
  Future<Response> handle(Request request, {Context? context}) async {
    request._admit();
    _freeze();
    final dispatchContext = context ?? this.context;
    final route = _routes.cast<_Route?>().firstWhere(
      (candidate) => candidate!.method == request.method && candidate.path == request.uri.path,
      orElse: () => null,
    );
    if (route == null) {
      return Response.empty(status: HttpStatus.notFound);
    }
    try {
      return await route.handler(dispatchContext, request);
    } on MalformedBodyException {
      return Response.empty(status: HttpStatus.badRequest);
    } on BodyLimitExceededException {
      return Response.empty(status: HttpStatus.requestEntityTooLarge);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      final errorHandler = onError;
      if (errorHandler != null) {
        try {
          return await errorHandler(dispatchContext, request, error, stackTrace);
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

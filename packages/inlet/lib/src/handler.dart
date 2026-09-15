import 'dart:async';

import 'package:context/context.dart';

import 'package:inlet/src/request.dart';
import 'package:inlet/src/response.dart';

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

/// Carries the response and latest forwarded values into transport delivery.
final class DispatchResult {
  /// Retains the values needed if delivery fails before committing headers.
  const DispatchResult(this.response, this.context, this.request);

  /// Response owned by the exchange until delivery and cleanup finish.
  final Response response;

  /// Latest context accepted by middleware.
  final Context context;

  /// Latest request view accepted by middleware.
  final Request request;
}

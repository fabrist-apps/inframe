import 'dart:async';

import 'package:context/context.dart';
import 'package:inlet/src/errors.dart';
import 'package:inlet/src/handler.dart';
import 'package:inlet/src/request.dart';
import 'package:inlet/src/response.dart';

/// Tracks forwarded values and reports cleanup failures for one dispatch.
final class DispatchState {
  /// Starts with the values supplied to the root middleware.
  DispatchState(this._context, this._request, this._report);

  Context _context;
  Request _request;
  final void Function(Object, StackTrace) _report;

  /// The latest context accepted by a continuation.
  Context get context => _context;

  /// The latest request view accepted by a continuation.
  Request get request => _request;

  /// Records valid forwarded values for error recovery.
  void forward(Context context, Request request) {
    _context = context;
    _request = request;
  }

  /// Reports unexpected failures unless a continuation already reported them.
  void reportUnexpected(Object error, StackTrace stackTrace) {
    if (isUnexpected(error) && !wasReported(error)) {
      _report(error, stackTrace);
    }
  }

  /// Reports and throws an invalid continuation use once.
  Never rejectContinuation(String message) {
    final error = ContinuationStateError(message, wasReported: true);
    _report(error, StackTrace.current);
    throw error;
  }

  /// Releases an abandoned downstream response when it becomes available.
  void observeOrphan(Future<Response> downstream) {
    Future<void> observe() async {
      try {
        final response = await downstream;
        await closeAndReport(response);
      } on Object catch (error, stackTrace) {
        reportUnexpected(error, stackTrace);
      }
    }

    unawaited(observe());
  }

  /// Releases a response without replacing the failure being handled.
  Future<void> closeAndReport(Response response) async {
    try {
      await response.close();
    } on Object catch (error, stackTrace) {
      reportUnexpected(error, stackTrace);
    }
  }
}

/// Runs a middleware chain while retaining ownership of abandoned work.
Future<Response> runMiddleware(
  List<Middleware> middleware,
  Handler terminal,
  DispatchState dispatch,
  Context context,
  Request request, [
  int index = 0,
]) {
  if (index == middleware.length) {
    try {
      return Future<Response>.value(terminal(context, request));
    } on Object catch (error, stackTrace) {
      return Future<Response>.error(error, stackTrace);
    }
  }

  return _MiddlewareInvocation(
    middleware,
    terminal,
    dispatch,
    request,
    index,
  ).run(context);
}

// Invocation lifetime is separate from downstream completion: next may be
// called once while active, and its work must settle before a response wins.
final class _MiddlewareInvocation {
  _MiddlewareInvocation(
    this.middleware,
    this.terminal,
    this.dispatch,
    this.request,
    this.index,
  );

  final List<Middleware> middleware;
  final Handler terminal;
  final DispatchState dispatch;
  final Request request;
  final int index;
  bool active = true;
  bool called = false;
  bool downstreamSettled = false;
  Future<Response>? downstream;

  Future<Response> next(Context forwardedContext, Request forwardedRequest) {
    if (!active) {
      dispatch.rejectContinuation(
        'next cannot be called after its middleware invocation has finished.',
      );
    }

    if (!forwardedRequest.isViewOf(request)) {
      dispatch.rejectContinuation(
        'next accepts only views of the current request.',
      );
    }

    if (called) {
      dispatch.rejectContinuation(
        'next can be called only once per middleware invocation.',
      );
    }

    called = true;
    dispatch.forward(forwardedContext, forwardedRequest);
    final future = runMiddleware(
      middleware,
      terminal,
      dispatch,
      forwardedContext,
      forwardedRequest,
      index + 1,
    );
    downstream = future;
    unawaited(
      future.then<void>(
        (_) => downstreamSettled = true,
        onError: (Object _, StackTrace _) {
          downstreamSettled = true;
        },
      ),
    );

    return future;
  }

  Future<Response> run(Context context) {
    late final FutureOr<Response> result;
    try {
      result = middleware[index](context, request, next);
    } on Object catch (error, stackTrace) {
      abandon();
      return Future<Response>.error(error, stackTrace);
    }

    if (result is Future<Response>) {
      return settle(result);
    }

    // A synchronous result closes next immediately, before any microtasks run.
    active = false;
    return finish(result);
  }

  Future<Response> settle(Future<Response> result) async {
    late final Response response;
    try {
      response = await result;
    } on Object {
      abandon();
      rethrow;
    }

    active = false;
    return finish(response);
  }

  void abandon() {
    active = false;
    if (called && !downstreamSettled) {
      dispatch.observeOrphan(downstream!);
    }
  }

  Future<Response> finish(Response response) async {
    if (!called || downstreamSettled) {
      return response;
    }

    await dispatch.closeAndReport(response);
    dispatch
      ..observeOrphan(downstream!)
      ..rejectContinuation(
        'Middleware finished before its downstream work completed.',
      );
  }
}

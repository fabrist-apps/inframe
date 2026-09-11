part of 'inlet.dart';

final class _DispatchState {
  _DispatchState(this._context, this._request, this._report);

  Context _context;
  Request _request;
  final void Function(Object, StackTrace) _report;

  Context get context => _context;
  Request get request => _request;

  void forward(Context context, Request request) {
    _context = context;
    _request = request;
  }

  void reportUnexpected(Object error, StackTrace stackTrace) {
    if (_isUnexpected(error) && !_wasReported(error)) {
      _report(error, stackTrace);
    }
  }

  Never rejectContinuation(String message) {
    final error = _ContinuationStateError(message, wasReported: true);
    _report(error, StackTrace.current);
    throw error;
  }
}

final class _ContinuationStateError extends StateError {
  _ContinuationStateError(super.message, {this.wasReported = false});

  final bool wasReported;
}

Future<Response> _runMiddleware(
  List<Middleware> middleware,
  Handler terminal,
  _DispatchState dispatch,
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

  var active = true;
  var called = false;
  var downstreamSettled = false;
  Future<Response>? downstream;

  Future<Response> next(Context forwardedContext, Request forwardedRequest) {
    if (!active) {
      dispatch.rejectContinuation(
        'next cannot be called after its middleware invocation has finished.',
      );
    }
    if (!forwardedRequest._isViewOf(request)) {
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
    final future = _runMiddleware(
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

  late final FutureOr<Response> result;
  try {
    result = middleware[index](context, request, next);
  } on Object catch (error, stackTrace) {
    active = false;
    if (called && !downstreamSettled) {
      _observeOrphan(downstream!, dispatch);
    }
    return Future<Response>.error(error, stackTrace);
  }

  if (result is Future<Response>) {
    Future<Response> settle() async {
      late final Response response;
      try {
        response = await result;
      } on Object catch (error, stackTrace) {
        active = false;
        if (called && !downstreamSettled) {
          _observeOrphan(downstream!, dispatch);
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      active = false;
      return _finishMiddleware(
        response,
        called: called,
        downstreamSettled: downstreamSettled,
        downstream: downstream,
        dispatch: dispatch,
      );
    }

    return settle();
  }

  active = false;
  return _finishMiddleware(
    result,
    called: called,
    downstreamSettled: downstreamSettled,
    downstream: downstream,
    dispatch: dispatch,
  );
}

Future<Response> _finishMiddleware(
  Response response, {
  required bool called,
  required bool downstreamSettled,
  required Future<Response>? downstream,
  required _DispatchState dispatch,
}) async {
  if (!called || downstreamSettled) {
    return response;
  }

  await _closeAndReport(response, dispatch);
  _observeOrphan(downstream!, dispatch);
  dispatch.rejectContinuation(
    'Middleware finished before its downstream work completed.',
  );
}

void _observeOrphan(Future<Response> downstream, _DispatchState dispatch) {
  Future<void> observe() async {
    try {
      final response = await downstream;
      await _closeAndReport(response, dispatch);
    } on Object catch (error, stackTrace) {
      dispatch.reportUnexpected(error, stackTrace);
    }
  }

  unawaited(observe());
}

Future<void> _closeAndReport(Response response, _DispatchState dispatch) async {
  try {
    await response.close();
  } on Object catch (error, stackTrace) {
    dispatch.reportUnexpected(error, stackTrace);
  }
}

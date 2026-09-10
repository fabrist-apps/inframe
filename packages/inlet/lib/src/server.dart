part of 'inlet.dart';

/// A bound listener owned by an [Inlet] application.
final class InletServer {
  InletServer._(this._server, this._adapter, {required this.isSecure})
    : address = _server.address,
      port = _server.port;

  final HttpServer _server;
  final _ServerAdapter _adapter;

  /// The address selected by the operating system.
  final InternetAddress address;

  /// The port selected by the operating system.
  final int port;

  /// Whether this listener accepts TLS connections.
  final bool isSecure;

  Future<void>? _closeFuture;
  bool _forced = false;

  /// Stops request admission, optionally closing active connections.
  Future<void> close({bool force = false}) {
    _adapter.beginClosing();
    if (force && !_forced) {
      _forced = true;
      final forceClose = _server.close(force: true);
      final existing = _closeFuture;
      if (existing != null) {
        unawaited(
          forceClose.then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              _adapter.report(error, stackTrace);
            },
          ),
        );
        return existing;
      }
      return _closeFuture = forceClose;
    }
    return _closeFuture ??= _server.close();
  }
}

extension on Inlet {
  Future<InletServer> _startServer({
    required InternetAddress? address,
    required int port,
    required int backlog,
    required bool shared,
    required Duration? idleTimeout,
    required bool isSecure,
    required Future<HttpServer> Function(InternetAddress address) bind,
  }) async {
    _validateServerOptions(port, backlog, idleTimeout);
    final bindAddress = address ?? InternetAddress.loopbackIPv4;
    final server = await _freezeAfter(() => bind(bindAddress));
    server
      ..autoCompress = false
      ..idleTimeout = idleTimeout;
    server.defaultResponseHeaders.clear();

    final adapter = _ServerAdapter(
      server,
      _dispatch,
      _recover,
      _report,
      isSecure: isSecure,
    );
    try {
      adapter.start();
    } on Object {
      await server.close(force: true);
      rethrow;
    }
    return InletServer._(server, adapter, isSecure: isSecure);
  }
}

final class _ServerAdapter {
  _ServerAdapter(
    this._server,
    this._dispatch,
    this._recover,
    this._report, {
    required this.isSecure,
  });

  final HttpServer _server;
  final bool isSecure;
  final Future<_DispatchResult> Function(Request request) _dispatch;
  final Future<Response> Function(
    Context context,
    Request request,
    Object error,
    StackTrace stackTrace,
  )
  _recover;
  final void Function(Object, StackTrace) _report;

  bool _closing = false;

  void start() {
    _server.listen(_accept, onError: _report);
  }

  void beginClosing() {
    _closing = true;
  }

  void report(Object error, StackTrace stackTrace) => _report(error, stackTrace);

  void _accept(HttpRequest request) => unawaited(_handle(request));

  Future<void> _handle(HttpRequest incoming) async {
    if (_closing) {
      await _sendEmpty(incoming.response, HttpStatus.serviceUnavailable);
      return;
    }

    final input = _HttpRequestBody(incoming);
    late final Request request;
    try {
      request = _adapt(incoming, input);
    } on Object {
      try {
        await _sendEmpty(incoming.response, HttpStatus.badRequest);
      } on Object catch (deliveryError, deliveryStackTrace) {
        _report(deliveryError, deliveryStackTrace);
      } finally {
        await _finishInput(input);
      }
      return;
    }

    _DispatchResult? dispatch;
    Response? response;
    try {
      dispatch = await _dispatch(request);
      response = dispatch.response;
      await _deliver(incoming.response, response, input);
    } on _DeliveryFailure catch (failure) {
      if (failure.committed || dispatch == null) {
        _report(failure.error, failure.stackTrace);
      } else {
        await _close(response!);
        response = await _recover(
          dispatch.context,
          dispatch.request,
          failure.error,
          failure.stackTrace,
        );
        try {
          await _deliver(incoming.response, response, input);
        } on _DeliveryFailure catch (replacementFailure) {
          _report(replacementFailure.error, replacementFailure.stackTrace);
        }
      }
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      try {
        await _sendEmpty(incoming.response, HttpStatus.internalServerError);
      } on Object catch (deliveryError, deliveryStackTrace) {
        _report(deliveryError, deliveryStackTrace);
      }
    } finally {
      if (response != null) {
        await _close(response);
      }
      await _close(request);
      await _finishInput(input);
    }
  }

  Request _adapt(HttpRequest incoming, _HttpRequestBody input) {
    final rawHeaders = <String, List<String>>{};
    incoming.headers.forEach((name, values) {
      rawHeaders[name] = List.of(values);
    });
    final socket = incoming.connectionInfo;
    final connection = socket == null
        ? null
        : ConnectionInfo(
            remoteAddress: socket.remoteAddress,
            remotePort: socket.remotePort,
            localPort: socket.localPort,
            isSecure: isSecure,
          );
    return Request(
      method: incoming.method,
      uri: incoming.uri,
      headers: Headers.from(rawHeaders),
      body: input,
      connection: connection,
    );
  }

  Future<void> _deliver(
    HttpResponse target,
    Response response,
    _HttpRequestBody input,
  ) async {
    var committed = false;
    try {
      if (!input.isComplete) {
        input.pause();
        target.persistentConnection = false;
      }
      target
        ..statusCode = response.statusCode
        ..bufferOutput = false;
      for (final MapEntry(key: name, value: values) in response.headers.toMap().entries) {
        for (final value in values) {
          target.headers.add(name, value);
        }
      }
      final knownLength = response._body.knownLength;
      if (knownLength != null) {
        target.contentLength = response._suppressBody ? 0 : knownLength;
      }
      final delivery = target.addStream(response.body);
      committed = true;
      await delivery;
      await target.close();
    } on Object catch (error, stackTrace) {
      throw _DeliveryFailure(error, stackTrace, committed: committed);
    }
  }

  Future<void> _sendEmpty(HttpResponse response, int status) async {
    response
      ..statusCode = status
      ..contentLength = 0;
    await response.close();
  }

  Future<void> _close(Object value) async {
    try {
      switch (value) {
        case final Request request:
          await request.close();
        case final Response response:
          await response.close();
      }
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  Future<void> _finishInput(_HttpRequestBody input) async {
    try {
      await input.finish();
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }
}

final class _DeliveryFailure implements Exception {
  const _DeliveryFailure(
    this.error,
    this.stackTrace, {
    required this.committed,
  });

  final Object error;
  final StackTrace stackTrace;
  final bool committed;
}

final class _HttpRequestBody extends Stream<List<int>> {
  _HttpRequestBody(HttpRequest request) {
    try {
      _subscription = request.listen(
        _add,
        onError: _addError,
        onDone: _complete,
        cancelOnError: false,
      );
      _pausePhysical();
      final hasNoBody =
          request.contentLength == 0 ||
          (request.contentLength < 0 && !request.headers.chunkedTransferEncoding);
      if (hasNoBody) {
        _resumePhysical();
        _completeCleanly = true;
      }
    } on Object catch (_, stackTrace) {
      _terminalError = const MalformedBodyException();
      _terminalStackTrace = stackTrace;
    }
  }

  StreamSubscription<List<int>>? _subscription;
  StreamController<List<int>>? _controller;
  Object? _terminalError;
  StackTrace? _terminalStackTrace;
  bool _listened = false;
  bool _completeCleanly = false;
  bool _paused = false;
  Future<void>? _finishFuture;

  bool get isComplete => _completeCleanly;

  void pause() {
    if (!_completeCleanly) {
      _pausePhysical();
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_listened) {
      throw StateError('The HTTP request body can be listened to only once.');
    }
    _listened = true;

    final controller = StreamController<List<int>>(sync: true);
    _controller = controller;
    controller
      ..onPause = _pausePhysical
      ..onResume = _resumePhysical
      ..onCancel = _pauseAfterCancellation;
    final downstream = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError ?? false,
    );

    final terminalError = _terminalError;
    if (terminalError != null) {
      controller.addError(terminalError, _terminalStackTrace);
      unawaited(controller.close());
    } else if (_completeCleanly) {
      unawaited(controller.close());
    } else {
      _resumePhysical();
    }
    return downstream;
  }

  void _add(List<int> chunk) {
    _controller?.add(chunk);
  }

  void _addError(Object _, StackTrace stackTrace) {
    if (_terminalError != null || _completeCleanly) {
      return;
    }
    _terminalError = const MalformedBodyException();
    _terminalStackTrace = stackTrace;
    final controller = _controller;
    if (controller != null) {
      controller.addError(_terminalError!, stackTrace);
      unawaited(controller.close());
    }
  }

  void _complete() {
    if (_terminalError != null || _completeCleanly) {
      return;
    }
    _completeCleanly = true;
    final close = _controller?.close();
    if (close != null) {
      unawaited(close);
    }
  }

  Future<void> _pauseAfterCancellation() async {
    pause();
  }

  void _pausePhysical() {
    if (_paused || _completeCleanly) {
      return;
    }
    _paused = true;
    _subscription?.pause();
  }

  void _resumePhysical() {
    if (!_paused || _completeCleanly) {
      return;
    }
    _paused = false;
    _subscription?.resume();
  }

  Future<void> finish() {
    final existing = _finishFuture;
    if (existing != null) {
      return existing;
    }
    if (_completeCleanly) {
      return _finishFuture = Future<void>.value();
    }
    final subscription = _subscription;
    return _finishFuture = subscription == null ? Future<void>.value() : subscription.cancel();
  }
}

void _validateServerOptions(int port, int backlog, Duration? idleTimeout) {
  _validatePort(port, 'port');
  if (backlog < 0) {
    throw ArgumentError.value(backlog, 'backlog', 'must not be negative');
  }
  if (idleTimeout != null && idleTimeout.isNegative) {
    throw ArgumentError.value(
      idleTimeout,
      'idleTimeout',
      'must not be negative',
    );
  }
}

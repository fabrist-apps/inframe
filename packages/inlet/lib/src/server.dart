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

  /// Stops request admission, optionally closing active HTTP connections.
  ///
  /// Upgraded WebSockets are detached from the listener. This method neither
  /// closes them nor waits for their session callbacks.
  Future<void> close({bool force = false}) {
    _adapter.beginClosing(force: force);
    if (force && !_forced) {
      _forced = true;
      final forceClose = _closeTransport(force: true);
      _observeAdditionalClose(forceClose);
      final existing = _closeFuture;
      if (existing != null) {
        return existing;
      }
      return _closeFuture = forceClose;
    }
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }

    final closing = Completer<void>();
    _closeFuture = closing.future;
    Timer.run(() async {
      try {
        await _closeTransport(force: false);
        closing.complete();
      } on Object catch (error, stackTrace) {
        _adapter.report(error, stackTrace);
        closing.completeError(error, stackTrace);
      }
    });
    return closing.future;
  }

  Future<void> _closeTransport({required bool force}) =>
      Future<void>.sync(() => _server.close(force: force));

  void _observeAdditionalClose(Future<void> close) {
    unawaited(
      close.then<void>(
        (_) {},
        onError: _adapter.report,
      ),
    );
  }
}

extension on Inlet {
  Future<InletServer> _startServer({
    required InternetAddress? address,
    required int port,
    required int backlog,
    required Duration? idleTimeout,
    required bool isSecure,
    required Future<HttpServer> Function(InternetAddress address) bind,
  }) async {
    _validateServerOptions(port, backlog, idleTimeout);
    final bindAddress = address ?? InternetAddress.loopbackIPv4;
    return _freezeAfter(() async {
      HttpServer? server;
      try {
        server = (await bind(bindAddress))
          ..autoCompress = false
          ..idleTimeout = idleTimeout
          ..defaultResponseHeaders.clear();

        final adapter = _ServerAdapter(
          server,
          _dispatch,
          _recover,
          _report,
          isSecure: isSecure,
        )..start();
        return InletServer._(server, adapter, isSecure: isSecure);
      } on Object catch (error, stackTrace) {
        if (server != null) {
          try {
            await server.close(force: true);
          } on Object catch (cleanupError, cleanupStackTrace) {
            _report(cleanupError, cleanupStackTrace);
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
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
  bool _forceClosing = false;
  final Set<_DetachedSseResponse> _detachedResponses = {};

  void start() {
    _server.listen(_accept, onError: _report);
  }

  void beginClosing({required bool force}) {
    _closing = true;
    if (!force || _forceClosing) {
      return;
    }
    _forceClosing = true;
    final responses = _detachedResponses.toList();
    _detachedResponses.clear();
    for (final response in responses) {
      response.abort().ignore();
    }
  }

  void report(Object error, StackTrace stackTrace) => _report(error, stackTrace);

  void _accept(HttpRequest request) => unawaited(_handle(request));

  Future<void> _handle(HttpRequest incoming) async {
    final input = _HttpRequestBody(incoming);
    if (_closing) {
      try {
        await _sendEmpty(
          incoming.response,
          HttpStatus.serviceUnavailable,
          input,
          closeConnection: true,
        );
      } on Object catch (error, stackTrace) {
        _report(error, stackTrace);
      } finally {
        await _cleanUp(input.finish);
      }
      return;
    }

    late final Request request;
    try {
      request = _adapt(incoming, input);
    } on Object {
      try {
        await _sendEmpty(incoming.response, HttpStatus.badRequest, input);
      } on Object catch (deliveryError, deliveryStackTrace) {
        _report(deliveryError, deliveryStackTrace);
      } finally {
        await _cleanUp(input.finish);
      }
      return;
    }

    _DispatchResult? dispatch;
    Response? response;
    try {
      dispatch = await _dispatch(request);
      response = dispatch.response;
      await _deliver(
        incoming,
        response,
        input,
        isHead: dispatch.request.method == 'HEAD',
      );
    } on _DeliveryFailure catch (failure) {
      if (failure.committed || dispatch == null) {
        _report(failure.error, failure.stackTrace);
      } else {
        await _cleanUp(response!.close);
        response = await _recover(
          dispatch.context,
          dispatch.request,
          failure.error,
          failure.stackTrace,
        );
        if (response.isWebSocketUpgrade) {
          await _cleanUp(response.close);
          response = Response.empty(status: HttpStatus.internalServerError);
        }
        try {
          await _deliver(
            incoming,
            response,
            input,
            isHead: dispatch.request.method == 'HEAD',
            resetTarget: true,
          );
        } on _DeliveryFailure catch (replacementFailure) {
          _report(replacementFailure.error, replacementFailure.stackTrace);
          if (!replacementFailure.committed) {
            await _cleanUp(() => _abortUncommitted(incoming.response));
          }
        }
      }
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      try {
        await _sendEmpty(
          incoming.response,
          HttpStatus.internalServerError,
          input,
        );
      } on Object catch (deliveryError, deliveryStackTrace) {
        _report(deliveryError, deliveryStackTrace);
      }
    } finally {
      if (response != null) {
        await _cleanUp(response.close);
      }
      await _cleanUp(request.close);
      if (!input.isFinishStarted) {
        await _cleanUp(input.finish);
      }
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
    HttpRequest incoming,
    Response response,
    _HttpRequestBody input, {
    required bool isHead,
    bool resetTarget = false,
  }) async {
    final target = incoming.response;
    var committed = false;
    Socket? detachedSocket;
    _DetachedSseResponse? detachedResponse;
    try {
      if (response._delivery case final _WebSocketDelivery webSocket) {
        if (incoming.method != 'GET' ||
            isHead ||
            !WebSocketTransformer.isUpgradeRequest(incoming)) {
          throw const _WebSocketHandshakeRejected(
            'Invalid WebSocket upgrade request.',
          );
        }
        if (!response._body.isUntouched) {
          throw StateError('The WebSocket response has already been closed.');
        }
        final offeredProtocols = _parseWebSocketProtocols(incoming.headers);
        final selectedProtocol = await _selectWebSocketProtocol(
          webSocket.selectProtocol,
          offeredProtocols,
        );
        _prepareWebSocketTarget(target, response.headers);

        final upgrading = WebSocketTransformer.upgrade(
          incoming,
          protocolSelector: selectedProtocol == null ? null : (_) => selectedProtocol,
          compression: webSocket.compression,
          maxPayloadLength: webSocket.maxFrameBytes,
        );
        committed = true;
        final socket = await upgrading;

        // The WebSocket owns the detached transport before the obsolete HTTP
        // request subscription is cancelled.
        await _cleanUp(input.finish);
        await _runWebSocketSession(socket, webSocket);
        return;
      }

      final suppressBody = response._suppressBody || isHead;
      if (!suppressBody && !response._body.isUntouched) {
        throw StateError('The response body has already been consumed or closed.');
      }
      _prepareTarget(target, input, reset: resetTarget);
      target.statusCode = response.statusCode;
      _applyResponseHeaders(target, response.headers);
      final knownLength = response._body.knownLength;
      if (response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.notModified) {
        target.persistentConnection = false;
        target.headers.chunkedTransferEncoding = false;
        final detached = target.detachSocket();
        committed = true;
        final socket = await detached;
        await socket.close();
        return;
      }
      if (response.statusCode == HttpStatus.resetContent) {
        target.contentLength = 0;
        final close = target.close();
        committed = true;
        await close;
        return;
      }
      if (isHead) {
        target.headers.chunkedTransferEncoding = false;
        if (knownLength != null) {
          target.contentLength = knownLength;
        }
        final close = target.close();
        committed = true;
        await close;
        return;
      }
      if (response._delivery is _SseDelivery) {
        target
          ..persistentConnection = false
          ..headers.chunkedTransferEncoding = false;
        final detach = target.detachSocket();
        committed = true;
        detachedSocket = await detach;
        final events = StreamIterator(response.body);
        detachedResponse = _DetachedSseResponse(detachedSocket, events);
        if (!_ownDetachedResponse(detachedResponse)) {
          detachedResponse = null;
          detachedSocket = null;
          return;
        }
        await detachedSocket.flush();
        while (await events.moveNext()) {
          detachedSocket.add(events.current);
          await detachedSocket.flush();
        }
        await detachedSocket.close();
        _detachedResponses.remove(detachedResponse);
        detachedResponse = null;
        detachedSocket = null;
        return;
      }
      if (knownLength != null) {
        target.contentLength = knownLength;
      }
      final delivery = target.addStream(response.body);
      committed = true;
      await delivery;
      await target.close();
    } on Object catch (error, stackTrace) {
      final ownedResponse = detachedResponse;
      if (ownedResponse == null) {
        detachedSocket?.destroy();
      } else {
        _detachedResponses.remove(ownedResponse);
        ownedResponse.abort().ignore();
      }
      throw _DeliveryFailure(error, stackTrace, committed: committed);
    }
  }

  void _prepareWebSocketTarget(HttpResponse target, Headers headers) {
    target.bufferOutput = false;
    _applyResponseHeaders(target, headers);
  }

  void _applyResponseHeaders(HttpResponse target, Headers headers) {
    for (final MapEntry(key: name, value: values) in headers.toMap().entries) {
      for (final value in values) {
        target.headers.add(name, value);
      }
    }
  }

  Future<void> _runWebSocketSession(
    WebSocket socket,
    _WebSocketDelivery delivery,
  ) async {
    try {
      await delivery.onConnect(socket);
      await _closeWebSocket(socket, WebSocketStatus.normalClosure);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      await _closeWebSocket(socket, WebSocketStatus.internalServerError);
    }
  }

  Future<String?> _selectWebSocketProtocol(
    WebSocketProtocolSelector? selector,
    List<String> offeredProtocols,
  ) async {
    if (selector == null) {
      return null;
    }

    late final String? selectedProtocol;
    try {
      selectedProtocol = await selector(offeredProtocols);
    } on WebSocketException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _WebSocketHandshakeRejected(error.message),
        stackTrace,
      );
    }
    if (selectedProtocol != null && !offeredProtocols.contains(selectedProtocol)) {
      throw StateError(
        'Selected WebSocket protocol "$selectedProtocol" was not offered.',
      );
    }
    return selectedProtocol;
  }

  Future<void> _closeWebSocket(WebSocket socket, int code) async {
    if (socket.readyState != WebSocket.open) {
      return;
    }
    try {
      await socket.close(code);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }

  bool _ownDetachedResponse(_DetachedSseResponse response) {
    if (_forceClosing) {
      response.abort().ignore();
      return false;
    }
    _detachedResponses.add(response);
    return true;
  }

  Future<void> _sendEmpty(
    HttpResponse response,
    int status,
    _HttpRequestBody input, {
    bool closeConnection = false,
  }) async {
    _prepareTarget(response, input, closeConnection: closeConnection);
    response
      ..statusCode = status
      ..contentLength = 0;
    await response.close();
  }

  void _prepareTarget(
    HttpResponse target,
    _HttpRequestBody input, {
    bool closeConnection = false,
    bool reset = false,
  }) {
    if (reset) {
      final wasPersistent = target.persistentConnection;
      final wasChunked = target.headers.chunkedTransferEncoding;
      target.headers.clear();
      target
        ..statusCode = HttpStatus.ok
        ..persistentConnection = wasPersistent;
      target.headers.chunkedTransferEncoding = wasChunked;
    }
    target.bufferOutput = false;
    if (closeConnection || !input.isComplete) {
      input.pause();
      target.persistentConnection = false;
    }
  }

  Future<void> _abortUncommitted(HttpResponse response) async {
    final socket = await response.detachSocket(writeHeaders: false);
    socket.destroy();
  }

  Future<void> _cleanUp(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
  }
}

final class _DetachedSseResponse {
  _DetachedSseResponse(this.socket, this.events);

  final Socket socket;
  final StreamIterator<List<int>> events;

  Future<void>? _abortFuture;

  Future<void> abort() => _abortFuture ??= _abort();

  Future<void> _abort() async {
    socket.destroy();
    await events.cancel();
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

final class _WebSocketHandshakeRejected extends WebSocketException {
  const _WebSocketHandshakeRejected(super.message);
}

List<String> _parseWebSocketProtocols(HttpHeaders headers) {
  final values = headers['sec-websocket-protocol'];
  if (values == null) {
    return const [];
  }

  final protocols = <String>[];
  for (final value in values) {
    for (final rawProtocol in value.split(',')) {
      final protocol = rawProtocol.trim();
      if (!_isWebSocketProtocolToken(protocol)) {
        throw const _WebSocketHandshakeRejected(
          'Invalid Sec-WebSocket-Protocol header.',
        );
      }
      protocols.add(protocol);
    }
  }
  return List.unmodifiable(protocols);
}

bool _isWebSocketProtocolToken(String value) {
  if (value.isEmpty) {
    return false;
  }
  const separators = <int>{
    0x28,
    0x29,
    0x3c,
    0x3e,
    0x40,
    0x2c,
    0x3b,
    0x3a,
    0x5c,
    0x22,
    0x2f,
    0x5b,
    0x5d,
    0x3f,
    0x3d,
    0x7b,
    0x7d,
  };
  return value.codeUnits.every(
    (unit) => unit > 0x20 && unit < 0x7f && !separators.contains(unit),
  );
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
    } on Object catch (error, stackTrace) {
      _terminalError = error;
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

  bool get isFinishStarted => _finishFuture != null;

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
      ..onCancel = pause;
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

  void _addError(Object error, StackTrace stackTrace) {
    if (_terminalError != null || _completeCleanly) {
      return;
    }
    _terminalError = error;
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

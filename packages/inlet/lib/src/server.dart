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

    late final Request request;
    try {
      request = _adapt(incoming);
    } on Object {
      await _sendEmpty(incoming.response, HttpStatus.badRequest);
      return;
    }

    _DispatchResult? dispatch;
    Response? response;
    try {
      dispatch = await _dispatch(request);
      response = dispatch.response;
      await _deliver(incoming.response, response);
    } on Object catch (error, stackTrace) {
      if (dispatch == null) {
        _report(error, stackTrace);
        await _sendEmpty(incoming.response, HttpStatus.internalServerError);
      } else {
        final replacement = await _recover(
          dispatch.context,
          dispatch.request,
          error,
          stackTrace,
        );
        response = replacement;
        try {
          await _deliver(incoming.response, replacement);
        } on Object catch (replacementError, replacementStackTrace) {
          _report(replacementError, replacementStackTrace);
        }
      }
    } finally {
      if (response != null) {
        await _close(response);
      }
      await _close(request);
    }
  }

  Request _adapt(HttpRequest incoming) {
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
      body: incoming,
      connection: connection,
    );
  }

  Future<void> _deliver(HttpResponse target, Response response) async {
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
    await target.addStream(response.body);
    await target.close();
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

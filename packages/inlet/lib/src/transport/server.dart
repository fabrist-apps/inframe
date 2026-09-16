import 'dart:async';
import 'dart:io';

import 'package:inlet/src/handler.dart';
import 'package:inlet/src/http_token.dart';
import 'package:inlet/src/request.dart';
import 'package:inlet/src/transport/http_exchange.dart';
import 'package:inlet/src/transport/sse.dart';

/// A bound listener owned by an Inlet application.
final class InletServer {
  InletServer._(this._server, this._adapter, {required this.isSecure})
    : address = _server.address,
      port = _server.port;

  final HttpServer _server;
  final _HttpAdapter _adapter;

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
  /// Normal close leaves active HTTP exchanges to finish; its future marks
  /// the admission boundary, not handler completion. Later forced calls close
  /// active HTTP and SSE connections while returning the first close future.
  Future<void> close({bool force = false}) {
    _adapter.beginClosing(force: force);

    if (force && !_forced) {
      _forced = true;
      // Escalation closes active connections without replacing the shared future.
      final forceClose = _closeTransport(force: true);
      _observeAdditionalClose(forceClose);

      return _closeFuture ??= forceClose;
    }

    final existing = _closeFuture;

    if (existing != null) {
      return existing;
    }

    final closing = Completer<void>();
    _closeFuture = closing.future;

    // Defer transport shutdown so requests already queued can receive 503.
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

/// Listener construction access, excluded from the package entrypoint.
extension InletServerRuntime on InletServer {
  /// Binds and configures a listener, closing it if setup fails.
  static Future<InletServer> bind({
    required Future<HttpServer> Function() bind,
    required Duration? idleTimeout,
    required bool isSecure,
    required Future<DispatchResult> Function(Request) dispatch,
    required ErrorHandler recover,
    required ErrorReporter report,
  }) async {
    HttpServer? server;
    try {
      server = (await bind())
        ..autoCompress = false
        ..idleTimeout = idleTimeout
        ..defaultResponseHeaders.clear();
      final adapter = _HttpAdapter(server, dispatch, recover, report, isSecure: isSecure)..start();
      return InletServer._(server, adapter, isSecure: isSecure);
    } on Object {
      if (server != null) {
        try {
          await server.close(force: true);
        } on Object catch (cleanupError, cleanupStackTrace) {
          report(cleanupError, cleanupStackTrace);
        }
      }
      rethrow;
    }
  }

  /// Rejects invalid options before a caller freezes its routes or binds.
  static void validateOptions(int port, int backlog, Duration? idleTimeout) {
    validatePort(port, 'port');

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
}

/// Admits HTTP exchanges and owns this listener's detached SSE connections.
final class _HttpAdapter {
  /// Shares dispatch and error policy across independently owned exchanges.
  _HttpAdapter(this._server, this._dispatch, this._recover, this.report, {required this.isSecure});

  final HttpServer _server;
  final Future<DispatchResult> Function(Request) _dispatch;
  final ErrorHandler _recover;

  /// Observes listener, exchange, and cleanup failures.
  final ErrorReporter report;

  /// Whether connection metadata should identify this listener as TLS.
  final bool isSecure;
  final SseConnections _sse = SseConnections();
  bool _closing = false;

  /// Starts accepting exchanges without waiting for preceding handlers.
  void start() => _server.listen(_accept, onError: report);

  /// Rejects new admissions and optionally aborts detached SSE connections.
  void beginClosing({required bool force}) {
    _closing = true;
    if (force) _sse.abort();
  }

  void _accept(HttpRequest request) => unawaited(
    HttpExchange(
      request,
      _dispatch,
      _recover,
      report,
      _sse,
      isSecure: isSecure,
      isClosing: _closing,
    ).run(),
  );
}

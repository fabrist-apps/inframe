import 'dart:async';
import 'dart:io';

import 'package:inlet/src/handler.dart';
import 'package:inlet/src/headers.dart';
import 'package:inlet/src/request.dart';
import 'package:inlet/src/response.dart';
import 'package:inlet/src/transport/request_body.dart';
import 'package:inlet/src/transport/sse.dart';
import 'package:inlet/src/transport/web_socket.dart';

/// Owns one HTTP exchange, including replacement responses and commit state.
///
/// A response may be replaced only before transport delivery commits. Cleanup
/// closes the latest response before its request, which may supply its stream.
final class HttpExchange {
  /// Captures admission state before dispatch begins.
  HttpExchange(
    this._incoming,
    this._dispatch,
    this._recover,
    this._report,
    this._sse, {
    required this._isSecure,
    required this._isClosing,
  }) : _input = HttpRequestBody(_incoming),
       _webSockets = WebSocketSession(_report);

  final HttpRequest _incoming;
  final HttpRequestBody _input;
  final bool _isSecure;
  final bool _isClosing;
  final Future<DispatchResult> Function(Request) _dispatch;
  final ErrorHandler _recover;
  final ErrorReporter _report;
  final SseConnections _sse;
  final WebSocketSession _webSockets;
  Response? _response;
  bool _committed = false;

  /// Dispatches once and releases response resources before the upload.
  Future<void> run() async {
    if (_isClosing) {
      try {
        await _sendEmpty(HttpStatus.serviceUnavailable, closeConnection: true);
      } on Object catch (error, stackTrace) {
        _report(error, stackTrace);
      } finally {
        await _cleanUp(_input.finish);
      }
      return;
    }
    late final Request request;
    try {
      request = _adapt();
    } on Object {
      try {
        await _sendEmpty(HttpStatus.badRequest);
      } on Object catch (error, stackTrace) {
        _report(error, stackTrace);
      } finally {
        await _cleanUp(_input.finish);
      }
      return;
    }
    try {
      late final DispatchResult dispatch;
      try {
        dispatch = await _dispatch(request);
      } on Object catch (error, stackTrace) {
        _report(error, stackTrace);
        try {
          await _sendEmpty(HttpStatus.internalServerError);
        } on Object catch (deliveryError, deliveryStackTrace) {
          _report(deliveryError, deliveryStackTrace);
        }
        return;
      }
      await _deliverWithRecovery(dispatch);
    } finally {
      if (_response case final response?) {
        await _cleanUp(response.close);
      }
      await _cleanUp(request.close);
      if (!_input.isFinishStarted) {
        await _cleanUp(_input.finish);
      }
    }
  }

  Future<void> _deliverWithRecovery(DispatchResult dispatch) async {
    final isHead = dispatch.request.method == 'HEAD';
    _response = dispatch.response;
    try {
      await _deliver(dispatch.response, isHead: isHead);
    } on Object catch (error, stackTrace) {
      if (_committed) {
        _report(error, stackTrace);
        return;
      }
      await _cleanUp(dispatch.response.close);
      var replacement = await _recover(dispatch.context, dispatch.request, error, stackTrace);
      if (replacement.isWebSocketUpgrade) {
        await _cleanUp(replacement.close);
        replacement = Response.empty(status: HttpStatus.internalServerError);
      }
      _response = replacement;
      try {
        await _deliver(replacement, isHead: isHead, resetTarget: true);
      } on Object catch (replacementError, replacementStackTrace) {
        _report(replacementError, replacementStackTrace);
        if (!_committed) {
          await _cleanUp(_abortUncommitted);
        }
      }
    }
  }

  Request _adapt() {
    final rawHeaders = <String, List<String>>{};
    _incoming.headers.forEach((name, values) {
      rawHeaders[name] = List.of(values);
    });
    final socket = _incoming.connectionInfo;
    final connection = socket == null
        ? null
        : ConnectionInfo(
            remoteAddress: socket.remoteAddress,
            remotePort: socket.remotePort,
            localPort: socket.localPort,
            isSecure: _isSecure,
          );

    return Request(
      method: _incoming.method,
      uri: _incoming.uri,
      headers: Headers.from(rawHeaders),
      body: _input,
      connection: connection,
    );
  }

  Future<void> _deliver(
    Response response, {
    required bool isHead,
    bool resetTarget = false,
  }) async {
    final target = _incoming.response;

    if (response.delivery case final WebSocketDelivery webSocket) {
      final selectedProtocol = await _webSockets.preflight(_incoming, webSocket, isHead: isHead);
      target.bufferOutput = false;
      _applyResponseHeaders(target, response.headers);

      final upgrading = WebSocketTransformer.upgrade(
        _incoming,
        protocolSelector: selectedProtocol == null ? null : (_) => selectedProtocol,
        compression: webSocket.compression,
        maxPayloadLength: webSocket.maxFrameBytes,
      );
      _committed = true;
      final socket = await upgrading;

      // The WebSocket owns the detached transport before the obsolete HTTP
      // request subscription is cancelled.
      await _cleanUp(_input.finish);
      await _webSockets.run(socket, webSocket);
      return;
    }

    final content = response.delivery as ContentDelivery;
    final suppressBody = response.suppressBody || isHead;

    if (!suppressBody && !content.body.isUntouched) {
      throw StateError('The response body has already been consumed or closed.');
    }

    _prepareTarget(reset: resetTarget);
    target.statusCode = response.statusCode;
    _applyResponseHeaders(target, response.headers);
    final knownLength = content.body.knownLength;

    if (response.statusCode == HttpStatus.noContent ||
        response.statusCode == HttpStatus.notModified) {
      target.persistentConnection = false;
      target.headers.chunkedTransferEncoding = false;
      final detached = target.detachSocket();
      _committed = true;
      final socket = await detached;
      await socket.close();
      return;
    }

    if (response.statusCode == HttpStatus.resetContent) {
      target.contentLength = 0;
      final close = target.close();
      _committed = true;
      await close;
      return;
    }

    if (isHead) {
      target.headers.chunkedTransferEncoding = false;

      if (knownLength != null) {
        target.contentLength = knownLength;
      }

      final close = target.close();
      _committed = true;
      await close;
      return;
    }

    if (content.flushEvents) {
      target
        ..persistentConnection = false
        ..headers.chunkedTransferEncoding = false;
      final detach = target.detachSocket();
      _committed = true;
      await _sse.deliver(await detach, response.body);
      return;
    }

    if (knownLength != null) {
      target.contentLength = knownLength;
    }

    final delivery = target.addStream(response.body);
    _committed = true;
    await delivery;
    await target.close();
  }

  void _applyResponseHeaders(HttpResponse target, Headers headers) {
    for (final MapEntry(key: name, value: values) in headers.toMap().entries) {
      for (final value in values) {
        target.headers.add(name, value);
      }
    }
  }

  Future<void> _sendEmpty(
    int status, {
    bool closeConnection = false,
  }) async {
    final response = _incoming.response;
    _prepareTarget(closeConnection: closeConnection);
    response
      ..statusCode = status
      ..contentLength = 0;
    await response.close();
  }

  void _prepareTarget({
    bool closeConnection = false,
    bool reset = false,
  }) {
    final target = _incoming.response;
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

    if (closeConnection || !_input.isComplete) {
      _input.pause();
      target.persistentConnection = false;
    }
  }

  Future<void> _abortUncommitted() async {
    final socket = await _incoming.response.detachSocket(writeHeaders: false);
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

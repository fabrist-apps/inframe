import 'dart:io';

import 'package:inlet/src/errors.dart';
import 'package:inlet/src/handler.dart';
import 'package:inlet/src/http_token.dart';
import 'package:inlet/src/response.dart';

/// Owns WebSocket preflight and callback-scoped session cleanup.
final class WebSocketSession {
  /// Uses the application's reporter without owning a listener or registry.
  const WebSocketSession(this._report);
  final ErrorReporter _report;

  /// Validates the handshake and selects a protocol before headers commit.
  Future<String?> preflight(
    HttpRequest incoming,
    WebSocketDelivery delivery, {
    required bool isHead,
  }) async {
    if (incoming.method != 'GET' || isHead || !WebSocketTransformer.isUpgradeRequest(incoming)) {
      throw const WebSocketHandshakeRejected('Invalid WebSocket upgrade request.');
    }
    if (delivery.isClosed) {
      throw StateError('The WebSocket response has already been closed.');
    }
    final offered = _parseWebSocketProtocols(incoming.headers);
    final selected = await _selectWebSocketProtocol(delivery.selectProtocol, offered);
    _validateWebSocketExtensions(incoming.headers, delivery.compression);
    return selected;
  }

  /// Keeps the socket open for the callback and preserves its chosen close code.
  Future<void> run(
    WebSocket socket,
    WebSocketDelivery delivery,
  ) async {
    try {
      await delivery.onConnect(socket);
      await _closeWebSocket(socket, WebSocketStatus.normalClosure);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      await _closeWebSocket(socket, WebSocketStatus.internalServerError);
    }
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

        if (!isHttpToken(protocol)) {
          throw const WebSocketHandshakeRejected(
            'Invalid Sec-WebSocket-Protocol header.',
          );
        }
        protocols.add(protocol);
      }
    }

    return List.unmodifiable(protocols);
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
        WebSocketHandshakeRejected(error.message),
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

  void _validateWebSocketExtensions(HttpHeaders headers, CompressionOptions compression) {
    // With a selected protocol Dart defers extension negotiation until after
    // upgrade() returns. Validate its throwing preflight here, while an ordinary
    // recovery response is still possible; transport failures must stay committed.
    final extension = HeaderValue.parse(
      headers.value('sec-websocket-extensions') ?? '',
      valueSeparator: ',',
    );

    if (compression.enabled && extension.value == 'permessage-deflate') {
      final windowBits = extension.parameters['server_max_window_bits'];

      if (windowBits != null && windowBits.length >= 2 && windowBits.startsWith('0')) {
        throw ArgumentError('Illegal 0 padding on value.');
      }
    }
  }
}

// Package-internal connection ownership shared by physical transports.

import 'dart:async';

export 'socket.dart' show ConnectionSocket, openSocket;

/// Owns resources while a physical connection is being established.
final class ConnectionAttempt {
  final Completer<void> _settled = Completer<void>();
  void Function()? _cancelConnect;
  Future<void> Function()? _closeResource;
  bool _cancelled = false;

  /// Completes after the caller finishes the connection-opening operation.
  Future<void> get settled => _settled.future;

  /// Registers cancellation for an in-progress TCP connection.
  ///
  /// Returns false and invokes [cancel] immediately when this attempt was already cancelled.
  bool attachConnect(void Function() cancel) {
    if (_cancelled) {
      cancel();
      return false;
    }
    _cancelConnect = cancel;
    return true;
  }

  /// Removes [cancel] if it still represents the active TCP connection.
  void detachConnect(void Function() cancel) {
    if (identical(_cancelConnect, cancel)) _cancelConnect = null;
  }

  /// Transfers ownership to [close] after a socket or transport is available.
  ///
  /// Returns false when cancellation already won the ownership race.
  bool attachResource(Future<void> Function() close) {
    if (_cancelled) return false;
    _closeResource = close;
    return true;
  }

  /// Marks the connection-opening operation as settled and releases temporary ownership.
  void finish() {
    _cancelConnect = null;
    _closeResource = null;
    if (!_settled.isCompleted) _settled.complete();
  }

  /// Cancels the active connection phase and releases its currently owned resource.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _cancelConnect?.call();
    _cancelConnect = null;
    final close = _closeResource;
    _closeResource = null;
    await close?.call();
  }
}

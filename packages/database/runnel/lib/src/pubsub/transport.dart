import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/configuration.dart';
import 'package:runnel/src/connection/connection_attempt.dart' show ConnectionAttempt;
import 'package:runnel/src/connection/legacy_errors.dart';
import 'package:runnel/src/connection/socket.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/resp/resp_parser.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// Wire subscription acknowledgement expected by a control request.
enum ControlKind {
  /// Adds a channel subscription.
  subscribe,

  /// Removes a channel subscription.
  unsubscribe,
}

/// Owns a Pub/Sub socket, frame parser, and pending wire replies.
final class PubSubTransport {
  PubSubTransport._(
    this._socket,
    RunnelLimits limits,
    this._onFrame,
    this._onTerminated,
  ) : _parser = RespParser(
        maxFrameBytes: limits.maxFrameBytes,
        maxNestingDepth: limits.maxNestingDepth,
      ) {
    _subscription = _socket.listen(
      _onBytes,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
  }

  final ConnectionSocket _socket;
  final RespParser _parser;
  final void Function(RespValue value) _onFrame;
  final void Function(Object error) _onTerminated;
  final Queue<Completer<RespValue>> _replyWaiters = Queue();
  late final StreamSubscription<Uint8List> _subscription;
  _PendingControl? _pendingControl;
  bool _closed = false;
  Future<void>? _release;

  /// Opens a socket owned by the cancellable connection attempt.
  static Future<PubSubTransport> open(
    ConnectionConfiguration configuration, {
    required RunnelLimits limits,
    required Duration timeout,
    required ConnectionAttempt attempt,
    required void Function(RespValue value) onFrame,
    required void Function(Object error) onTerminated,
  }) async {
    final socket = await openSocket(
      host: configuration.host,
      port: configuration.port,
      tls: configuration.tls,
      securityContext: configuration.securityContext,
      timeout: timeout,
      attempt: attempt,
    );
    final transport = PubSubTransport._(socket, limits, onFrame, onTerminated);
    if (!attempt.attachResource(transport.close)) {
      await transport.close();
      throw const RedisClosedException(message: 'The Pub/Sub connection was cancelled.');
    }
    return transport;
  }

  /// Sends a handshake command and waits for its non-push reply.
  Future<RespValue> requestReply(RedisCommand<Object?> command, {required Duration timeout}) {
    if (_closed) return Future.error(StateError('The Pub/Sub transport is closed.'));
    final completer = Completer<RespValue>();
    _replyWaiters.add(completer);
    try {
      _socket.add(encodeCommand(command));
    } on Object catch (error, stackTrace) {
      _replyWaiters.remove(completer);
      completer.completeError(error, stackTrace);
    }
    return completer.future.timeout(timeout).then((reply) {
      if (reply case RespError(:final code, :final message)) {
        throw RedisServerException(code: code, message: message);
      }
      return reply;
    });
  }

  /// Sends one serialized control and waits for all channel acknowledgements.
  Future<void> sendControl(
    Uint8List bytes, {
    required ControlKind kind,
    required List<String> channels,
  }) {
    if (_closed) return Future.error(StateError('The Pub/Sub transport is closed.'));
    if (_pendingControl != null) {
      return Future.error(StateError('Pub/Sub controls must be serialized.'));
    }
    final pending = _PendingControl(kind, channels);
    _pendingControl = pending;
    try {
      _socket.add(bytes);
    } on Object catch (error, stackTrace) {
      _pendingControl = null;
      pending.completer.completeError(error, stackTrace);
    }
    return pending.completer.future;
  }

  /// Consumes an acknowledgement after the session updates its channel state.
  void acknowledge(ControlKind kind, String channel) {
    final pending = _pendingControl;
    if (pending == null || pending.kind != kind || !pending.remaining.remove(channel)) return;
    if (pending.remaining.isNotEmpty) return;
    _pendingControl = null;
    pending.completer.complete();
  }

  /// Rejects the active control, or terminates an unsolicited server error.
  void rejectControl(Object error) {
    final pending = _pendingControl;
    if (pending == null) {
      _terminate(error);
      return;
    }
    _pendingControl = null;
    pending.completer.completeError(error, StackTrace.current);
  }

  void _onBytes(Uint8List bytes) {
    try {
      for (final received in _parser.add(bytes)) {
        final value = switch (received) {
          RespAttributed(:final value) => value,
          _ => received,
        };
        if (_replyWaiters.isNotEmpty && value is! RespPush) {
          _replyWaiters.removeFirst().complete(value);
        } else {
          _onFrame(received);
        }
      }
    } on Object catch (error) {
      _terminate(error);
    }
  }

  void _onError(Object error, StackTrace stackTrace) => _terminate(error);

  void _onDone() {
    if (!_closed) _terminate(StateError('The Pub/Sub socket closed.'));
  }

  void _terminate(Object error) {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    _release = _subscription.cancel();
    _failReplies(error);
    _onTerminated(error);
  }

  /// Releases the socket and settles pending replies.
  Future<void> close() async {
    if (_closed) {
      await _release;
      return;
    }
    _closed = true;
    _socket.destroy();
    _release = _subscription.cancel();
    await _release;
    const error = RedisClosedException(message: 'The Pub/Sub transport closed.');
    _failReplies(error);
  }

  void _failReplies(Object error) {
    for (final waiter in _replyWaiters) {
      if (!waiter.isCompleted) waiter.completeError(error, StackTrace.current);
    }
    _replyWaiters.clear();
    final pending = _pendingControl;
    _pendingControl = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error, StackTrace.current);
    }
  }
}

final class _PendingControl {
  _PendingControl(this.kind, Iterable<String> channels) : remaining = Set.of(channels);

  final ControlKind kind;
  final Set<String> remaining;
  final Completer<void> completer = Completer<void>();
}

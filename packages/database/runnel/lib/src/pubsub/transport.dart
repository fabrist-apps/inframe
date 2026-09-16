import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:conflux/option.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/configuration.dart';
import 'package:runnel/src/connection/connection_attempt.dart' show ConnectionAttempt;
import 'package:runnel/src/connection/socket.dart';
import 'package:runnel/src/deadline.dart';
import 'package:runnel/src/errors.dart';
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
    this._acceptsChannel,
    this._onMessage,
    this._onAcknowledgement,
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
  final bool Function(String channel) _acceptsChannel;
  final void Function(String channel, Uint8List payload) _onMessage;
  final void Function(ControlKind kind, String channel) _onAcknowledgement;
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
    required Deadline deadline,
    required ConnectionAttempt attempt,
    required bool Function(String channel) acceptsChannel,
    required void Function(String channel, Uint8List payload) onMessage,
    required void Function(ControlKind kind, String channel) onAcknowledgement,
    required void Function(Object error) onTerminated,
  }) async {
    final socket = await openSocket(
      host: configuration.host,
      port: configuration.port,
      tls: configuration.tls,
      securityContext: configuration.securityContext,
      deadline: deadline,
      attempt: attempt,
    );
    final transport = PubSubTransport._(
      socket,
      limits,
      acceptsChannel,
      onMessage,
      onAcknowledgement,
      onTerminated,
    );
    if (!attempt.attachResource(transport.close)) {
      await transport.close();
      throw RunnelClosedError(
        'The Pub/Sub connection was cancelled.',
        stackTrace: StackTrace.current,
      );
    }
    return transport;
  }

  /// Sends a handshake command and waits for its non-push reply.
  Future<RespValue> requestReply(RedisCommand<Object?> command, {required Deadline deadline}) {
    if (_closed) return Future.error(StateError('The Pub/Sub transport is closed.'));
    final bytes = encodeCommand(command);
    final remaining = deadline.remaining;
    final completer = Completer<RespValue>();
    _replyWaiters.add(completer);
    try {
      _socket.add(bytes);
    } on Object catch (error, stackTrace) {
      _replyWaiters.remove(completer);
      completer.completeError(error, stackTrace);
    }
    return completer.future.timeout(remaining).then((reply) {
      if (reply case RespError(:final code, :final message)) {
        throw RunnelServerError(message, code: code, cause: reply, stackTrace: StackTrace.current);
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

  // Publish acknowledged state before waking the caller awaiting this control.
  void _acknowledge(ControlKind kind, String channel) {
    _onAcknowledgement(kind, channel);
    final pending = _pendingControl;
    if (pending == null || pending.kind != kind || !pending.remaining.remove(channel)) return;
    if (pending.remaining.isNotEmpty) return;
    _pendingControl = null;
    pending.completer.complete();
  }

  void _rejectControl(Object error) {
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
          _onFrame(value);
        }
      }
    } on Object catch (error) {
      _terminate(error);
    }
  }

  void _onFrame(RespValue value) {
    try {
      if (value case RespError(:final code, :final message)) {
        _rejectControl(
          RunnelServerError(message, code: code, cause: value, stackTrace: StackTrace.current),
        );
        return;
      }
      final parts = switch (value) {
        RespPush(:final values) => values,
        _ => throw const FormatException('Expected a Pub/Sub push frame.'),
      };
      if (parts.isEmpty) throw const FormatException('Received an empty Pub/Sub frame.');
      final type = respText(parts.first).toLowerCase();
      switch (type) {
        case 'message':
          if (parts.length != 3) throw const FormatException('Malformed Pub/Sub message.');
          final channel = respText(parts[1]);
          if (!_acceptsChannel(channel)) return;
          final payload = switch (parts[2]) {
            RespBlobString(:final value) => value,
            RespSimpleString(:final value) => Uint8List.fromList(utf8.encode(value)),
            _ => throw FormatException(
              'Expected a Pub/Sub payload, received ${parts[2].runtimeType}.',
            ),
          };
          _onMessage(channel, payload);
        case 'subscribe':
        case 'unsubscribe':
          if (parts.length != 3) throw const FormatException('Malformed Pub/Sub acknowledgement.');
          _acknowledge(
            type == 'subscribe' ? ControlKind.subscribe : ControlKind.unsubscribe,
            respText(parts[1]),
          );
        case 'pong':
          break;
        default:
          throw FormatException('Unsupported Pub/Sub frame type $type.');
      }
    } on FormatException catch (error, stackTrace) {
      _terminate(
        RunnelProtocolError(
          error.message,
          cause: error,
          deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
          stackTrace: stackTrace,
        ),
      );
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
    final error = RunnelClosedError(
      'The Pub/Sub transport closed.',
      stackTrace: StackTrace.current,
    );
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

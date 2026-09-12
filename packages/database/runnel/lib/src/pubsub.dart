import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/src/client.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/connection_attempt.dart';
import 'package:runnel/src/connection/reconnect_backoff.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/protocol.dart';
import 'package:runnel/src/resp/resp_parser.dart';
import 'package:runnel/src/resp/resp_value.dart';

/// Resource limits for one Pub/Sub session.
final class PubSubLimits {
  /// Creates Pub/Sub queue and channel limits.
  const PubSubLimits({
    this.maxBufferedEvents = 1024,
    this.maxBufferedBytes = 8 * 1024 * 1024,
    this.maxChannels = 16384,
  });

  /// Maximum undelivered messages and lifecycle events.
  final int maxBufferedEvents;

  /// Maximum bytes retained by undelivered events.
  final int maxBufferedBytes;

  /// Maximum distinct desired channels.
  final int maxChannels;

  void _validate() {
    if (maxBufferedEvents <= 0 || maxBufferedBytes <= 0 || maxChannels <= 0) {
      throw ArgumentError('Pub/Sub limits must be positive.');
    }
  }
}

/// Connection details inherited by a Pub/Sub session from its parent client.
///
/// Application code ordinarily obtains a session through `Runnel.openPubSub`; this
/// value is the composition seam used by the client to create the dedicated socket.
final class PubSubConnectionConfiguration {
  /// Creates validated connection details for a dedicated Pub/Sub socket.
  const PubSubConnectionConfiguration({
    required this.host,
    required this.port,
    required this.tls,
    required this.protocol,
    required this.connectTimeout,
    required this.connectionLimits,
    this.securityContext,
    this.database = 0,
    this.username,
    this.password,
  });

  /// Redis or Valkey host.
  final String host;

  /// Redis or Valkey port.
  final int port;

  /// Whether to establish TLS.
  final bool tls;

  /// TLS trust and client-certificate configuration.
  final SecurityContext? securityContext;

  /// RESP version negotiated by HELLO.
  final RedisProtocol protocol;

  /// Selected logical database.
  final int database;

  /// Optional ACL username.
  final String? username;

  /// Optional ACL password.
  final String? password;

  /// Deadline for socket creation and handshake.
  final Duration connectTimeout;

  /// Inherited command and incoming-frame limits.
  final RunnelLimits connectionLimits;

  void _validate() {
    if (host.isEmpty) throw ArgumentError.value(host, 'host', 'must not be empty');
    if (port <= 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be between 1 and 65535');
    }
    if (database < 0) throw ArgumentError.value(database, 'database', 'must be nonnegative');
    if (connectTimeout <= Duration.zero) {
      throw ArgumentError.value(connectTimeout, 'connectTimeout', 'must be positive');
    }
    if (!tls && securityContext != null) {
      throw ArgumentError.value(securityContext, 'securityContext', 'requires TLS');
    }
    connectionLimits.validate();
  }
}

/// Lifecycle state of a Pub/Sub session.
enum PubSubState {
  /// The socket and desired subscriptions are acknowledged.
  ready,

  /// A healthy socket is reconciling subscription changes.
  subscribing,

  /// The physical socket is being replaced and restored.
  reconnecting,

  /// Local resource release is in progress.
  closing,

  /// The session cannot perform more work.
  closed,
}

/// Reason a Pub/Sub delivery generation was interrupted.
enum PubSubInterruptionCause {
  /// The socket failed or closed unexpectedly.
  networkLoss,

  /// The caller requested a new physical connection.
  explicitReconnect,

  /// A subscription control deadline expired.
  subscriptionTimeout,

  /// Redis rejected a subscription control command.
  subscriptionRejection,

  /// Incoming bytes violated the Pub/Sub protocol.
  protocolFailure,

  /// Undelivered events exceeded a configured bound.
  bufferOverflow,
}

/// One ordered event from a Pub/Sub session.
sealed class PubSubEvent {
  const PubSubEvent();
}

/// One channel publication with an owned binary payload.
final class PubSubMessage extends PubSubEvent {
  /// Creates a publication and snapshots [payload].
  PubSubMessage({required this.generation, required this.channel, required Uint8List payload})
    : _payload = Uint8List.fromList(payload);

  /// Physical connection generation on which the message arrived.
  final int generation;

  /// Published channel decoded as strict UTF-8.
  final String channel;

  final Uint8List _payload;

  /// An owned copy of the publication bytes.
  Uint8List get payload => Uint8List.fromList(_payload);

  /// Payload decoded as strict UTF-8.
  String get text => utf8.decode(_payload);
}

/// A delivery generation stopped or a session terminated.
final class PubSubInterrupted extends PubSubEvent {
  /// Creates an interruption event.
  const PubSubInterrupted({
    required this.generation,
    required this.cause,
    required this.terminal,
    this.error,
  });

  /// Generation that was interrupted.
  final int generation;

  /// Stable interruption reason.
  final PubSubInterruptionCause cause;

  /// Whether this session will never reconnect.
  final bool terminal;

  /// Underlying transport, server, timeout, or protocol failure.
  final Object? error;
}

/// A new connection has acknowledged the desired subscription snapshot.
final class PubSubRestored extends PubSubEvent {
  /// Creates a restoration event with an immutable channel snapshot.
  PubSubRestored({required this.generation, required Iterable<String> channels})
    : channels = Set.unmodifiable(channels);

  /// Newly restored physical connection generation.
  final int generation;

  /// Channels acknowledged before restoration completed.
  final Set<String> channels;
}

/// An unfinished subscription was replaced by a later channel operation.
final class SubscriptionSupersededException implements Exception {
  /// Creates a later-operation-wins failure.
  const SubscriptionSupersededException([
    this.message = 'A later subscription change superseded this operation.',
  ]);

  /// Human-readable failure detail.
  final String message;

  @override
  String toString() => message;
}

/// Builds a PUBLISH command whose result is Redis's broker subscriber count.
RedisCommand<int> publishCommand(String channel, String message) =>
    _publishCommand(channel, RedisArgument.text(message));

/// Builds a binary PUBLISH command and snapshots [message].
RedisCommand<int> publishBytesCommand(String channel, Uint8List message) =>
    _publishCommand(channel, RedisArgument.bytes(message));

/// Publishing conveniences for [Runnel].
extension RunnelPublishingCommands on Runnel {
  /// Publishes text and returns the broker subscriber count.
  ///
  /// The count is not an end-client delivery acknowledgement or persistence proof.
  Future<int> publish(String channel, String message, {Duration? timeout}) =>
      execute(publishCommand(channel, message), timeout: timeout);

  /// Publishes exact bytes and returns the broker subscriber count.
  ///
  /// The count is not an end-client delivery acknowledgement or persistence proof.
  Future<int> publishBytes(String channel, Uint8List message, {Duration? timeout}) =>
      execute(publishBytesCommand(channel, message), timeout: timeout);
}

/// One bounded, dynamically subscribed Pub/Sub connection.
final class PubSubSession {
  PubSubSession._(
    this._configuration,
    this._controlTimeout,
    this._limits,
    this._onClosed,
  ) : _events = _PubSubEventStream();

  /// Opens a dedicated connection and completes its HELLO/SELECT handshake.
  ///
  /// [onClosed] is invoked once after the socket is released so a parent client can
  /// unregister ownership.
  static Future<PubSubSession> connect(
    PubSubConnectionConfiguration configuration, {
    Duration controlTimeout = const Duration(seconds: 5),
    PubSubLimits limits = const PubSubLimits(),
    void Function(PubSubSession session)? onClosed,
    void Function(PubSubSession session)? onCreated,
  }) async {
    configuration._validate();
    limits._validate();
    if (controlTimeout <= Duration.zero) {
      throw ArgumentError.value(controlTimeout, 'controlTimeout', 'must be positive');
    }
    final session = PubSubSession._(configuration, controlTimeout, limits, onClosed);
    session._events._session = session;
    onCreated?.call(session);
    try {
      await session._openInitialTransport();
      return session;
    } on Object {
      await session._transport?.close();
      session
        .._state = PubSubState.closed
        .._notifyClosed();
      rethrow;
    }
  }

  final PubSubConnectionConfiguration _configuration;
  final Duration _controlTimeout;
  final PubSubLimits _limits;
  final void Function(PubSubSession session)? _onClosed;
  final _PubSubEventStream _events;
  final Queue<_BufferedEvent> _eventQueue = Queue();
  final Map<String, int> _channelRevisions = {};
  final Set<String> _desiredChannels = {};
  final Set<String> _acknowledgedChannels = {};
  final Set<_ControlOperation> _controlOperations = {};
  final ReconnectBackoff _backoff = ReconnectBackoff();

  _PubSubTransport? _transport;
  ConnectionAttempt? _openingTransport;
  _PubSubEventSubscription? _listener;
  PubSubEvent? _terminalEvent;
  Future<void> _controlTail = Future.value();
  Future<void>? _closing;
  Future<void>? _recovery;
  Future<void>? _explicitReconnect;
  Completer<void>? _readyAfterRecovery;
  Timer? _reconnectTimer;
  Completer<bool>? _reconnectWaiter;
  PubSubState _state = PubSubState.reconnecting;
  int _generation = 0;
  int _revision = 0;
  int _bufferedBytes = 0;
  int _reservedControlCommands = 0;
  int _reservedControlBytes = 0;
  bool _streamDone = false;
  bool _closedCallbackSent = false;
  PubSubInterrupted? _lastInterruption;

  /// Ordered single-listener message and lifecycle events.
  Stream<PubSubEvent> get events => _events;

  /// Current connection and reconciliation state.
  PubSubState get state => _state;

  /// Current successful physical connection generation.
  int get generation => _generation;

  /// Immutable snapshot of locally desired channels.
  Set<String> get desiredChannels => Set.unmodifiable(_desiredChannels);

  /// Immutable snapshot acknowledged on the current connection.
  Set<String> get acknowledgedChannels => Set.unmodifiable(_acknowledgedChannels);

  /// Most recent delivery interruption, including its underlying failure.
  PubSubInterrupted? get lastInterruption => _lastInterruption;

  Future<void> _openInitialTransport() async {
    await _openTransport(_configuration.connectTimeout);
    _generation = 1;
    _backoff.reset();
    _state = PubSubState.ready;
  }

  Future<void> _openTransport(Duration timeout) async {
    final deadline = _Deadline(timeout);
    final attempt = ConnectionAttempt();
    _openingTransport = attempt;
    late final _PubSubTransport transport;
    var transportOpened = false;
    try {
      transport = await _PubSubTransport.open(
        _configuration,
        timeout: deadline.remaining,
        attempt: attempt,
        onFrame: (value) {
          if (identical(_transport, transport)) _onFrame(value);
        },
        onTerminated: (error) {
          if (identical(_transport, transport)) _onTransportTerminated(error);
        },
      );
      transportOpened = true;
      if (_state == PubSubState.closing || _state == PubSubState.closed) {
        await transport.close();
        throw const RedisClosedException(message: 'The Pub/Sub session is closed.');
      }
      _transport = transport;
      await transport.requestReply(_helloCommand(), timeout: deadline.remaining);
      if (_configuration.database != 0) {
        await transport.requestReply(_selectCommand(), timeout: deadline.remaining);
      }
    } on Object {
      if (transportOpened) {
        if (identical(_transport, transport)) _transport = null;
        await transport.close();
      }
      rethrow;
    } finally {
      attempt.finish();
      if (identical(_openingTransport, attempt)) _openingTransport = null;
    }
  }

  /// Adds [channels] to desired state and waits for every relevant acknowledgement.
  Future<void> subscribe(List<String> channels, {Duration? timeout}) async {
    final deadline = _validatedTimeout(timeout);
    final requested = _validatedChannels(channels);
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      return Future.error(const RedisClosedException(message: 'The Pub/Sub session is closed.'));
    }
    final resultingCount = _desiredChannels.union(requested.toSet()).length;
    if (resultingCount > _limits.maxChannels) {
      return Future.error(
        RedisLimitException(
          message: 'The subscription would exceed ${_limits.maxChannels} desired channels.',
          deliveryStatus: RedisDeliveryStatus.notSent,
          limit: _limits.maxChannels,
        ),
      );
    }

    final needsWire = requested
        .where((channel) => !_acknowledgedChannels.contains(channel))
        .toList();
    final reservation = _reserveControl('SUBSCRIBE', needsWire);
    final operationRevision = ++_revision;
    final additions = <String>{};
    for (final channel in requested) {
      if (_desiredChannels.add(channel)) additions.add(channel);
      _channelRevisions[channel] = operationRevision;
    }
    final operation = _ControlOperation(
      kind: _ControlKind.subscribe,
      channels: requested,
      additions: additions,
      revision: operationRevision,
      deadline: deadline,
      reservation: reservation,
    );
    return _enqueueControl(operation);
  }

  /// Removes [channels] from desired state immediately, then waits for wire acknowledgement.
  Future<void> unsubscribe(List<String> channels, {Duration? timeout}) async {
    final deadline = _validatedTimeout(timeout);
    final requested = _validatedChannels(channels);
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      return Future.error(const RedisClosedException(message: 'The Pub/Sub session is closed.'));
    }
    final disconnected = _state == PubSubState.reconnecting;
    final needsWire = requested
        .where(
          (channel) =>
              _desiredChannels.contains(channel) || _acknowledgedChannels.contains(channel),
        )
        .toList();
    final reservation = disconnected
        ? const _ControlReservation(0, 0)
        : _reserveControl('UNSUBSCRIBE', needsWire);
    final operationRevision = ++_revision;
    for (final channel in requested) {
      _desiredChannels.remove(channel);
      _channelRevisions[channel] = operationRevision;
    }
    _discardQueuedMessages(requested.toSet());
    if (disconnected) return;
    final operation = _ControlOperation(
      kind: _ControlKind.unsubscribe,
      channels: requested,
      additions: const {},
      revision: operationRevision,
      deadline: deadline,
      reservation: reservation,
    );
    return _enqueueControl(operation);
  }

  /// Replaces the physical connection and restores the desired channel set.
  Future<void> reconnect({Duration? timeout}) {
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      return Future.error(const RedisClosedException(message: 'The Pub/Sub session is closed.'));
    }
    final existing = _explicitReconnect;
    if (existing != null) return existing;
    final deadline = timeout ?? _configuration.connectTimeout + _controlTimeout;
    if (deadline <= Duration.zero) {
      return Future.error(ArgumentError.value(deadline, 'timeout', 'must be positive'));
    }
    final operation = _startExplicitReconnect(deadline);
    _explicitReconnect = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_explicitReconnect, operation)) _explicitReconnect = null;
        },
        onError: (_, _) {
          if (identical(_explicitReconnect, operation)) _explicitReconnect = null;
        },
      ),
    );
    return operation;
  }

  /// Releases the dedicated socket and completes the event stream without an error event.
  Future<void> close() => _closing ??= _close(listenerCancelled: false);

  Future<void> _close({required bool listenerCancelled}) async {
    if (_state == PubSubState.closed) return;
    _state = PubSubState.closing;
    _cancelReconnectDelay();
    final ready = _readyAfterRecovery;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const RedisClosedException(message: 'The Pub/Sub session closed.'));
    }
    _failControls(const RedisClosedException(message: 'The Pub/Sub session closed.'));
    _desiredChannels.clear();
    _acknowledgedChannels.clear();
    final transport = _transport;
    _transport = null;
    await _openingTransport?.cancel();
    await transport?.close();
    final recovery = _recovery;
    if (recovery != null) {
      try {
        await recovery;
      } on Object {
        // Closing owns the final state regardless of a recovery failure.
      }
    }
    _state = PubSubState.closed;
    if (listenerCancelled) {
      _eventQueue.clear();
      _bufferedBytes = 0;
      _streamDone = true;
    } else {
      _streamDone = true;
      _drainEvents();
    }
    _notifyClosed();
  }

  Duration _validatedTimeout(Duration? timeout) {
    final value = timeout ?? _controlTimeout;
    if (value <= Duration.zero) throw ArgumentError.value(value, 'timeout', 'must be positive');
    return value;
  }

  List<String> _validatedChannels(List<String> channels) {
    if (channels.isEmpty) throw ArgumentError.value(channels, 'channels', 'must not be empty');
    final unique = <String>{};
    for (final channel in channels) {
      if (channel.isEmpty) {
        throw ArgumentError.value(channels, 'channels', 'must contain nonempty channel names');
      }
      unique.add(channel);
    }
    return List.unmodifiable(unique);
  }

  _ControlReservation _reserveControl(String command, List<String> channels) {
    if (channels.isEmpty) return const _ControlReservation(0, 0);
    var commands = 0;
    var bytes = 0;
    for (final chunk in _chunks(channels)) {
      commands++;
      bytes += encodeCommand(_controlCommand(command, chunk) as RedisCommand<Object?>).length;
    }
    final connectionLimits = _configuration.connectionLimits;
    if (_reservedControlCommands + commands > connectionLimits.maxPendingCommands) {
      throw RedisLimitException(
        message:
            'The request would exceed ${connectionLimits.maxPendingCommands} pending controls.',
        deliveryStatus: RedisDeliveryStatus.notSent,
        limit: connectionLimits.maxPendingCommands,
      );
    }
    if (_reservedControlBytes + bytes > connectionLimits.maxPendingBytes) {
      throw RedisLimitException(
        message:
            'The request would exceed ${connectionLimits.maxPendingBytes} pending control bytes.',
        deliveryStatus: RedisDeliveryStatus.notSent,
        limit: connectionLimits.maxPendingBytes,
      );
    }
    _reservedControlCommands += commands;
    _reservedControlBytes += bytes;
    return _ControlReservation(commands, bytes);
  }

  Future<void> _enqueueControl(_ControlOperation operation) {
    _controlOperations.add(operation);
    operation.timer = Timer(operation.deadline - operation.stopwatch.elapsed, () {
      _expireControl(operation);
    });
    final predecessor = _controlTail;
    final running = predecessor.then((_) => _runControl(operation));
    _controlTail = running.then<void>((_) {}, onError: (_, _) {});
    unawaited(
      running.then<void>(
        (_) {
          if (!operation.result.isCompleted) operation.result.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!operation.result.isCompleted) operation.result.completeError(error, stackTrace);
        },
      ),
    );
    return operation.result.future;
  }

  Future<void> _runControl(_ControlOperation operation) async {
    try {
      if (operation.result.isCompleted) return;
      if (_state == PubSubState.reconnecting) {
        final remaining = operation.deadline - operation.stopwatch.elapsed;
        if (remaining <= Duration.zero) throw TimeoutException('Subscription control timed out.');
        await _readyAfterRecovery!.future.timeout(remaining);
      }
      if (_state == PubSubState.closed || _state == PubSubState.closing) {
        throw const RedisClosedException(message: 'The Pub/Sub session is closed.');
      }
      _state = PubSubState.subscribing;
      _ensureCurrent(operation);
      final wireChannels = switch (operation.kind) {
        _ControlKind.subscribe =>
          operation.channels.where((channel) => !_acknowledgedChannels.contains(channel)).toList(),
        _ControlKind.unsubscribe =>
          operation.channels.where(_acknowledgedChannels.contains).toList(),
      };
      for (final chunk in _chunks(wireChannels)) {
        _ensureCurrent(operation);
        final commandName = operation.kind == _ControlKind.subscribe ? 'SUBSCRIBE' : 'UNSUBSCRIBE';
        final remaining = operation.deadline - operation.stopwatch.elapsed;
        if (remaining <= Duration.zero) throw TimeoutException('Subscription control timed out.');
        final command = _controlCommand(commandName, chunk);
        operation.submitted = true;
        await _transport!
            .sendControl(
              encodeCommand(command as RedisCommand<Object?>),
              kind: operation.kind,
              channels: chunk,
            )
            .timeout(remaining);
      }
      _ensureCurrent(operation);
    } on SubscriptionSupersededException {
      _rollbackAdditions(operation);
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      _rollbackAdditions(operation);
      final failure = RedisTimeoutException(
        message: 'The Pub/Sub subscription deadline expired.',
        deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
        cause: error,
      );
      _terminateForControlFailure(
        PubSubInterruptionCause.subscriptionTimeout,
        failure,
      );
      Error.throwWithStackTrace(failure, stackTrace);
    } on RedisServerException catch (error, stackTrace) {
      _rollbackAdditions(operation);
      _terminateForControlFailure(PubSubInterruptionCause.subscriptionRejection, error);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _releaseControl(operation);
      if (_state == PubSubState.subscribing && _controlOperations.isEmpty && _recovery == null) {
        _state = PubSubState.ready;
      }
    }
  }

  void _expireControl(_ControlOperation operation) {
    if (operation.result.isCompleted) return;
    _rollbackAdditions(operation);
    final failure = RedisTimeoutException(
      message: 'The Pub/Sub subscription deadline expired.',
      deliveryStatus: operation.submitted
          ? RedisDeliveryStatus.outcomeUnknown
          : RedisDeliveryStatus.notSent,
    );
    if (operation.submitted || operation.kind == _ControlKind.unsubscribe) {
      _terminateForControlFailure(PubSubInterruptionCause.subscriptionTimeout, failure);
    } else {
      operation.result.completeError(failure, StackTrace.current);
    }
    _releaseControl(operation);
  }

  void _ensureCurrent(_ControlOperation operation) {
    if (operation.result.isCompleted) {
      throw const RedisClosedException(message: 'The Pub/Sub control operation was cancelled.');
    }
    for (final channel in operation.channels) {
      if (_channelRevisions[channel] != operation.revision) {
        throw const SubscriptionSupersededException();
      }
    }
  }

  void _rollbackAdditions(_ControlOperation operation) {
    for (final channel in operation.additions) {
      if (_channelRevisions[channel] == operation.revision) {
        _desiredChannels.remove(channel);
      }
    }
  }

  void _releaseReservation(_ControlReservation reservation) {
    _reservedControlCommands -= reservation.commands;
    _reservedControlBytes -= reservation.bytes;
  }

  void _releaseControl(_ControlOperation operation) {
    if (operation.released) return;
    operation.released = true;
    operation.timer?.cancel();
    _controlOperations.remove(operation);
    _releaseReservation(operation.reservation);
  }

  void _onFrame(RespValue received) {
    try {
      final value = switch (received) {
        RespAttributed(:final value) => value,
        _ => received,
      };
      if (value case RespError(:final code, :final message)) {
        _transport?.rejectControl(RedisServerException(code: code, message: message));
        return;
      }
      final parts = switch (value) {
        RespPush(:final values) => values,
        RespArray(:final values) => values,
        _ => throw const FormatException('Expected a Pub/Sub array or push frame.'),
      };
      if (parts.isEmpty) throw const FormatException('Received an empty Pub/Sub frame.');
      final type = respText(parts.first).toLowerCase();
      switch (type) {
        case 'message':
          if (parts.length != 3) throw const FormatException('Malformed Pub/Sub message.');
          final channel = respText(parts[1]);
          if (!_desiredChannels.contains(channel)) return;
          final payload = _replyBytes(parts[2]);
          _emit(PubSubMessage(generation: _generation, channel: channel, payload: payload));
        case 'subscribe':
          _handleAcknowledgement(parts, _ControlKind.subscribe);
        case 'unsubscribe':
          _handleAcknowledgement(parts, _ControlKind.unsubscribe);
        case 'pong':
          break;
        default:
          throw FormatException('Unsupported Pub/Sub frame type $type.');
      }
    } on Object catch (error) {
      _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
    }
  }

  void _handleAcknowledgement(List<RespValue> parts, _ControlKind kind) {
    if (parts.length != 3) throw const FormatException('Malformed Pub/Sub acknowledgement.');
    final channel = respText(parts[1]);
    switch (kind) {
      case _ControlKind.subscribe:
        _acknowledgedChannels.add(channel);
      case _ControlKind.unsubscribe:
        _acknowledgedChannels.remove(channel);
    }
    _transport?.acknowledge(kind, channel);
  }

  void _onTransportTerminated(Object error) {
    if (_state == PubSubState.closing || _state == PubSubState.closed) return;
    if (_generation == 0) return;
    _transport = null;
    if (error is RedisProtocolException ||
        error is RedisLimitException ||
        error is FormatException) {
      _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
      return;
    }
    final failure = RedisTransportException(
      message: 'The Pub/Sub connection was interrupted.',
      deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
      cause: error,
    );
    _interrupt(PubSubInterruptionCause.networkLoss, failure);
    if (_state != PubSubState.closed && _recovery == null) {
      unawaited(_beginRecovery(immediate: false));
    }
  }

  void _terminateForControlFailure(PubSubInterruptionCause cause, Object error) {
    if (_state == PubSubState.closed || _state == PubSubState.closing) return;
    _interrupt(cause, error);
    if (_state != PubSubState.closed && _recovery == null) {
      unawaited(_beginRecovery(immediate: true));
    }
  }

  void _interrupt(PubSubInterruptionCause cause, Object error) {
    if (_state == PubSubState.closed || _state == PubSubState.closing) return;
    _acknowledgedChannels.clear();
    _failControls(error);
    _controlTail = Future.value();
    final interruption = PubSubInterrupted(
      generation: _generation,
      cause: cause,
      terminal: false,
      error: error,
    );
    _lastInterruption = interruption;
    _emit(interruption);
    if (_state != PubSubState.closed) _state = PubSubState.reconnecting;
    final transport = _transport;
    _transport = null;
    unawaited(transport?.close());
  }

  Future<void> _startExplicitReconnect(Duration timeout) async {
    final deadline = _Deadline(timeout);
    final startingChannels = Set<String>.of(_desiredChannels);
    final automaticRecovery = _recovery;
    if (automaticRecovery != null) {
      _cancelReconnectDelay();
      try {
        await automaticRecovery.timeout(deadline.remaining);
      } on TimeoutException catch (error, stackTrace) {
        final failure = RedisTimeoutException(
          message: 'The explicit Pub/Sub reconnect deadline expired.',
          deliveryStatus: RedisDeliveryStatus.notSent,
          cause: error,
        );
        _terminateTerminal(PubSubInterruptionCause.explicitReconnect, failure);
        Error.throwWithStackTrace(failure, stackTrace);
      }
    }
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      throw const RedisClosedException(message: 'The Pub/Sub session is closed.');
    }
    _interrupt(
      PubSubInterruptionCause.explicitReconnect,
      const RedisTransportException(
        message: 'The Pub/Sub connection was replaced explicitly.',
        deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
      ),
    );
    if (_state == PubSubState.closed) {
      Error.throwWithStackTrace(lastInterruption!.error!, StackTrace.current);
    }
    await _beginRecovery(
      immediate: true,
      overallTimeout: deadline.remaining,
      restorationTarget: startingChannels,
    );
  }

  Future<void> _beginRecovery({
    required bool immediate,
    Duration? overallTimeout,
    Set<String>? restorationTarget,
  }) {
    final existing = _recovery;
    if (existing != null) return existing;
    final ready = Completer<void>();
    _readyAfterRecovery = ready;
    unawaited(ready.future.then<void>((_) {}, onError: (_, _) {}));
    final recovery = overallTimeout == null
        ? _recoverAutomatically(immediate: immediate)
        : _recoverExplicitly(overallTimeout, restorationTarget!);
    _recovery = recovery;
    unawaited(
      recovery.then<void>(
        (_) {
          if (!ready.isCompleted) ready.complete();
          if (identical(_recovery, recovery)) _recovery = null;
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!ready.isCompleted) ready.completeError(error, stackTrace);
          if (identical(_recovery, recovery)) _recovery = null;
        },
      ),
    );
    return recovery;
  }

  Future<void> _recoverAutomatically({required bool immediate}) async {
    var skipDelay = immediate;
    while (_state == PubSubState.reconnecting) {
      if (!skipDelay && !await _waitForReconnectDelay(_backoff.next())) return;
      skipDelay = false;
      try {
        await _replaceAndRestore(
          connectTimeout: _configuration.connectTimeout,
          controlTimeout: _controlTimeout,
        );
        return;
      } on _RestorationRejected catch (rejection, stackTrace) {
        _terminateTerminal(PubSubInterruptionCause.subscriptionRejection, rejection.error);
        Error.throwWithStackTrace(rejection.error, stackTrace);
      } on RedisServerException catch (error, stackTrace) {
        _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
        Error.throwWithStackTrace(error, stackTrace);
      } on RedisProtocolException catch (error, stackTrace) {
        _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
        Error.throwWithStackTrace(error, stackTrace);
      } on HandshakeException catch (error, stackTrace) {
        _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
        Error.throwWithStackTrace(error, stackTrace);
      } on TimeoutException catch (error) {
        if (_state == PubSubState.reconnecting && _transport != null) {
          _interrupt(PubSubInterruptionCause.subscriptionTimeout, error);
        }
      } on Object catch (error) {
        if (_state == PubSubState.reconnecting && _transport != null) {
          _interrupt(PubSubInterruptionCause.networkLoss, error);
        }
        if (_state != PubSubState.reconnecting) return;
      }
    }
  }

  Future<void> _recoverExplicitly(Duration timeout, Set<String> restorationTarget) async {
    final deadline = _Deadline(timeout);
    var firstAttempt = true;
    while (_state == PubSubState.reconnecting) {
      try {
        if (!firstAttempt && !await _waitForReconnectDelay(_backoff.next(), deadline: deadline)) {
          throw TimeoutException('The explicit Pub/Sub reconnect deadline expired.');
        }
        firstAttempt = false;
        final remaining = deadline.remaining;
        await _replaceAndRestore(
          connectTimeout: remaining,
          controlTimeout: remaining,
          restorationTarget: restorationTarget,
          overallDeadline: deadline,
        );
        return;
      } on _RestorationRejected catch (rejection, stackTrace) {
        _terminateTerminal(PubSubInterruptionCause.subscriptionRejection, rejection.error);
        Error.throwWithStackTrace(rejection.error, stackTrace);
      } on RedisServerException catch (error, stackTrace) {
        _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
        Error.throwWithStackTrace(error, stackTrace);
      } on RedisProtocolException catch (error, stackTrace) {
        _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
        Error.throwWithStackTrace(error, stackTrace);
      } on TimeoutException catch (error, stackTrace) {
        final failure = RedisTimeoutException(
          message: 'The explicit Pub/Sub reconnect deadline expired.',
          deliveryStatus: RedisDeliveryStatus.notSent,
          cause: error,
        );
        _terminateTerminal(PubSubInterruptionCause.explicitReconnect, failure);
        Error.throwWithStackTrace(failure, stackTrace);
      } on Object {
        if (_state != PubSubState.reconnecting) {
          throw const RedisClosedException(message: 'The Pub/Sub session is closed.');
        }
        try {
          deadline.remaining;
        } on TimeoutException catch (error, stackTrace) {
          final failure = RedisTimeoutException(
            message: 'The explicit Pub/Sub reconnect deadline expired.',
            deliveryStatus: RedisDeliveryStatus.notSent,
            cause: error,
          );
          _terminateTerminal(PubSubInterruptionCause.explicitReconnect, failure);
          Error.throwWithStackTrace(failure, stackTrace);
        }
      }
    }
    throw const RedisClosedException(message: 'The Pub/Sub session is closed.');
  }

  Future<void> _replaceAndRestore({
    required Duration connectTimeout,
    required Duration controlTimeout,
    Set<String>? restorationTarget,
    _Deadline? overallDeadline,
  }) async {
    final previous = _transport;
    _transport = null;
    await previous?.close();
    await _openTransport(overallDeadline?.remaining ?? connectTimeout);
    _generation++;
    _backoff.reset();
    try {
      await _restoreDesiredChannels(
        overallDeadline?.remaining ?? controlTimeout,
        restorationTarget: restorationTarget,
      );
    } on RedisServerException catch (error) {
      throw _RestorationRejected(error);
    }
    if (_state != PubSubState.reconnecting) {
      throw const RedisClosedException(message: 'The Pub/Sub session is closed.');
    }
    _state = PubSubState.ready;
    _emit(PubSubRestored(generation: _generation, channels: _acknowledgedChannels));
  }

  Future<void> _restoreDesiredChannels(Duration timeout, {Set<String>? restorationTarget}) async {
    final deadline = _Deadline(timeout);
    while (_state == PubSubState.reconnecting) {
      final target = restorationTarget == null
          ? Set<String>.of(_desiredChannels)
          : restorationTarget.where(_desiredChannels.contains).toSet();
      final removals = _acknowledgedChannels.difference(_desiredChannels).toList();
      final additions = target.difference(_acknowledgedChannels).toList();
      if (removals.isEmpty && additions.isEmpty) return;
      for (final chunk in _chunks(removals)) {
        await _sendRestorationControl(_ControlKind.unsubscribe, chunk, deadline.remaining);
      }
      for (final chunk in _chunks(additions)) {
        final stillDesired = chunk.where(_desiredChannels.contains).toList();
        if (stillDesired.isNotEmpty) {
          await _sendRestorationControl(_ControlKind.subscribe, stillDesired, deadline.remaining);
        }
      }
    }
    throw const RedisClosedException(message: 'The Pub/Sub session is closed.');
  }

  Future<void> _sendRestorationControl(
    _ControlKind kind,
    List<String> channels,
    Duration timeout,
  ) {
    final name = kind == _ControlKind.subscribe ? 'SUBSCRIBE' : 'UNSUBSCRIBE';
    final command = _controlCommand(name, channels);
    final encoded = encodeCommand(command as RedisCommand<Object?>);
    final connectionLimits = _configuration.connectionLimits;
    if (encoded.length > connectionLimits.maxPendingBytes) {
      throw RedisLimitException(
        message: 'Restoration exceeds ${connectionLimits.maxPendingBytes} pending control bytes.',
        deliveryStatus: RedisDeliveryStatus.notSent,
        limit: connectionLimits.maxPendingBytes,
      );
    }
    return _transport!.sendControl(encoded, kind: kind, channels: channels).timeout(timeout);
  }

  Future<bool> _waitForReconnectDelay(Duration delay, {_Deadline? deadline}) {
    if (_state != PubSubState.reconnecting) return Future.value(false);
    var actualDelay = delay;
    if (deadline != null) {
      final remaining = deadline.remaining;
      if (actualDelay > remaining) actualDelay = remaining;
    }
    final completer = Completer<bool>();
    _reconnectWaiter = completer;
    _reconnectTimer = Timer(actualDelay, () {
      _reconnectTimer = null;
      _reconnectWaiter = null;
      completer.complete(_state == PubSubState.reconnecting);
    });
    return completer.future;
  }

  void _terminateTerminal(PubSubInterruptionCause cause, Object error) {
    if (_state == PubSubState.closed || _state == PubSubState.closing) return;
    final interruption = PubSubInterrupted(
      generation: _generation,
      cause: cause,
      terminal: true,
      error: error,
    );
    _lastInterruption = interruption;
    _emit(interruption);
    if (_state == PubSubState.closed) return;
    _state = PubSubState.closed;
    _cancelReconnectDelay();
    _acknowledgedChannels.clear();
    _failControls(error);
    _streamDone = true;
    _drainEvents();
    final transport = _transport;
    _transport = null;
    final release = _releaseTerminalResources(_openingTransport, transport);
    _closing ??= release.whenComplete(_notifyClosed);
  }

  void _emit(PubSubEvent event) {
    if (_state == PubSubState.closed && event is! PubSubInterrupted) return;
    final bytes = _eventBytes(event);
    if (bytes > _limits.maxBufferedBytes) {
      _overflow(limit: _limits.maxBufferedBytes);
      return;
    }
    final listener = _listener;
    if (listener != null && !listener.isPaused && _eventQueue.isEmpty) {
      listener._add(event);
      return;
    }
    if (_eventQueue.length == _limits.maxBufferedEvents) {
      _overflow(limit: _limits.maxBufferedEvents);
      return;
    }
    if (_bufferedBytes + bytes > _limits.maxBufferedBytes) {
      _overflow(limit: _limits.maxBufferedBytes);
      return;
    }
    _eventQueue.add(_BufferedEvent(event, bytes));
    _bufferedBytes += bytes;
  }

  void _overflow({required int limit}) {
    if (_state == PubSubState.closed) return;
    _state = PubSubState.closed;
    _cancelReconnectDelay();
    _acknowledgedChannels.clear();
    _eventQueue.clear();
    _bufferedBytes = 0;
    final failure = RedisLimitException(
      message: 'The Pub/Sub event buffer exceeded its configured limit.',
      deliveryStatus: RedisDeliveryStatus.outcomeUnknown,
      limit: limit,
    );
    _failControls(failure);
    final interruption = PubSubInterrupted(
      generation: _generation,
      cause: PubSubInterruptionCause.bufferOverflow,
      terminal: true,
      error: failure,
    );
    _lastInterruption = interruption;
    _terminalEvent = interruption;
    _streamDone = true;
    _drainEvents();
    final transport = _transport;
    _transport = null;
    final release = _releaseTerminalResources(_openingTransport, transport);
    _closing ??= release.whenComplete(_notifyClosed);
  }

  Future<void> _releaseTerminalResources(
    ConnectionAttempt? opening,
    _PubSubTransport? transport,
  ) async {
    await opening?.cancel();
    await transport?.close();
    await opening?.settled;
  }

  void _cancelReconnectDelay() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final reconnectWaiter = _reconnectWaiter;
    _reconnectWaiter = null;
    if (reconnectWaiter != null && !reconnectWaiter.isCompleted) {
      reconnectWaiter.complete(false);
    }
  }

  void _failControls(Object error) {
    for (final operation in _controlOperations.toList(growable: false)) {
      if (!operation.result.isCompleted) operation.result.completeError(error, StackTrace.current);
      _releaseControl(operation);
    }
  }

  void _discardQueuedMessages(Set<String> channels) {
    if (_eventQueue.isEmpty) return;
    final retained = Queue<_BufferedEvent>();
    var retainedBytes = 0;
    for (final buffered in _eventQueue) {
      if (buffered.event case PubSubMessage(:final channel) when channels.contains(channel)) {
        continue;
      }
      retained.add(buffered);
      retainedBytes += buffered.bytes;
    }
    _eventQueue
      ..clear()
      ..addAll(retained);
    _bufferedBytes = retainedBytes;
  }

  StreamSubscription<PubSubEvent> _listen(
    void Function(PubSubEvent)? onData,
    Function? onError,
    void Function()? onDone,
    bool cancelOnError,
  ) {
    if (_listener != null) throw StateError('Pub/Sub events support exactly one listener.');
    final listener = _PubSubEventSubscription(
      this,
      onData: onData,
      onDone: onDone,
    );
    _listener = listener;
    scheduleMicrotask(_drainEvents);
    return listener;
  }

  void _drainEvents() {
    final listener = _listener;
    if (listener == null || listener.isPaused || listener._cancelled) return;
    while (_eventQueue.isNotEmpty && !listener.isPaused && !listener._cancelled) {
      final buffered = _eventQueue.removeFirst();
      _bufferedBytes -= buffered.bytes;
      listener._add(buffered.event);
    }
    if (listener.isPaused || listener._cancelled) return;
    final terminal = _terminalEvent;
    if (terminal != null) {
      _terminalEvent = null;
      listener._add(terminal);
    }
    if (_streamDone) listener._done();
  }

  Future<void> _cancelListener() {
    _eventQueue.clear();
    _bufferedBytes = 0;
    _terminalEvent = null;
    _streamDone = true;
    return _closing ??= _close(listenerCancelled: true);
  }

  void _notifyClosed() {
    if (_closedCallbackSent) return;
    _closedCallbackSent = true;
    _onClosed?.call(this);
  }

  RedisCommand<Object?> _helloCommand() => RedisCommand<Object?>([
    RedisArgument.text('HELLO'),
    RedisArgument.text('${_configuration.protocol.version}'),
    if (_configuration.password case final password?) ...[
      RedisArgument.text('AUTH'),
      RedisArgument.text(_configuration.username ?? 'default'),
      RedisArgument.text(password),
    ],
  ], (reply) => reply);

  RedisCommand<Object?> _selectCommand() => RedisCommand<Object?>([
    RedisArgument.text('SELECT'),
    RedisArgument.text('${_configuration.database}'),
  ], (reply) => reply);
}

RedisCommand<int> _publishCommand(String channel, RedisArgument message) {
  if (channel.isEmpty) throw ArgumentError.value(channel, 'channel', 'must not be empty');
  return RedisCommand<int>(
    [
      RedisArgument.text('PUBLISH'),
      RedisArgument.text(channel),
      message,
    ],
    (reply) => switch (reply) {
      RespInteger(:final value) => value,
      _ => throw FormatException(
        'Expected an integer PUBLISH reply, received ${reply.runtimeType}.',
      ),
    },
  );
}

RedisCommand<void> _controlCommand(String name, List<String> channels) => RedisCommand<void>([
  RedisArgument.text(name),
  ...channels.map(RedisArgument.text),
], (_) {});

Iterable<List<String>> _chunks(List<String> channels) sync* {
  for (var start = 0; start < channels.length; start += 512) {
    final end = start + 512 < channels.length ? start + 512 : channels.length;
    yield channels.sublist(start, end);
  }
}

Uint8List _replyBytes(RespValue reply) => switch (reply) {
  RespBlobString(:final value) => Uint8List.fromList(value),
  RespSimpleString(:final value) => Uint8List.fromList(utf8.encode(value)),
  _ => throw FormatException('Expected a Pub/Sub payload, received ${reply.runtimeType}.'),
};

int _eventBytes(PubSubEvent event) => switch (event) {
  PubSubMessage(:final channel, :final payload) => utf8.encode(channel).length + payload.length,
  PubSubInterrupted(:final cause, :final error) =>
    utf8.encode(cause.name).length + (error == null ? 0 : utf8.encode('$error').length),
  PubSubRestored(:final channels) => channels.fold(
    0,
    (total, channel) => total + utf8.encode(channel).length,
  ),
};

enum _ControlKind { subscribe, unsubscribe }

final class _RestorationRejected implements Exception {
  const _RestorationRejected(this.error);

  final RedisServerException error;
}

final class _ControlReservation {
  const _ControlReservation(this.commands, this.bytes);

  final int commands;
  final int bytes;
}

final class _ControlOperation {
  _ControlOperation({
    required this.kind,
    required this.channels,
    required this.additions,
    required this.revision,
    required this.deadline,
    required this.reservation,
  }) : stopwatch = Stopwatch()..start();

  final _ControlKind kind;
  final List<String> channels;
  final Set<String> additions;
  final int revision;
  final Duration deadline;
  final _ControlReservation reservation;
  final Stopwatch stopwatch;
  final Completer<void> result = Completer<void>();
  Timer? timer;
  bool submitted = false;
  bool released = false;
}

final class _BufferedEvent {
  const _BufferedEvent(this.event, this.bytes);

  final PubSubEvent event;
  final int bytes;
}

final class _Deadline {
  _Deadline(this.duration) : _stopwatch = Stopwatch()..start();

  final Duration duration;
  final Stopwatch _stopwatch;

  Duration get remaining {
    final remaining = duration - _stopwatch.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('The connection deadline expired.');
    return remaining;
  }
}

final class _PubSubTransport {
  _PubSubTransport._(
    this._socket,
    PubSubConnectionConfiguration configuration,
    this._onFrame,
    this._onTerminated,
  ) : _parser = RespParser(
        maxFrameBytes: configuration.connectionLimits.maxFrameBytes,
        maxNestingDepth: configuration.connectionLimits.maxNestingDepth,
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

  static Future<_PubSubTransport> open(
    PubSubConnectionConfiguration configuration, {
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
    final transport = _PubSubTransport._(socket, configuration, onFrame, onTerminated);
    if (!attempt.attachResource(transport.close)) {
      await transport.close();
      throw const RedisClosedException(message: 'The Pub/Sub connection was cancelled.');
    }
    return transport;
  }

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

  Future<void> sendControl(
    Uint8List bytes, {
    required _ControlKind kind,
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

  void acknowledge(_ControlKind kind, String channel) {
    final pending = _pendingControl;
    if (pending == null || pending.kind != kind || !pending.remaining.remove(channel)) return;
    if (pending.remaining.isNotEmpty) return;
    _pendingControl = null;
    pending.completer.complete();
  }

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
    for (final waiter in _replyWaiters) {
      if (!waiter.isCompleted) waiter.completeError(error, StackTrace.current);
    }
    _replyWaiters.clear();
    final pending = _pendingControl;
    _pendingControl = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error, StackTrace.current);
    }
    _onTerminated(error);
  }

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

  final _ControlKind kind;
  final Set<String> remaining;
  final Completer<void> completer = Completer<void>();
}

final class _PubSubEventStream extends Stream<PubSubEvent> {
  late PubSubSession _session;

  @override
  StreamSubscription<PubSubEvent> listen(
    void Function(PubSubEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _session._listen(onData, onError, onDone, cancelOnError ?? false);
}

final class _PubSubEventSubscription implements StreamSubscription<PubSubEvent> {
  _PubSubEventSubscription(
    this._session, {
    required this._onData,
    required this._onDone,
  }) : _zone = Zone.current;

  final PubSubSession _session;
  final Zone _zone;
  final Completer<void> _doneCompleter = Completer<void>();
  void Function(PubSubEvent)? _onData;
  void Function()? _onDone;
  int _pauseCount = 0;
  bool _cancelled = false;
  bool _doneSent = false;

  @override
  bool get isPaused => _pauseCount > 0;

  void _add(PubSubEvent event) {
    if (_cancelled || _doneSent) return;
    final onData = _onData;
    if (onData != null) _zone.runUnaryGuarded(onData, event);
  }

  void _done() {
    if (_cancelled || _doneSent) return;
    _doneSent = true;
    final onDone = _onDone;
    if (onDone != null) _zone.runGuarded(onDone);
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  @override
  Future<void> cancel() {
    if (_cancelled) return Future.value();
    _cancelled = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    return _session._cancelListener();
  }

  @override
  void onData(void Function(PubSubEvent data)? handleData) => _onData = handleData;

  @override
  void onDone(void Function()? handleDone) => _onDone = handleDone;

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    if (_cancelled || _doneSent) return;
    _pauseCount++;
    if (resumeSignal != null) unawaited(resumeSignal.whenComplete(resume));
  }

  @override
  void resume() {
    if (_pauseCount == 0) return;
    _pauseCount--;
    if (_pauseCount == 0) _session._drainEvents();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) async {
    await _doneCompleter.future;
    return futureValue as E;
  }
}

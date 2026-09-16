import 'dart:async';
import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:runnel/src/command.dart';
import 'package:runnel/src/connection/configuration.dart';
import 'package:runnel/src/connection/connection_attempt.dart';
import 'package:runnel/src/connection/operation.dart';
import 'package:runnel/src/connection/reconnect_backoff.dart';
import 'package:runnel/src/deadline.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:runnel/src/pubsub/event_queue.dart';
import 'package:runnel/src/pubsub/events.dart';
import 'package:runnel/src/pubsub/transport.dart';

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
}

/// One bounded, dynamically subscribed Pub/Sub connection.
final class PubSubSession {
  PubSubSession._(
    this._endpoint,
    this._connectTimeout,
    this._connectionLimits,
    this._controlTimeout,
    this._limits,
    this._onClosed,
  ) {
    _events = PubSubEventQueue(
      maxBufferedEvents: _limits.maxBufferedEvents,
      maxBufferedBytes: _limits.maxBufferedBytes,
      onOverflow: (limit) => _overflow(limit: limit),
    );
  }

  final ConnectionConfiguration _endpoint;
  final Duration _connectTimeout;
  final RunnelLimits _connectionLimits;
  final Duration _controlTimeout;
  final PubSubLimits _limits;
  final void Function(PubSubSession session)? _onClosed;
  late final PubSubEventQueue _events;
  final Map<String, int> _channelRevisions = {};
  final Set<String> _desiredChannels = {};
  final Set<String> _acknowledgedChannels = {};
  final Set<_ControlOperation> _controlOperations = {};
  final ReconnectBackoff _backoff = ReconnectBackoff();

  PubSubTransport? _transport;
  ConnectionAttempt? _openingTransport;
  Future<void> _controlTail = Future.value();
  Future<void>? _closing;
  Future<void>? _recovery;
  Future<void>? _explicitReconnect;
  Timer? _reconnectTimer;
  Completer<bool>? _reconnectWaiter;
  PubSubState _state = PubSubState.reconnecting;
  int _generation = 0;
  int _revision = 0;
  int _reservedControlCommands = 0;
  int _reservedControlBytes = 0;
  bool _closedCallbackSent = false;
  PubSubInterrupted? _lastInterruption;

  /// Hot events with one successful consumer acquisition per session lifetime.
  ///
  /// Consumption pulls from the session's bounded queue. Early completion,
  /// interruption, and scope exit close the session. Terminal faults discard
  /// normal queued events, emit one interruption event, then fail the next pull.
  /// A second consumer fails without disturbing the original owner.
  Flow<PubSubEvent, RunnelError> get events => Flow.fromPull(
    Effect.defer((_) {
      if (_consumerClaimed) {
        return Effect.fail<PubSubSession, RunnelError>(
          const RunnelUsageError('Pub/Sub events permit one consumer per session lifetime.'),
        );
      }
      _consumerClaimed = true;
      return Effect.succeed<PubSubSession, RunnelError>(this);
    }),
    next: (session, _) => RunnelOperation.run((operation) {
      operation.onCancel(() => session._closing ??= session._close(listenerCancelled: true));
      return session._events.next();
    }),
    release: (session, _) => RunnelOperation.release(
      () => session._closing ??= session._close(listenerCancelled: true),
    ),
  );

  bool _consumerClaimed = false;

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
    await _openTransport(Deadline(_connectTimeout));
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      throw RunnelClosedError(
        'The Pub/Sub session closed during acquisition.',
        stackTrace: StackTrace.current,
      );
    }
    _generation = 1;
    _backoff.reset();
    _state = PubSubState.ready;
  }

  Future<void> _openTransport(Deadline deadline) async {
    final attempt = ConnectionAttempt();
    _openingTransport = attempt;
    late final PubSubTransport transport;
    var transportOpened = false;
    try {
      transport = await PubSubTransport.open(
        _endpoint,
        limits: _connectionLimits,
        deadline: deadline,
        attempt: attempt,
        acceptsChannel: (channel) =>
            identical(_transport, transport) && _desiredChannels.contains(channel),
        onMessage: (channel, payload) {
          if (identical(_transport, transport)) {
            _emit(PubSubMessage(generation: _generation, channel: channel, payload: payload));
          }
        },
        onAcknowledgement: (kind, channel) {
          if (!identical(_transport, transport)) return;
          switch (kind) {
            case ControlKind.subscribe:
              _acknowledgedChannels.add(channel);
            case ControlKind.unsubscribe:
              _acknowledgedChannels.remove(channel);
          }
        },
        onTerminated: (error) {
          if (identical(_transport, transport)) _onTransportTerminated(error);
        },
      );
      transportOpened = true;
      if (_state == PubSubState.closing || _state == PubSubState.closed) {
        await transport.close();
        throw RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current);
      }
      _transport = transport;
      for (final command in _endpoint.handshakeCommands) {
        await transport.requestReply(command, deadline: deadline);
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
  Effect<void, RunnelError> subscribe(List<String> channels, {Duration? timeout}) {
    final captured = List<String>.unmodifiable(channels);
    return RunnelOperation.run((operation) => _subscribe(captured, timeout, operation));
  }

  Future<void> _subscribe(
    List<String> channels,
    Duration? timeout,
    RunnelOperation execution,
  ) async {
    final deadline = RunnelOperation.validate(() => _validatedTimeout(timeout));
    final requested = RunnelOperation.validate(() => _validatedChannels(channels));
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      return Future.error(
        RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current),
      );
    }
    final resultingCount = _desiredChannels.union(requested.toSet()).length;
    if (resultingCount > _limits.maxChannels) {
      return Future.error(
        RunnelLimitError(
          'The subscription would exceed ${_limits.maxChannels} desired channels.',
          deliveryStatus: const Some(RedisDeliveryStatus.notSent),
          limit: _limits.maxChannels,
          stackTrace: StackTrace.current,
        ),
      );
    }

    final needsWire = requested
        .where((channel) => !_acknowledgedChannels.contains(channel))
        .toList();
    final reservation = _reserveControl('SUBSCRIBE', needsWire);
    execution.onCancel(() => _closing ??= _close(listenerCancelled: true));
    final operationRevision = ++_revision;
    final additions = <String>{};
    for (final channel in requested) {
      if (_desiredChannels.add(channel)) additions.add(channel);
      _channelRevisions[channel] = operationRevision;
    }
    final operation = _ControlOperation(
      kind: ControlKind.subscribe,
      channels: requested,
      additions: additions,
      revision: operationRevision,
      deadline: deadline,
      reservation: reservation,
      onRelease: _releaseControl,
    );
    return _enqueueControl(operation);
  }

  /// Removes [channels] from desired state immediately, then waits for wire acknowledgement.
  Effect<void, RunnelError> unsubscribe(List<String> channels, {Duration? timeout}) {
    final captured = List<String>.unmodifiable(channels);
    return RunnelOperation.run((operation) => _unsubscribe(captured, timeout, operation));
  }

  Future<void> _unsubscribe(
    List<String> channels,
    Duration? timeout,
    RunnelOperation execution,
  ) async {
    final deadline = RunnelOperation.validate(() => _validatedTimeout(timeout));
    final requested = RunnelOperation.validate(() => _validatedChannels(channels));
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      return Future.error(
        RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current),
      );
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
    execution.onCancel(() => _closing ??= _close(listenerCancelled: true));
    final operationRevision = ++_revision;
    for (final channel in requested) {
      _desiredChannels.remove(channel);
      _channelRevisions[channel] = operationRevision;
    }
    _events.discardMessages(requested.toSet());
    if (disconnected) return;
    final operation = _ControlOperation(
      kind: ControlKind.unsubscribe,
      channels: requested,
      additions: const {},
      revision: operationRevision,
      deadline: deadline,
      reservation: reservation,
      onRelease: _releaseControl,
    );
    return _enqueueControl(operation);
  }

  /// Replaces the physical connection and restores the desired channel set.
  Effect<void, RunnelError> reconnect({Duration? timeout}) =>
      RunnelOperation.run((operation) => _reconnect(timeout, operation));

  Future<void> _reconnect(Duration? timeout, RunnelOperation execution) {
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      return Future.error(
        RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current),
      );
    }
    RunnelOperation.validate(() {
      if (timeout != null && timeout <= Duration.zero) {
        throw ArgumentError.value(timeout, 'timeout');
      }
    });
    execution.onCancel(() => _closing ??= _close(listenerCancelled: true));
    final existing = _explicitReconnect;
    if (existing != null) return existing;
    final deadline = timeout ?? _connectTimeout + _controlTimeout;
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

  /// Releases the dedicated socket and completes event consumption normally.
  Effect<void, Never> close() => RunnelOperation.release(closeFuture);

  Future<void> _close({required bool listenerCancelled}) async {
    if (_state == PubSubState.closed) return;
    _state = PubSubState.closing;
    _cancelReconnectDelay();
    _failControls(RunnelClosedError('The Pub/Sub session closed.', stackTrace: StackTrace.current));
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
    _events.finish(discard: listenerCancelled);
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
      bytes += _controlCommand(command, chunk).encodedLength;
    }
    final connectionLimits = _connectionLimits;
    if (_reservedControlCommands + commands > connectionLimits.maxPendingCommands) {
      throw RunnelLimitError(
        'The request would exceed ${connectionLimits.maxPendingCommands} pending controls.',
        deliveryStatus: const Some(RedisDeliveryStatus.notSent),
        limit: connectionLimits.maxPendingCommands,
        stackTrace: StackTrace.current,
      );
    }
    if (_reservedControlBytes + bytes > connectionLimits.maxPendingBytes) {
      throw RunnelLimitError(
        'The request would exceed ${connectionLimits.maxPendingBytes} pending control bytes.',
        deliveryStatus: const Some(RedisDeliveryStatus.notSent),
        limit: connectionLimits.maxPendingBytes,
        stackTrace: StackTrace.current,
      );
    }
    _reservedControlCommands += commands;
    _reservedControlBytes += bytes;
    return _ControlReservation(commands, bytes);
  }

  Future<void> _enqueueControl(_ControlOperation operation) {
    _controlOperations.add(operation);
    operation.startDeadline(() => _expireControl(operation));
    final predecessor = _controlTail;
    final running = predecessor.then((_) => _runControl(operation));
    _controlTail = running.then<void>((_) {}, onError: (_, _) {});
    unawaited(
      running.then<void>(
        (_) {
          operation.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          operation.fail(error, stackTrace);
        },
      ),
    );
    return operation.future;
  }

  Future<void> _runControl(_ControlOperation operation) async {
    try {
      if (operation.isCompleted) return;
      if (_state == PubSubState.reconnecting) {
        final remaining = operation.remaining;
        if (remaining <= Duration.zero) throw TimeoutException('Subscription control timed out.');
        await _recovery!.timeout(remaining);
      }
      if (_state == PubSubState.closed || _state == PubSubState.closing) {
        throw RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current);
      }
      _state = PubSubState.subscribing;
      _ensureCurrent(operation);
      final wireChannels = switch (operation.kind) {
        ControlKind.subscribe =>
          operation.channels.where((channel) => !_acknowledgedChannels.contains(channel)).toList(),
        ControlKind.unsubscribe =>
          operation.channels.where(_acknowledgedChannels.contains).toList(),
      };
      for (final chunk in _chunks(wireChannels)) {
        _ensureCurrent(operation);
        final commandName = operation.kind == ControlKind.subscribe ? 'SUBSCRIBE' : 'UNSUBSCRIBE';
        final remaining = operation.remaining;
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
    } on RunnelSubscriptionError {
      _rollbackAdditions(operation);
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      _rollbackAdditions(operation);
      final failure = RunnelTimeoutError(
        'The Pub/Sub subscription deadline expired.',
        deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
        cause: error,
        stackTrace: stackTrace,
      );
      _terminateForControlFailure(
        PubSubInterruptionCause.subscriptionTimeout,
        failure,
      );
      Error.throwWithStackTrace(failure, stackTrace);
    } on RunnelServerError catch (error, stackTrace) {
      _rollbackAdditions(operation);
      _terminateForControlFailure(PubSubInterruptionCause.subscriptionRejection, error);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      operation.release();
      if (_state == PubSubState.subscribing && _controlOperations.isEmpty && _recovery == null) {
        _state = PubSubState.ready;
      }
    }
  }

  void _expireControl(_ControlOperation operation) {
    if (operation.isCompleted) return;
    _rollbackAdditions(operation);
    final failure = RunnelTimeoutError(
      'The Pub/Sub subscription deadline expired.',
      deliveryStatus: Some(
        operation.submitted ? RedisDeliveryStatus.outcomeUnknown : RedisDeliveryStatus.notSent,
      ),
      stackTrace: StackTrace.current,
    );
    if (operation.submitted || operation.kind == ControlKind.unsubscribe) {
      _terminateForControlFailure(PubSubInterruptionCause.subscriptionTimeout, failure);
    } else {
      operation.fail(failure, StackTrace.current);
    }
    operation.release();
  }

  void _ensureCurrent(_ControlOperation operation) {
    if (operation.isCompleted) {
      throw RunnelClosedError(
        'The Pub/Sub control operation was cancelled.',
        stackTrace: StackTrace.current,
      );
    }
    for (final channel in operation.channels) {
      if (_channelRevisions[channel] != operation.revision) {
        throw const RunnelSubscriptionError(
          'A later subscription change superseded this operation.',
        );
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
    _controlOperations.remove(operation);
    _releaseReservation(operation.reservation);
  }

  void _onTransportTerminated(Object error) {
    if (_state == PubSubState.closing || _state == PubSubState.closed) return;
    if (_generation == 0) return;
    if (error is RunnelProtocolError || error is RunnelLimitError || error is FormatException) {
      _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
      return;
    }
    final failure = RunnelTransportError(
      'The Pub/Sub connection was interrupted.',
      deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
      cause: error,
      stackTrace: StackTrace.current,
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
      error: cause == PubSubInterruptionCause.explicitReconnect
          ? const None()
          : Some(RunnelOperation.expected(error, StackTrace.current)),
    );
    _lastInterruption = interruption;
    _emit(interruption);
    if (_state != PubSubState.closed) _state = PubSubState.reconnecting;
    final transport = _transport;
    _transport = null;
    unawaited(transport?.close());
  }

  Future<void> _startExplicitReconnect(Duration timeout) async {
    final deadline = Deadline(timeout);
    final startingChannels = Set<String>.of(_desiredChannels);
    final automaticRecovery = _recovery;
    if (automaticRecovery != null) {
      _cancelReconnectDelay();
      try {
        await automaticRecovery.timeout(deadline.remaining);
      } on TimeoutException catch (error, stackTrace) {
        _failExplicitReconnect(error, stackTrace);
      }
    }
    if (_state == PubSubState.closed || _state == PubSubState.closing) {
      throw RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current);
    }
    _interrupt(
      PubSubInterruptionCause.explicitReconnect,
      RunnelTransportError(
        'The Pub/Sub connection was replaced explicitly.',
        deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
        stackTrace: StackTrace.current,
      ),
    );
    if (_state == PubSubState.closed) {
      Error.throwWithStackTrace(
        (lastInterruption!.error as Some<RunnelError>).value,
        StackTrace.current,
      );
    }
    await _beginRecovery(
      immediate: true,
      deadline: deadline,
      restorationTarget: startingChannels,
    );
  }

  Future<void> _beginRecovery({
    required bool immediate,
    Deadline? deadline,
    Set<String>? restorationTarget,
  }) {
    final existing = _recovery;
    if (existing != null) return existing;
    final recovery = _recover(
      immediate: immediate,
      deadline: deadline,
      restorationTarget: restorationTarget,
    );
    _recovery = recovery;
    unawaited(
      recovery.then<void>(
        (_) {
          if (identical(_recovery, recovery)) _recovery = null;
        },
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_recovery, recovery)) _recovery = null;
        },
      ),
    );
    return recovery;
  }

  // Automatic recovery follows current desires without an overall deadline.
  // Explicit recovery shares one deadline and restores its starting snapshot.
  Future<void> _recover({
    required bool immediate,
    Deadline? deadline,
    Set<String>? restorationTarget,
  }) async {
    var skipDelay = immediate;
    while (_state == PubSubState.reconnecting) {
      try {
        if (!skipDelay && !await _waitForReconnectDelay(_backoff.next(), deadline: deadline)) {
          if (deadline != null) {
            throw TimeoutException('The explicit Pub/Sub reconnect deadline expired.');
          }
          return;
        }
        skipDelay = false;
        await _replaceAndRestore(
          deadline: deadline,
          restorationTarget: restorationTarget,
        );
        return;
      } on Object catch (error, stackTrace) {
        if (deadline != null && error is TimeoutException) {
          _failExplicitReconnect(error, stackTrace);
        }
        _throwTerminalRecoveryFailure(error, stackTrace, automatic: deadline == null);
        if (deadline == null) {
          if (_state == PubSubState.reconnecting && _transport != null) {
            _interrupt(
              error is TimeoutException
                  ? PubSubInterruptionCause.subscriptionTimeout
                  : PubSubInterruptionCause.networkLoss,
              error,
            );
          }
          if (_state != PubSubState.reconnecting) return;
        } else {
          if (_state != PubSubState.reconnecting) {
            throw RunnelClosedError(
              'The Pub/Sub session is closed.',
              stackTrace: StackTrace.current,
            );
          }
          try {
            deadline.remaining;
          } on TimeoutException catch (error, stackTrace) {
            _failExplicitReconnect(error, stackTrace);
          }
        }
      }
    }
    if (deadline != null) {
      throw RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current);
    }
  }

  Never _failExplicitReconnect(TimeoutException error, StackTrace stackTrace) {
    final failure = RunnelTimeoutError(
      'The explicit Pub/Sub reconnect deadline expired.',
      deliveryStatus: const Some(RedisDeliveryStatus.notSent),
      cause: error,
      stackTrace: stackTrace,
    );
    _terminateTerminal(PubSubInterruptionCause.explicitReconnect, failure);
    Error.throwWithStackTrace(failure, stackTrace);
  }

  void _throwTerminalRecoveryFailure(
    Object error,
    StackTrace stackTrace, {
    required bool automatic,
  }) {
    if (error is _RestorationRejected) {
      _terminateTerminal(PubSubInterruptionCause.subscriptionRejection, error.error);
      Error.throwWithStackTrace(error.error, stackTrace);
    }
    if (error is RunnelServerError ||
        error is RunnelProtocolError ||
        (automatic && error is HandshakeException)) {
      _terminateTerminal(PubSubInterruptionCause.protocolFailure, error);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _replaceAndRestore({
    Deadline? deadline,
    Set<String>? restorationTarget,
  }) async {
    final previous = _transport;
    _transport = null;
    await previous?.close();
    await _openTransport(deadline ?? Deadline(_connectTimeout));
    _generation++;
    _backoff.reset();
    try {
      await _restoreDesiredChannels(
        deadline ?? Deadline(_controlTimeout),
        restorationTarget: restorationTarget,
      );
    } on RunnelServerError catch (error) {
      throw _RestorationRejected(error);
    }
    if (_state != PubSubState.reconnecting) {
      throw RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current);
    }
    _state = PubSubState.ready;
    _emit(PubSubRestored(generation: _generation, channels: _acknowledgedChannels));
  }

  Future<void> _restoreDesiredChannels(Deadline deadline, {Set<String>? restorationTarget}) async {
    while (_state == PubSubState.reconnecting) {
      final target = restorationTarget == null
          ? Set<String>.of(_desiredChannels)
          : restorationTarget.where(_desiredChannels.contains).toSet();
      final removals = _acknowledgedChannels.difference(_desiredChannels).toList();
      final additions = target.difference(_acknowledgedChannels).toList();
      if (removals.isEmpty && additions.isEmpty) return;
      for (final chunk in _chunks(removals)) {
        await _sendRestorationControl(ControlKind.unsubscribe, chunk, deadline.remaining);
      }
      for (final chunk in _chunks(additions)) {
        final stillDesired = chunk.where(_desiredChannels.contains).toList();
        if (stillDesired.isNotEmpty) {
          await _sendRestorationControl(ControlKind.subscribe, stillDesired, deadline.remaining);
        }
      }
    }
    throw RunnelClosedError('The Pub/Sub session is closed.', stackTrace: StackTrace.current);
  }

  Future<void> _sendRestorationControl(
    ControlKind kind,
    List<String> channels,
    Duration timeout,
  ) {
    final name = kind == ControlKind.subscribe ? 'SUBSCRIBE' : 'UNSUBSCRIBE';
    final command = _controlCommand(name, channels);
    final encoded = encodeCommand(command as RedisCommand<Object?>);
    final connectionLimits = _connectionLimits;
    if (encoded.length > connectionLimits.maxPendingBytes) {
      throw RunnelLimitError(
        'Restoration exceeds ${connectionLimits.maxPendingBytes} pending control bytes.',
        deliveryStatus: const Some(RedisDeliveryStatus.notSent),
        limit: connectionLimits.maxPendingBytes,
        stackTrace: StackTrace.current,
      );
    }
    return _transport!.sendControl(encoded, kind: kind, channels: channels).timeout(timeout);
  }

  Future<bool> _waitForReconnectDelay(Duration delay, {Deadline? deadline}) {
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
      error: Some(RunnelOperation.expected(error, StackTrace.current)),
    );
    _lastInterruption = interruption;
    _state = PubSubState.closed;
    _cancelReconnectDelay();
    _acknowledgedChannels.clear();
    _failControls(error);
    _events.finish(discard: true, terminal: interruption);
    final transport = _transport;
    _transport = null;
    final release = _releaseTerminalResources(_openingTransport, transport);
    _closing ??= release.whenComplete(_notifyClosed);
  }

  void _emit(PubSubEvent event) {
    if (_state == PubSubState.closed && event is! PubSubInterrupted) return;
    _events.add(event);
  }

  void _overflow({required int limit}) => _terminateTerminal(
    PubSubInterruptionCause.bufferOverflow,
    RunnelLimitError(
      'The Pub/Sub event buffer exceeded its configured limit.',
      deliveryStatus: const Some(RedisDeliveryStatus.outcomeUnknown),
      limit: limit,
      stackTrace: StackTrace.current,
    ),
  );

  Future<void> _releaseTerminalResources(
    ConnectionAttempt? opening,
    PubSubTransport? transport,
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
      operation.fail(error, StackTrace.current);
    }
  }

  void _notifyClosed() {
    if (_closedCallbackSent) return;
    _closedCallbackSent = true;
    _onClosed?.call(this);
  }
}

RedisCommand<void> _controlCommand(String name, List<String> channels) => builtInCommand<void>([
  RedisArgument.text(name),
  ...channels.map(RedisArgument.text),
], (_) {});

Iterable<List<String>> _chunks(List<String> channels) sync* {
  for (var start = 0; start < channels.length; start += 512) {
    final end = start + 512 < channels.length ? start + 512 : channels.length;
    yield channels.sublist(start, end);
  }
}

final class _RestorationRejected implements Exception {
  const _RestorationRejected(this.error);

  final RunnelServerError error;
}

final class _ControlReservation {
  const _ControlReservation(this.commands, this.bytes);

  final int commands;
  final int bytes;
}

/// Owns one caller's deadline, completion, and reserved control capacity.
final class _ControlOperation {
  _ControlOperation({
    required this.kind,
    required this.channels,
    required this.additions,
    required this.revision,
    required Duration deadline,
    required this.reservation,
    required this._onRelease,
  }) : _deadline = Deadline(deadline);

  final ControlKind kind;
  final List<String> channels;
  final Set<String> additions;
  final int revision;
  final _ControlReservation reservation;
  final Deadline _deadline;
  final void Function(_ControlOperation) _onRelease;
  final Completer<void> _result = Completer<void>();
  Timer? _timer;
  bool submitted = false;
  bool _released = false;

  Future<void> get future => _result.future;
  bool get isCompleted => _result.isCompleted;
  Duration get remaining => _deadline.timeLeft;

  void startDeadline(void Function() onExpire) => _timer = Timer(remaining, onExpire);

  void complete() {
    if (!isCompleted) _result.complete();
    release();
  }

  void fail(Object error, StackTrace stackTrace) {
    if (!isCompleted) _result.completeError(error, stackTrace);
    release();
  }

  void release() {
    if (_released) return;
    _released = true;
    _timer?.cancel();
    _onRelease(this);
  }
}

/// Package-internal parent ownership operations.
extension PubSubSessionOwnership on PubSubSession {
  /// Opens a dedicated connection and completes its HELLO/SELECT handshake.
  ///
  /// [onClosed] is invoked once after the socket is released so a parent client can
  /// unregister ownership.
  static Future<PubSubSession> connect(
    ConnectionConfiguration configuration, {
    required Duration connectTimeout,
    required RunnelLimits connectionLimits,
    Duration controlTimeout = const Duration(seconds: 5),
    PubSubLimits limits = const PubSubLimits(),
    void Function(PubSubSession session)? onClosed,
    void Function(PubSubSession session)? onCreated,
  }) async {
    RunnelOperation.validate(() {
      connectionLimits.validate();
      if (connectTimeout <= Duration.zero) {
        throw ArgumentError.value(connectTimeout, 'connectTimeout', 'must be positive');
      }
      limits._validate();
      if (controlTimeout <= Duration.zero) {
        throw ArgumentError.value(controlTimeout, 'controlTimeout', 'must be positive');
      }
    });
    final session = PubSubSession._(
      configuration,
      connectTimeout,
      connectionLimits,
      controlTimeout,
      limits,
      onClosed,
    );
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

  /// Releases this session for its owning client without starting another runtime.
  Future<void> closeFuture() => _closing ??= _close(listenerCancelled: false);
}

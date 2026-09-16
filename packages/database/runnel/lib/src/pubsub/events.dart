import 'dart:convert';
import 'dart:typed_data';

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

/// Internal queue accounting without copying message payloads.
extension PubSubEventSize on PubSubEvent {
  /// Retained payload and textual metadata size.
  int get bufferedBytes => switch (this) {
    PubSubMessage(:final channel, :final _payload) => utf8.encode(channel).length + _payload.length,
    PubSubInterrupted(:final cause, :final error) =>
      utf8.encode(cause.name).length + (error == null ? 0 : utf8.encode('$error').length),
    PubSubRestored(:final channels) => channels.fold(
      0,
      (total, channel) => total + utf8.encode(channel).length,
    ),
  };
}

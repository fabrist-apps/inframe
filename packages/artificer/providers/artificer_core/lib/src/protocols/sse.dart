import 'package:artificer_core/src/native.dart';

/// One decoded Server-Sent Event.
final class SseEvent {
  /// Creates a [SseEvent].
  const SseEvent({required this.data, this.event, this.id, this.retry});

  /// The immutable native replay data.
  final String data;

  /// The native SSE event name, when supplied.
  final String? event;

  /// The stable identifier.
  final String? id;

  /// The server-suggested reconnection delay, when supplied.
  final Duration? retry;
}

/// Stateful decoding rules created independently for each SSE consumption.
abstract interface class SseProtocol<A> {
  /// Partial immutable output attached to framing, transport, or limit errors.
  Object? get partialOutput;

  /// Emits values after response headers have been accepted.
  Iterable<A> start(ResponseMetadata metadata);

  /// Decodes one complete SSE record.
  Iterable<A> decode(SseEvent event);

  /// Whether the protocol has recognized an early terminal record.
  bool get isTerminal;

  /// Validates terminal state and emits final values after transport cleanup.
  Iterable<A> finish();
}

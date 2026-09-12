import '../native.dart';

/// One decoded Server-Sent Event.
final class SseEvent {
  const SseEvent({required this.data, this.event, this.id, this.retry});

  final String data;
  final String? event;
  final String? id;
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

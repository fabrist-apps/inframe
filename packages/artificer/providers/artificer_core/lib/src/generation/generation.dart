import '../messages/messages.dart';
import '../native.dart';

/// A normalized reason that generation stopped.
enum FinishReason { stop, toolCalls, outputLimit, refusal, contentFilter, paused, other }

/// Common generation settings.
final class GenerationOptions {
  GenerationOptions({
    this.maxOutputTokens = 4096,
    this.temperature,
    this.topP,
    Iterable<String> stopSequences = const [],
  }) : stopSequences = List.unmodifiable(stopSequences) {
    if (maxOutputTokens <= 0) {
      throw ArgumentError.value(maxOutputTokens, 'maxOutputTokens', 'must be positive');
    }
    _validateUnit(temperature, 'temperature');
    _validateUnit(topP, 'topP');
    if (this.stopSequences.any((value) => value.isEmpty)) {
      throw ArgumentError.value(stopSequences, 'stopSequences', 'must not contain empty values');
    }
  }

  final int maxOutputTokens;
  final double? temperature;
  final double? topP;
  final List<String> stopSequences;
}

/// A request for one foreground generation candidate.
final class GenerationRequest {
  GenerationRequest({
    required Iterable<Message> messages,
    this.instructions,
    GenerationOptions? options,
  }) : messages = List.unmodifiable(messages),
       options = options ?? GenerationOptions() {
    if (this.messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
  }

  final String? instructions;
  final List<Message> messages;
  final GenerationOptions options;
}

/// Token accounting reported by a provider.
final class Usage {
  const Usage({this.inputTokens, this.outputTokens, this.totalTokens});

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
}

/// A normalized generation outcome.
final class GenerationResult {
  GenerationResult({
    required this.message,
    required this.finishReason,
    required this.nativePayload,
    required this.metadata,
    this.nativeFinishReason,
    this.usage,
    this.responseId,
    this.requestId,
  });

  final AssistantMessage message;
  final FinishReason finishReason;
  final String? nativeFinishReason;
  final Usage? usage;
  final String? responseId;
  final String? requestId;
  final NativePayload nativePayload;
  final ResponseMetadata metadata;

  String get text => message.text;
}

/// One event emitted by a generation stream.
sealed class GenerationEvent {
  const GenerationEvent();
}

/// The successful terminal event for a generation stream.
final class GenerationFinished extends GenerationEvent {
  const GenerationFinished(this.result);

  final GenerationResult result;
}

void _validateUnit(double? value, String name) {
  if (value != null && (!value.isFinite || value < 0 || value > 1)) {
    throw ArgumentError.value(value, name, 'must be finite and between 0 and 1');
  }
}

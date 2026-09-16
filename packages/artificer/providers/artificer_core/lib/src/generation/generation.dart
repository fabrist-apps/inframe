import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/serialization.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'generation.mapper.dart';

/// Common request options; optional sampling values are omitted unless supplied.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class GenerationOptions with GenerationOptionsMappable {
  /// Creates a [GenerationOptions] retaining the supplied values.
  const GenerationOptions({
    this.maxOutputTokens = 4096,
    this.temperature,
    this.topP,
    this.stop = const [],
  });

  /// Maximum output tokens; the common default is 4096.
  final int maxOutputTokens;

  /// Optional sampling temperature, omitted when absent.
  final double? temperature;

  /// Optional nucleus sampling value, omitted when absent.
  final double? topP;

  /// Stop sequences, preserving caller order.
  final List<String> stop;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = GenerationOptionsMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = GenerationOptionsMapper.fromJson;
}

/// One foreground inference with explicit ordered history.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class GenerationRequest with GenerationRequestMappable {
  /// Creates a [GenerationRequest] retaining the supplied values.
  GenerationRequest({
    required this.messages,
    this.instructions,
    this.options = const GenerationOptions(),
  }) {
    if (messages.isEmpty) throw ArgumentError.value(messages, 'messages', 'Must not be empty.');
  }

  /// Ordered conversation turns, read when execution begins.
  final List<Message> messages;

  /// Instructions separate from the conversation history.
  final String? instructions;

  /// Common per-request generation options.
  final GenerationOptions options;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = GenerationRequestMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = GenerationRequestMapper.fromJson;
}

/// Normalized completion reason; incomplete output remains inspectable.
@MappableEnum()
enum FinishReason {
  /// Stop.
  stop,

  /// Tool calls.
  toolCalls,

  /// Output limit.
  outputLimit,

  /// Refusal.
  refusal,

  /// Content filter.
  contentFilter,

  /// Paused.
  paused,

  /// Other.
  other,
}

/// Available usage fields are nullable; missing does not mean zero.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class Usage with UsageMappable {
  /// Creates a [Usage] retaining the supplied values.
  const Usage({this.inputTokens, this.outputTokens, this.totalTokens});

  /// Input tokens.
  final int? inputTokens;

  /// Output tokens.
  final int? outputTokens;

  /// Total tokens.
  final int? totalTokens;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = UsageMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = UsageMapper.fromJson;
}

/// Normalized and native views of the same result.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class GenerationResult with GenerationResultMappable {
  /// Creates a [GenerationResult] retaining the supplied values.
  GenerationResult({
    required this.message,
    required this.finishReason,
    required this.native,
    this.nativeFinishReason,
    this.usage,
    this.responseId,
    this.metadata,
    this.schemaVersion = 1,
  }) {
    DomainSchema.check(schemaVersion);
  }

  /// Human-readable detail, available only through explicit inspection.
  final AssistantMessage message;

  /// Normalized completion reason.
  final FinishReason finishReason;

  /// Complete provider payload from the same inference.
  final NativePayload native;

  /// Original provider completion reason.
  final String? nativeFinishReason;

  /// Available cumulative usage; absent fields remain null.
  final Usage? usage;

  /// Response id.
  final String? responseId;

  /// HTTP response metadata for explicit inspection.
  final ResponseMetadata? metadata;

  /// Persisted domain schema version; only version 1 is supported.
  final int schemaVersion;

  /// The text content.
  String get text => message.text;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = GenerationResultMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = GenerationResultMapper.fromJson;
}

/// Events of one cold generation stream.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class GenerationEvent with GenerationEventMappable {
  /// Creates a [GenerationEvent] retaining the supplied values.
  const GenerationEvent();

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = GenerationEventMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = GenerationEventMapper.fromJson;
}

/// Final assembled result after transport cleanup.
@MappableClass(
  discriminatorValue: 'finished',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class GenerationFinished extends GenerationEvent with GenerationFinishedMappable {
  /// Creates a [GenerationFinished] retaining the supplied values.
  const GenerationFinished(this.result);

  /// Result.
  final GenerationResult result;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = GenerationFinishedMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = GenerationFinishedMapper.fromJson;
}

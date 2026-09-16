import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/serialization.dart';
import 'package:artificer_core/src/settings.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'generation.mapper.dart';

/// Common per-request overrides; omitted options inherit model and SDK defaults.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class GenerationOptions with GenerationOptionsMappable {
  /// Creates overrides without resolving or copying their values.
  const GenerationOptions({
    this.maxOutputTokens = const Setting.inherit(),
    this.temperature = const Setting.inherit(),
    this.topP = const Setting.inherit(),
    this.stop = const Setting.inherit(),
  });

  /// Maximum output tokens; the inherited SDK default is 4096.
  final Setting<int> maxOutputTokens;

  /// Optional temperature; absent by default.
  final Setting<double> temperature;

  /// Optional nucleus sampling; absent by default.
  final Setting<double> topP;

  /// Stop sequences; a replacement list is never concatenated.
  final Setting<List<String>> stop;

  /// Resolves SDK defaults, model defaults, then these per-call overrides.
  ResolvedGenerationOptions resolve([GenerationOptions defaults = const GenerationOptions()]) =>
      ResolvedGenerationOptions(
        maxOutputTokens: maxOutputTokens.resolve(defaults.maxOutputTokens.resolve(4096)),
        temperature: temperature.resolve(defaults.temperature.resolve(null)),
        topP: topP.resolve(defaults.topP.resolve(null)),
        stop: stop.resolve(defaults.stop.resolve(const [])),
      );

  /// Decodes persisted map data.
  static const fromMap = GenerationOptionsMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = GenerationOptionsMapper.fromJson;
}

/// Resolved common options ready for endpoint-specific field translation.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class ResolvedGenerationOptions with ResolvedGenerationOptionsMappable {
  /// Creates resolved values; null means omit the corresponding native field.
  const ResolvedGenerationOptions({this.maxOutputTokens, this.temperature, this.topP, this.stop});

  /// Maximum output tokens, or an explicitly cleared default.
  final int? maxOutputTokens;

  /// Optional sampling temperature.
  final double? temperature;

  /// Optional nucleus sampling.
  final double? topP;

  /// Stop sequences, or an explicitly cleared value.
  final List<String>? stop;

  /// Returns a typed configuration failure before network work.
  InvalidRequestError? validate() {
    if (maxOutputTokens != null && maxOutputTokens! <= 0) {
      return const InvalidRequestError('maxOutputTokens must be positive.');
    }
    if (temperature != null && (!temperature!.isFinite || temperature! < 0)) {
      return const InvalidRequestError('temperature must be finite and nonnegative.');
    }
    if (topP != null && (!topP!.isFinite || topP! < 0 || topP! > 1)) {
      return const InvalidRequestError('topP must be between zero and one.');
    }
    return null;
  }

  /// Encodes resolved native fields without domain tags or Setting wrappers.
  Map<String, Object?> toWire({String maxOutputTokensKey = 'max_tokens'}) => {
    if (maxOutputTokens != null) maxOutputTokensKey: maxOutputTokens,
    if (temperature != null) 'temperature': temperature,
    if (topP != null) 'top_p': topP,
    if (stop != null && stop!.isNotEmpty) 'stop': stop,
  };

  /// Decodes persisted map data.
  static const fromMap = ResolvedGenerationOptionsMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = ResolvedGenerationOptionsMapper.fromJson;
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

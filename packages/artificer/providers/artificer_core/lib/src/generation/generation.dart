import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/json/json_value_hook.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/serialization.dart';
import 'package:artificer_core/src/settings.dart';
import 'package:artificer_core/src/tools/tools.dart';
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
    this.tools = const [],
    this.toolChoice = const AutoToolChoice(),
    this.output = const TextOutput(),
  }) {
    if (messages.isEmpty) throw ArgumentError.value(messages, 'messages', 'Must not be empty.');
  }

  /// Ordered conversation turns, read when execution begins.
  final List<Message> messages;

  /// Instructions separate from the conversation history.
  final String? instructions;

  /// Common per-request generation options.
  final GenerationOptions options;

  /// Application declarations; the provider never executes these functions.
  final List<FunctionTool> tools;

  /// Requested function-selection policy.
  final ToolChoice toolChoice;

  /// Requested output encoding, without application-schema validation.
  final OutputFormat output;

  /// Checks explicit history and native replay compatibility before I/O.
  InvalidRequestError? validate({
    required String providerId,
    required String api,
    required String modelId,
  }) {
    if (messages.isEmpty) return const InvalidRequestError('Messages must not be empty.');
    final names = <String>{};
    for (final tool in tools) {
      if (!names.add(tool.name)) return const InvalidRequestError('Conflicting tool declarations.');
    }
    if (toolChoice case NamedToolChoice(:final name)) {
      if (!names.contains(name)) return const InvalidRequestError('Named tool is not declared.');
    }
    final calls = <String, ToolCallPart>{};
    final thisResultIds = <String>{};
    for (final message in messages) {
      switch (message) {
        case UserMessage(:final parts):
          if (parts.isEmpty) return const InvalidRequestError('User parts must not be empty.');
        case AssistantMessage(:final parts, :final replay):
          if (replay != null &&
              (replay.providerId != providerId || replay.api != api || replay.modelId != modelId)) {
            return const InvalidRequestError('Provider replay target is incompatible.');
          }
          for (final part in parts.whereType<ToolCallPart>()) {
            if (calls.containsKey(part.callId)) {
              return const InvalidRequestError('Duplicate application call ID.');
            }
            calls[part.callId] = part;
            if (part.arguments case NativeToolArguments(
              providerId: final owner,
              api: final dialect,
            )) {
              if (owner != providerId || dialect != api) {
                return const InvalidRequestError('Native action target is incompatible.');
              }
            }
          }
        case ToolMessage(:final results):
          if (results.isEmpty) return const InvalidRequestError('Tool results must not be empty.');
          for (final result in results) {
            final call = calls[result.callId];
            if (call == null) {
              return const InvalidRequestError(
                'Tool result references a missing application call.',
              );
            }
            if (!thisResultIds.add(result.callId)) {
              return const InvalidRequestError('Duplicate tool result ID.');
            }
            if (result.content case NativeToolResultContent(
              providerId: final owner,
              api: final dialect,
            )) {
              if (owner != providerId || dialect != api) {
                return const InvalidRequestError('Native result target is incompatible.');
              }
              if (call.arguments case NativeToolArguments(
                providerId: final callOwner,
                api: final callApi,
              )) {
                if (owner != callOwner || dialect != callApi) {
                  return const InvalidRequestError('Native result does not match its call.');
                }
              } else {
                return const InvalidRequestError('Native result requires a native action call.');
              }
            }
          }
      }
    }
    return null;
  }

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

/// Semantic content expected for a stable local part.
@MappableEnum()
enum GenerationPartKind {
  /// Visible model text.
  text,

  /// Public reasoning summary only.
  reasoning,

  /// Refusal text.
  refusal,

  /// Caller executed action.
  toolCall,

  /// Provider executed action record.
  providerTool,

  /// Unnormalized native content.
  opaque,
}

/// Closed ContentDelta variants.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class ContentDelta with ContentDeltaMappable {
  /// Creates a variant.
  const ContentDelta();

  /// Decodes persisted map data.
  static const fromMap = ContentDeltaMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ContentDeltaMapper.fromJson;
}

/// TextDelta.
@MappableClass(
  discriminatorValue: 'text',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class TextDelta extends ContentDelta with TextDeltaMappable {
  /// Creates the value retaining supplied collections.
  const TextDelta({required this.text});

  /// Text.
  final String text;

  /// Decodes persisted map data.
  static const fromMap = TextDeltaMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = TextDeltaMapper.fromJson;
}

/// ReasoningDelta.
@MappableClass(
  discriminatorValue: 'reasoning',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ReasoningDelta extends ContentDelta with ReasoningDeltaMappable {
  /// Creates the value retaining supplied collections.
  const ReasoningDelta({required this.text});

  /// Text.
  final String text;

  /// Decodes persisted map data.
  static const fromMap = ReasoningDeltaMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ReasoningDeltaMapper.fromJson;
}

/// ToolArgumentsDelta.
@MappableClass(
  discriminatorValue: 'toolArguments',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ToolArgumentsDelta extends ContentDelta with ToolArgumentsDeltaMappable {
  /// Creates the value retaining supplied collections.
  const ToolArgumentsDelta({required this.text});

  /// Text.
  final String text;

  /// Decodes persisted map data.
  static const fromMap = ToolArgumentsDeltaMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ToolArgumentsDeltaMapper.fromJson;
}

/// GenerationStarted.
@MappableClass(
  discriminatorValue: 'started',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class GenerationStarted extends GenerationEvent with GenerationStartedMappable {
  /// Creates the value retaining supplied collections.
  const GenerationStarted({this.responseId, this.requestId});

  /// ResponseId.
  final String? responseId;

  /// RequestId.
  final String? requestId;

  /// Decodes persisted map data.
  static const fromMap = GenerationStartedMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = GenerationStartedMapper.fromJson;
}

/// PartStarted.
@MappableClass(
  discriminatorValue: 'partStarted',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class PartStarted extends GenerationEvent with PartStartedMappable {
  /// Creates the value retaining supplied collections.
  const PartStarted({
    required this.id,
    required this.index,
    required this.kind,
    this.callId,
    this.name,
    this.owner,
  });

  /// Id.
  final String id;

  /// Index.
  final int index;

  /// Kind.
  final GenerationPartKind kind;

  /// CallId.
  final String? callId;

  /// Name.
  final String? name;

  /// Owner.
  final ToolExecutionOwner? owner;

  /// Decodes persisted map data.
  static const fromMap = PartStartedMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = PartStartedMapper.fromJson;
}

/// PartDelta.
@MappableClass(
  discriminatorValue: 'partDelta',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class PartDelta extends GenerationEvent with PartDeltaMappable {
  /// Creates the value retaining supplied collections.
  const PartDelta({required this.id, required this.delta});

  /// Id.
  final String id;

  /// Delta.
  final ContentDelta delta;

  /// Decodes persisted map data.
  static const fromMap = PartDeltaMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = PartDeltaMapper.fromJson;
}

/// PartFinished.
@MappableClass(
  discriminatorValue: 'partFinished',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class PartFinished extends GenerationEvent with PartFinishedMappable {
  /// Creates the value retaining supplied collections.
  const PartFinished({required this.id, required this.part});

  /// Id.
  final String id;

  /// Part.
  final OutputPart part;

  /// Decodes persisted map data.
  static const fromMap = PartFinishedMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = PartFinishedMapper.fromJson;
}

/// UsageUpdated.
@MappableClass(
  discriminatorValue: 'usageUpdated',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class UsageUpdated extends GenerationEvent with UsageUpdatedMappable {
  /// Creates the value retaining supplied collections.
  const UsageUpdated({required this.usage});

  /// Usage.
  final Usage usage;

  /// Decodes persisted map data.
  static const fromMap = UsageUpdatedMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = UsageUpdatedMapper.fromJson;
}

/// ProviderEvent.
@MappableClass(
  discriminatorValue: 'providerEvent',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ProviderEvent extends GenerationEvent with ProviderEventMappable {
  /// Creates the value retaining supplied collections.
  const ProviderEvent({
    required this.providerId,
    required this.api,
    required this.event,
    required this.data,
  });

  /// ProviderId.
  final String providerId;

  /// Api.
  final String api;

  /// Event.
  final String event;

  /// Data.
  @MappableField(hook: JsonValueHook())
  final Object? data;

  /// Decodes persisted map data.
  static const fromMap = ProviderEventMapper.fromMap;

  /// Decodes persisted JSON.
  static const fromJson = ProviderEventMapper.fromJson;
}

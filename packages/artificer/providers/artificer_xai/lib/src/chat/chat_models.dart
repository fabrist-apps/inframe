import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';

/// A native Chat Completions role.
enum XaiChatRole {
  /// System-level instructions.
  system,

  /// Developer-level instructions.
  developer,

  /// End-user input.
  user,

  /// Prior assistant output.
  assistant,

  /// A caller-provided tool result.
  tool,
}

/// One native Chat Completions message.
final class XaiChatMessage {
  /// Creates a typed native message.
  XaiChatMessage({
    required this.role,
    required this.content,
    this.name,
    this.toolCallId,
    JsonObject? extraBody,
  }) : extraBody = extraBody ?? JsonObject({}) {
    _rejectCollisions(this.extraBody, {'role', 'content', 'name', 'tool_call_id'});
  }

  /// Creates a user text message.
  XaiChatMessage.userText(String text)
    : this(role: XaiChatRole.user, content: JsonString(_nonEmpty(text, 'text')));

  /// Native role.
  final XaiChatRole role;

  /// Native string, content-part array, or explicit null.
  final JsonValue content;

  /// Optional participant name.
  final String? name;

  /// Tool call ID for a tool result message.
  final String? toolCallId;

  /// Forward-compatible fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Encodes this native message.
  Map<String, Object?> toDart() => {
    ...extraBody.toDart(),
    'role': role.name,
    'content': content.toDart(),
    'name': ?name,
    'tool_call_id': ?toolCallId,
  };
}

/// A typed native function tool for Chat Completions.
final class XaiChatFunctionTool {
  /// Creates a function declaration.
  XaiChatFunctionTool({
    required String name,
    required this.parameters,
    this.description,
    this.strict = true,
  }) : name = _nonEmpty(name, 'name');

  /// Function name.
  final String name;

  /// Function description.
  final String? description;

  /// JSON Schema parameters.
  final JsonObject parameters;

  /// Whether Xai should enforce the schema.
  final bool strict;

  /// Encodes this native tool declaration.
  Map<String, Object?> toDart() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': ?description,
      'parameters': parameters.toDart(),
      'strict': strict,
    },
  };
}

/// A typed native request for `POST /chat/completions`.
final class XaiChatRequest {
  /// Creates a native request while preserving omitted versus explicit null fields.
  XaiChatRequest({
    required String model,
    required Iterable<XaiChatMessage> messages,
    this.maxCompletionTokens,
    this.temperature,
    this.topP,
    this.n,
    this.frequencyPenalty,
    this.presencePenalty,
    this.logprobs,
    this.topLogprobs,
    this.parallelToolCalls,
    this.promptCacheKey,
    this.reasoningEffort,
    this.seed,
    this.serviceTier,
    Iterable<String>? stop,
    this.user,
    this.searchParameters,
    Object? responseFormat = _omitted,
    Iterable<XaiChatFunctionTool>? tools,
    this.toolChoice,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       messages = List.unmodifiable(messages),
       _responseFormat = _nullableJsonObject(responseFormat, 'responseFormat'),
       _hasResponseFormat = !identical(responseFormat, _omitted),
       stop = stop == null ? null : List.unmodifiable(stop),
       tools = tools == null ? null : List.unmodifiable(tools),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    if (maxCompletionTokens != null && maxCompletionTokens! <= 0) {
      throw ArgumentError.value(maxCompletionTokens, 'maxCompletionTokens', 'must be positive');
    }
    if (n != null && n! <= 0) throw ArgumentError.value(n, 'n', 'must be positive');
    if (frequencyPenalty != null && (frequencyPenalty! < -2 || frequencyPenalty! > 2)) {
      throw ArgumentError.value(frequencyPenalty, 'frequencyPenalty', 'must be between -2 and 2');
    }
    if (presencePenalty != null && (presencePenalty! < -2 || presencePenalty! > 2)) {
      throw ArgumentError.value(presencePenalty, 'presencePenalty', 'must be between -2 and 2');
    }
    if (topLogprobs != null && (topLogprobs! < 0 || topLogprobs! > 8)) {
      throw ArgumentError.value(topLogprobs, 'topLogprobs', 'must be between 0 and 8');
    }
    if (this.stop != null &&
        (this.stop!.isEmpty || this.stop!.length > 4 || this.stop!.any((value) => value.isEmpty))) {
      throw ArgumentError.value(stop, 'stop', 'must contain between 1 and 4 nonempty values');
    }
    _rejectCollisions(this.extraBody, _typedRequestFields);
  }

  /// Provider-local model ID.
  final String model;

  /// Ordered native messages.
  final List<XaiChatMessage> messages;

  /// Maximum generated tokens.
  final int? maxCompletionTokens;

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus-sampling threshold.
  final double? topP;

  /// Number of choices requested.
  final int? n;

  /// Frequency penalty between -2 and 2.
  final double? frequencyPenalty;

  /// Presence penalty between -2 and 2.
  final double? presencePenalty;

  /// Whether token log probabilities are returned.
  final bool? logprobs;

  /// Number of alternative token log probabilities to return.
  final int? topLogprobs;

  /// Whether multiple tool calls may run in parallel.
  final bool? parallelToolCalls;

  /// Stable xAI prompt-cache routing key.
  final String? promptCacheKey;

  /// Native reasoning effort.
  final String? reasoningEffort;

  /// Best-effort deterministic sampling seed.
  final int? seed;

  /// Native service tier.
  final String? serviceTier;

  /// Native stop sequences.
  final List<String>? stop;

  /// Caller-defined End User identifier.
  final String? user;

  /// Typed native search configuration preserved as validated JSON.
  final JsonObject? searchParameters;

  /// Structured-output configuration, or null when explicitly cleared.
  JsonObject? get responseFormat => _responseFormat;

  final JsonObject? _responseFormat;
  final bool _hasResponseFormat;

  /// Native function declarations.
  final List<XaiChatFunctionTool>? tools;

  /// Native tool-selection value.
  final JsonValue? toolChoice;

  /// Forward-compatible fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Encodes the request for ordinary or streaming transport.
  JsonObject toJson({required bool stream}) => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'messages': messages.map((message) => message.toDart()).toList(),
    'max_completion_tokens': ?maxCompletionTokens,
    'temperature': ?temperature,
    'top_p': ?topP,
    'n': ?n,
    'frequency_penalty': ?frequencyPenalty,
    'presence_penalty': ?presencePenalty,
    'logprobs': ?logprobs,
    'top_logprobs': ?topLogprobs,
    'parallel_tool_calls': ?parallelToolCalls,
    'prompt_cache_key': ?promptCacheKey,
    'reasoning_effort': ?reasoningEffort,
    'seed': ?seed,
    'service_tier': ?serviceTier,
    'stop': ?stop,
    'user': ?user,
    if (searchParameters case final value?) 'search_parameters': value.toDart(),
    if (_hasResponseFormat) 'response_format': _responseFormat?.toDart(),
    if (tools case final value?) 'tools': value.map((tool) => tool.toDart()).toList(),
    if (toolChoice case final value?) 'tool_choice': value.toDart(),
    'stream': stream,
  });
}

/// One typed native Chat Completions response.
final class XaiChatCompletion {
  /// Decodes a native completion.
  factory XaiChatCompletion.fromJson(JsonObject raw) =>
      XaiChatCompletion._(OpenAiCompatibleChatResponse.fromJson(raw));

  /// Wraps the shared strict wire representation without decoding twice.
  factory XaiChatCompletion.fromCompatible(OpenAiCompatibleChatResponse response) =>
      XaiChatCompletion._(response);

  const XaiChatCompletion._(this.compatible);

  /// Shared strict wire representation used by the transport codec.
  final OpenAiCompatibleChatResponse compatible;

  /// Completion ID.
  String get id => compatible.id;

  /// Actual provider model ID.
  String get model => compatible.model;

  /// Indexed native choices.
  List<XaiChatChoice> get choices => compatible.choices;

  /// Token usage when returned.
  Usage? get usage => compatible.usage;

  /// Complete native object.
  JsonObject get raw => compatible.raw;

  /// Fields outside the typed snapshot.
  JsonObject get extensions => compatible.extensions;
}

/// One indexed native completion choice.
typedef XaiChatChoice = OpenAiCompatibleChoice;

/// One typed native chat stream event.
typedef XaiChatEvent = OpenAiCompatibleStreamEvent;

/// One typed native chat stream chunk.
typedef XaiChatChunk = OpenAiCompatibleChunk;

/// An unrecognized native stream object retained without loss.
typedef XaiUnknownChatEvent = OpenAiCompatibleUnknownEvent;

/// The terminal `[DONE]` event, emitted after response-body cleanup.
typedef XaiChatDone = OpenAiCompatibleDone;

const _omitted = Object();

const _typedRequestFields = {
  'model',
  'messages',
  'max_completion_tokens',
  'temperature',
  'top_p',
  'n',
  'frequency_penalty',
  'presence_penalty',
  'logprobs',
  'top_logprobs',
  'parallel_tool_calls',
  'prompt_cache_key',
  'reasoning_effort',
  'seed',
  'service_tier',
  'stop',
  'user',
  'search_parameters',
  'response_format',
  'tools',
  'tool_choice',
  'stream',
};

JsonObject? _nullableJsonObject(Object? value, String name) {
  if (identical(value, _omitted) || value == null) return null;
  if (value is! JsonObject) {
    throw ArgumentError.value(value, name, 'must be a JsonObject or null');
  }
  return value;
}

void _rejectCollisions(JsonObject extraBody, Set<String> typedFields) {
  final collision = extraBody.toDart().keys.where(typedFields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(collision, 'extraBody', 'collides with a typed field');
  }
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

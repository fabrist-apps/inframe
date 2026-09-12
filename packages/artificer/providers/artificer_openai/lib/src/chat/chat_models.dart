import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';

/// A native Chat Completions role.
enum OpenAIChatRole {
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
final class OpenAIChatMessage {
  /// Creates a typed native message.
  OpenAIChatMessage({
    required this.role,
    required this.content,
    this.name,
    this.toolCallId,
    JsonObject? extraBody,
  }) : extraBody = extraBody ?? JsonObject({}) {
    _rejectCollisions(this.extraBody, {'role', 'content', 'name', 'tool_call_id'});
  }

  /// Creates a user text message.
  OpenAIChatMessage.userText(String text)
    : this(role: OpenAIChatRole.user, content: JsonString(_nonEmpty(text, 'text')));

  /// Native role.
  final OpenAIChatRole role;

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
final class OpenAIChatFunctionTool {
  /// Creates a function declaration.
  OpenAIChatFunctionTool({
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

  /// Whether OpenAI should enforce the schema.
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
final class OpenAIChatRequest {
  /// Creates a native request while preserving omitted versus explicit null fields.
  OpenAIChatRequest({
    required String model,
    required Iterable<OpenAIChatMessage> messages,
    this.maxCompletionTokens,
    this.temperature,
    this.topP,
    this.n,
    this.reasoningEffort,
    this.serviceTier,
    Object? responseFormat = _omitted,
    Iterable<OpenAIChatFunctionTool>? tools,
    this.toolChoice,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       messages = List.unmodifiable(messages),
       _responseFormat = _nullableJsonObject(responseFormat, 'responseFormat'),
       _hasResponseFormat = !identical(responseFormat, _omitted),
       tools = tools == null ? null : List.unmodifiable(tools),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    if (maxCompletionTokens != null && maxCompletionTokens! <= 0) {
      throw ArgumentError.value(maxCompletionTokens, 'maxCompletionTokens', 'must be positive');
    }
    if (n != null && n! <= 0) throw ArgumentError.value(n, 'n', 'must be positive');
    _rejectCollisions(this.extraBody, _typedRequestFields);
  }

  /// Provider-local model ID.
  final String model;

  /// Ordered native messages.
  final List<OpenAIChatMessage> messages;

  /// Maximum generated tokens.
  final int? maxCompletionTokens;

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus-sampling threshold.
  final double? topP;

  /// Number of choices requested.
  final int? n;

  /// Native reasoning effort.
  final String? reasoningEffort;

  /// Native service tier.
  final String? serviceTier;

  /// Structured-output configuration, or null when explicitly cleared.
  JsonObject? get responseFormat => _responseFormat;

  final JsonObject? _responseFormat;
  final bool _hasResponseFormat;

  /// Native function declarations.
  final List<OpenAIChatFunctionTool>? tools;

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
    'reasoning_effort': ?reasoningEffort,
    'service_tier': ?serviceTier,
    if (_hasResponseFormat) 'response_format': _responseFormat?.toDart(),
    if (tools case final value?) 'tools': value.map((tool) => tool.toDart()).toList(),
    if (toolChoice case final value?) 'tool_choice': value.toDart(),
    'stream': stream,
  });
}

/// One typed native Chat Completions response.
final class OpenAIChatCompletion {
  /// Decodes a native completion.
  factory OpenAIChatCompletion.fromJson(JsonObject raw) =>
      OpenAIChatCompletion._(OpenAiCompatibleChatResponse.fromJson(raw));

  /// Wraps the shared strict wire representation without decoding twice.
  factory OpenAIChatCompletion.fromCompatible(OpenAiCompatibleChatResponse response) =>
      OpenAIChatCompletion._(response);

  const OpenAIChatCompletion._(this.compatible);

  /// Shared strict wire representation used by the transport codec.
  final OpenAiCompatibleChatResponse compatible;

  /// Completion ID.
  String get id => compatible.id;

  /// Actual provider model ID.
  String get model => compatible.model;

  /// Indexed native choices.
  List<OpenAIChatChoice> get choices => compatible.choices;

  /// Token usage when returned.
  Usage? get usage => compatible.usage;

  /// Complete native object.
  JsonObject get raw => compatible.raw;

  /// Fields outside the typed snapshot.
  JsonObject get extensions => compatible.extensions;
}

/// One indexed native completion choice.
typedef OpenAIChatChoice = OpenAiCompatibleChoice;

/// One typed native chat stream event.
typedef OpenAIChatEvent = OpenAiCompatibleStreamEvent;

/// One typed native chat stream chunk.
typedef OpenAIChatChunk = OpenAiCompatibleChunk;

/// An unrecognized native stream object retained without loss.
typedef OpenAIUnknownChatEvent = OpenAiCompatibleUnknownEvent;

/// The terminal `[DONE]` event, emitted after response-body cleanup.
typedef OpenAIChatDone = OpenAiCompatibleDone;

const _omitted = Object();

const _typedRequestFields = {
  'model',
  'messages',
  'max_completion_tokens',
  'temperature',
  'top_p',
  'n',
  'reasoning_effort',
  'service_tier',
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

import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';

/// A native Baseten Chat Completions role.
enum BasetenChatRole {
  /// System-level instructions.
  system,

  /// End-user input.
  user,

  /// Prior assistant output.
  assistant,

  /// A caller-provided tool result.
  tool,
}

/// One native Baseten Chat Completions message.
final class BasetenChatMessage {
  /// Creates a typed native message.
  BasetenChatMessage({
    required this.role,
    required this.content,
    this.name,
    this.toolCallId,
    JsonObject? extraBody,
  }) : extraBody = extraBody ?? JsonObject({}) {
    _rejectCollisions(this.extraBody, {
      'role',
      'content',
      'name',
      'tool_call_id',
    });
  }

  /// Creates a user text message.
  BasetenChatMessage.userText(String text)
    : this(
        role: BasetenChatRole.user,
        content: JsonString(_nonEmpty(text, 'text')),
      );

  /// Native role.
  final BasetenChatRole role;

  /// Native string, content-part array, or explicit null.
  final JsonValue content;

  /// Optional participant name.
  final String? name;

  /// Tool call ID for a tool-result message.
  final String? toolCallId;

  /// Forward-compatible message fields.
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

/// A typed native request for `POST /chat/completions`.
final class BasetenChatRequest {
  /// Creates a native compatible-chat request.
  BasetenChatRequest({
    required String model,
    required Iterable<BasetenChatMessage> messages,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.repetitionPenalty,
    this.responseFormat,
    Iterable<JsonObject>? tools,
    this.toolChoice,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       messages = List.unmodifiable(messages),
       tools = tools == null ? null : List.unmodifiable(tools),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    if (maxTokens != null && maxTokens! <= 0) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
    if (topK != null && topK! <= 0) {
      throw ArgumentError.value(topK, 'topK', 'must be positive');
    }
    _rejectCollisions(this.extraBody, _requestFields);
  }

  /// Served model name or catalog model slug.
  final String model;

  /// Ordered native messages.
  final List<BasetenChatMessage> messages;

  /// Maximum generated tokens.
  final int? maxTokens;

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus-sampling threshold.
  final double? topP;

  /// Top-k sampling limit.
  final int? topK;

  /// Repetition penalty.
  final double? repetitionPenalty;

  /// Compatible structured-output configuration.
  final JsonObject? responseFormat;

  /// Native tool declarations.
  final List<JsonObject>? tools;

  /// Native tool selection.
  final JsonValue? toolChoice;

  /// Forward-compatible fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Encodes this request for ordinary or streaming transport.
  JsonObject toJson({required bool stream}) => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'messages': messages.map((message) => message.toDart()).toList(),
    'max_tokens': ?maxTokens,
    'temperature': ?temperature,
    'top_p': ?topP,
    'top_k': ?topK,
    'repetition_penalty': ?repetitionPenalty,
    if (responseFormat case final value?) 'response_format': value.toDart(),
    if (tools case final value?) 'tools': value.map((tool) => tool.toDart()).toList(),
    if (toolChoice case final value?) 'tool_choice': value.toDart(),
    'stream': stream,
  });
}

/// One typed native Baseten Chat Completions response.
typedef BasetenChatCompletion = OpenAiCompatibleChatResponse;

/// One indexed native completion choice.
typedef BasetenChatChoice = OpenAiCompatibleChoice;

/// One typed native chat stream event.
typedef BasetenChatEvent = OpenAiCompatibleStreamEvent;

/// One typed native chat stream chunk.
typedef BasetenChatChunk = OpenAiCompatibleChunk;

/// An unrecognized native stream object retained without loss.
typedef BasetenUnknownChatEvent = OpenAiCompatibleUnknownEvent;

/// The terminal `[DONE]` event, emitted after response-body cleanup.
typedef BasetenChatDone = OpenAiCompatibleDone;

const _requestFields = {
  'model',
  'messages',
  'max_tokens',
  'temperature',
  'top_p',
  'top_k',
  'repetition_penalty',
  'response_format',
  'tools',
  'tool_choice',
  'stream',
};

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

void _rejectCollisions(JsonObject extraBody, Set<String> fields) {
  final collision = extraBody.toDart().keys.where(fields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(
      extraBody,
      'extraBody',
      'field "$collision" collides with a typed field',
    );
  }
}

import 'package:artificer_core/json.dart';

/// A native beta Messages conversation role.
enum BasetenMessageRole {
  /// Caller-authored input.
  user,

  /// Model-authored output.
  assistant,
}

/// One typed native beta Messages input turn.
final class BasetenInputMessage {
  /// Creates an input turn with ordered native content blocks.
  BasetenInputMessage({
    required this.role,
    required Iterable<JsonObject> content,
  }) : content = List.unmodifiable(content) {
    if (this.content.isEmpty) {
      throw ArgumentError.value(content, 'content', 'must not be empty');
    }
  }

  /// Creates a user turn containing one text block.
  BasetenInputMessage.userText(String text)
    : this(
        role: BasetenMessageRole.user,
        content: [
          JsonObject({'type': 'text', 'text': _nonEmpty(text, 'text')}),
        ],
      );

  /// Native role.
  final BasetenMessageRole role;

  /// Ordered native content blocks, including beta tool variants.
  final List<JsonObject> content;

  /// Encodes this turn.
  Map<String, Object?> toDart() => {
    'role': role.name,
    'content': content.map((block) => block.toDart()).toList(),
  };
}

/// A typed native request for Baseten's beta `POST /messages` endpoint.
final class BasetenMessageRequest {
  /// Creates a beta Messages request.
  BasetenMessageRequest({
    required String model,
    required this.maxTokens,
    required Iterable<BasetenInputMessage> messages,
    this.system,
    this.temperature,
    this.topP,
    Iterable<String>? stopSequences,
    Iterable<JsonObject>? tools,
    this.toolChoice,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       messages = List.unmodifiable(messages),
       stopSequences = stopSequences == null ? null : List.unmodifiable(stopSequences),
       tools = tools == null ? null : List.unmodifiable(tools),
       extraBody = extraBody ?? JsonObject({}) {
    if (maxTokens <= 0) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
    if (this.messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    if (temperature != null && (!temperature!.isFinite || temperature! < 0 || temperature! > 1)) {
      throw ArgumentError.value(temperature, 'temperature', 'must be between 0 and 1');
    }
    if (topP != null && (!topP!.isFinite || topP! <= 0 || topP! > 1)) {
      throw ArgumentError.value(topP, 'topP', 'must be greater than 0 and at most 1');
    }
    _rejectCollisions(this.extraBody, _requestFields);
  }

  /// Catalog model slug.
  final String model;

  /// Maximum generated tokens.
  final int maxTokens;

  /// Ordered user and assistant turns.
  final List<BasetenInputMessage> messages;

  /// Optional system prompt in the beta native schema.
  final JsonValue? system;

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus-sampling threshold.
  final double? topP;

  /// Native stop sequences.
  final List<String>? stopSequences;

  /// Native application or provider tool definitions.
  final List<JsonObject>? tools;

  /// Native tool-selection configuration.
  final JsonValue? toolChoice;

  /// Forward-compatible beta fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Encodes this request for ordinary or streaming transport.
  JsonObject toJson({required bool stream}) => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'max_tokens': maxTokens,
    'messages': messages.map((message) => message.toDart()).toList(),
    if (system case final value?) 'system': value.toDart(),
    'temperature': ?temperature,
    'top_p': ?topP,
    'stop_sequences': ?stopSequences,
    if (tools case final value?) 'tools': value.map((tool) => tool.toDart()).toList(),
    if (toolChoice case final value?) 'tool_choice': value.toDart(),
    'stream': stream,
  });
}

/// One typed native response from Baseten's beta Messages endpoint.
final class BasetenMessageResponse {
  /// Decodes a beta Messages response while retaining unknown fields.
  factory BasetenMessageResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    _literal(value, 'type', 'message');
    final content = _list(value, 'content').map(
      (block) => _object(block, 'content item'),
    );
    return BasetenMessageResponse._(
      id: _string(value, 'id'),
      model: _string(value, 'model'),
      role: _responseRole(value['role']),
      content: content,
      stopReason: _stopReason(value['stop_reason']),
      usage: _object(value['usage'], 'usage'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'id',
          'type',
          'model',
          'role',
          'content',
          'stop_reason',
          'stop_sequence',
          'usage',
        }),
      ),
    );
  }

  BasetenMessageResponse._({
    required this.id,
    required this.model,
    required this.role,
    required Iterable<JsonObject> content,
    required this.stopReason,
    required this.usage,
    required this.raw,
    required this.extensions,
  }) : content = List.unmodifiable(content);

  /// Message ID.
  final String id;

  /// Actual catalog model slug.
  final String model;

  /// Native response role.
  final BasetenMessageRole role;

  /// Ordered content and tool blocks from the pinned beta schema.
  final List<JsonObject> content;

  /// Native terminal reason.
  final String stopReason;

  /// Native usage fields.
  final JsonObject usage;

  /// Complete immutable native response.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

const _requestFields = {
  'model',
  'max_tokens',
  'messages',
  'system',
  'temperature',
  'top_p',
  'stop_sequences',
  'tools',
  'tool_choice',
  'stream',
};

BasetenMessageRole _responseRole(Object? value) => switch (value) {
  'assistant' => BasetenMessageRole.assistant,
  _ => throw const FormatException('Messages response role must be assistant.'),
};

String _stopReason(Object? value) {
  if (value is! String || !_stopReasons.contains(value)) {
    throw FormatException('Unknown Messages stop_reason: $value');
  }
  return value;
}

void _literal(Map<String, Object?> value, String key, String expected) {
  if (value[key] != expected) {
    throw FormatException('$key must be "$expected".');
  }
}

void _rejectCollisions(JsonObject extraBody, Set<String> fields) {
  final collision = extraBody.toDart().keys.where(fields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(extraBody, 'extraBody', 'field "$collision" is typed');
  }
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) throw FormatException('$key must be a string.');
  return field;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

JsonObject _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object.');
  }
  return JsonObject(value);
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

const _stopReasons = {'end_turn', 'max_tokens', 'stop_sequence', 'tool_use'};

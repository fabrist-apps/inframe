import 'package:artificer_core/json.dart';

/// A typed Responses input item.
sealed class OpenAIResponseInputItem {
  const OpenAIResponseInputItem();

  /// Encodes the item for the Responses API.
  Map<String, Object?> toDart();
}

/// A Responses input message.
final class OpenAIResponseInputMessage extends OpenAIResponseInputItem {
  /// Creates an input message.
  OpenAIResponseInputMessage({
    required this.role,
    required Iterable<OpenAIResponseInputPart> content,
  }) : content = List.unmodifiable(content) {
    if (this.content.isEmpty) throw ArgumentError.value(content, 'content', 'must not be empty');
  }

  /// Creates a user message containing one text part.
  OpenAIResponseInputMessage.userText(String text)
    : this(role: OpenAIResponseInputRole.user, content: [OpenAITextInputPart(text)]);

  /// The native message role.
  final OpenAIResponseInputRole role;

  /// The ordered content.
  final List<OpenAIResponseInputPart> content;

  @override
  Map<String, Object?> toDart() => {
    'role': role.name,
    'content': content.map((part) => part.toDart()).toList(),
  };
}

/// A native Responses input-message role.
enum OpenAIResponseInputRole {
  /// A caller message.
  user,

  /// A prior model message.
  assistant,

  /// Developer instructions.
  developer,

  /// System instructions.
  system,
}

/// One typed native input part.
sealed class OpenAIResponseInputPart {
  const OpenAIResponseInputPart();

  /// Encodes the part.
  Map<String, Object?> toDart();
}

/// A native text input part.
final class OpenAITextInputPart extends OpenAIResponseInputPart {
  /// Creates a text part.
  OpenAITextInputPart(this.text) {
    if (text.isEmpty) throw ArgumentError.value(text, 'text', 'must not be empty');
  }

  /// The input text.
  final String text;

  @override
  Map<String, Object?> toDart() => {'type': 'input_text', 'text': text};
}

/// A typed native request for `POST /responses`.
final class OpenAIResponseRequest {
  /// Creates a Responses request.
  OpenAIResponseRequest({
    required String model,
    required Iterable<OpenAIResponseInputItem> input,
    this.instructions,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.store,
    this.stream,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       input = List.unmodifiable(input),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.input.isEmpty) throw ArgumentError.value(input, 'input', 'must not be empty');
    if (maxOutputTokens != null && maxOutputTokens! <= 0) {
      throw ArgumentError.value(maxOutputTokens, 'maxOutputTokens', 'must be positive');
    }
    final collision = this.extraBody.toDart().keys.where(_typedResponseFields.contains).firstOrNull;
    if (collision != null) {
      throw ArgumentError.value(collision, 'extraBody', 'collides with a typed field');
    }
  }

  /// The provider-local model ID.
  final String model;

  /// The ordered explicit input history.
  final List<OpenAIResponseInputItem> input;

  /// Separate developer instructions.
  final String? instructions;

  /// The maximum output-token count.
  final int? maxOutputTokens;

  /// Sampling temperature when supplied.
  final double? temperature;

  /// Nucleus-sampling threshold when supplied.
  final double? topP;

  /// Whether the provider stores the response.
  final bool? store;

  /// Whether to stream the response.
  final bool? stream;

  /// Forward-compatible fields outside this pinned typed snapshot.
  final JsonObject extraBody;

  /// Encodes this request and rejects collisions with typed fields.
  JsonObject toJson() {
    final extras = extraBody.toDart();
    return JsonObject({
      ...extras,
      'model': model,
      'input': input.map((item) => item.toDart()).toList(),
      'instructions': ?instructions,
      'max_output_tokens': ?maxOutputTokens,
      'temperature': ?temperature,
      'top_p': ?topP,
      'store': ?store,
      'stream': ?stream,
    });
  }
}

/// Native response state.
enum OpenAIResponseStatus {
  /// Completed successfully.
  completed,

  /// Failed at the provider.
  failed,

  /// Still running.
  inProgress,

  /// Cancelled explicitly.
  cancelled,

  /// Queued for background execution.
  queued,

  /// Ended with partial output.
  incomplete,

  /// A newer native status.
  unknown,
}

/// A typed native Responses object with full raw and extension data.
final class OpenAIResponse {
  /// Decodes a Responses object.
  factory OpenAIResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIResponse._(
      id: _string(value, 'id'),
      model: _string(value, 'model'),
      status: _status(_string(value, 'status')),
      output: _list(value, 'output').map(OpenAIResponseOutputItem.fromDart),
      usage: value['usage'] is Map<String, Object?>
          ? OpenAIResponseUsage.fromDart(value['usage'])
          : null,
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'model', 'status', 'output', 'usage'})),
    );
  }

  OpenAIResponse._({
    required this.id,
    required this.model,
    required this.status,
    required Iterable<OpenAIResponseOutputItem> output,
    required this.raw,
    required this.extensions,
    this.usage,
  }) : output = List.unmodifiable(output);

  /// Response ID.
  final String id;

  /// Actual model ID.
  final String model;

  /// Native lifecycle state.
  final OpenAIResponseStatus status;

  /// Ordered native output items.
  final List<OpenAIResponseOutputItem> output;

  /// Token accounting when returned.
  final OpenAIResponseUsage? usage;

  /// Complete native response.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One typed output item.
sealed class OpenAIResponseOutputItem {
  OpenAIResponseOutputItem({
    required this.type,
    required this.raw,
    required this.extensions,
    this.id,
  });

  /// Decodes a native output item.
  factory OpenAIResponseOutputItem.fromDart(Object? input) {
    final value = _object(input, 'output item');
    final raw = JsonObject(value);
    final type = _string(value, 'type');
    return switch (type) {
      'message' => OpenAIResponseMessageItem._(
        id: value['id'] as String?,
        status: value['status'] as String?,
        content: _list(value, 'content').map(OpenAIResponseOutputContent.fromDart),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'id', 'status', 'role', 'content'})),
      ),
      _ => OpenAIUnknownOutputItem._(
        type: type,
        id: value['id'] as String?,
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'id'})),
      ),
    };
  }

  /// Native item type.
  final String type;

  /// Native item ID.
  final String? id;

  /// Complete native item.
  final JsonObject raw;

  /// Unknown fields on the item.
  final JsonObject extensions;
}

/// A native assistant message item.
final class OpenAIResponseMessageItem extends OpenAIResponseOutputItem {
  OpenAIResponseMessageItem._({
    required super.id,
    required this.status,
    required Iterable<OpenAIResponseOutputContent> content,
    required super.raw,
    required super.extensions,
  }) : content = List.unmodifiable(content),
       super(type: 'message');

  /// Native completion state.
  final String? status;

  /// Ordered native output content.
  final List<OpenAIResponseOutputContent> content;
}

/// An unknown output item retained without loss.
final class OpenAIUnknownOutputItem extends OpenAIResponseOutputItem {
  OpenAIUnknownOutputItem._({
    required super.type,
    required super.id,
    required super.raw,
    required super.extensions,
  });
}

/// One typed message content part.
sealed class OpenAIResponseOutputContent {
  OpenAIResponseOutputContent({required this.type, required this.raw, required this.extensions});

  /// Decodes one native content part.
  factory OpenAIResponseOutputContent.fromDart(Object? input) {
    final value = _object(input, 'output content');
    final raw = JsonObject(value);
    final type = _string(value, 'type');
    return switch (type) {
      'output_text' => OpenAIOutputTextContent._(
        text: _string(value, 'text'),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'text'})),
      ),
      'refusal' => OpenAIRefusalContent._(
        refusal: _string(value, 'refusal'),
        raw: raw,
        extensions: JsonObject(_without(value, {'type', 'refusal'})),
      ),
      _ => OpenAIUnknownOutputContent._(
        type: type,
        raw: raw,
        extensions: JsonObject(_without(value, {'type'})),
      ),
    };
  }

  /// Native part type.
  final String type;

  /// Complete native part.
  final JsonObject raw;

  /// Unknown fields on the part.
  final JsonObject extensions;
}

/// Native visible text.
final class OpenAIOutputTextContent extends OpenAIResponseOutputContent {
  OpenAIOutputTextContent._({
    required this.text,
    required super.raw,
    required super.extensions,
  }) : super(type: 'output_text');

  /// Visible text.
  final String text;
}

/// Native refusal content.
final class OpenAIRefusalContent extends OpenAIResponseOutputContent {
  OpenAIRefusalContent._({
    required this.refusal,
    required super.raw,
    required super.extensions,
  }) : super(type: 'refusal');

  /// Refusal text.
  final String refusal;
}

/// Unknown content retained without loss.
final class OpenAIUnknownOutputContent extends OpenAIResponseOutputContent {
  OpenAIUnknownOutputContent._({
    required super.type,
    required super.raw,
    required super.extensions,
  });
}

/// Native Responses token accounting.
final class OpenAIResponseUsage {
  /// Decodes usage.
  factory OpenAIResponseUsage.fromDart(Object? input) {
    final value = _object(input, 'usage');
    return OpenAIResponseUsage._(
      inputTokens: _optionalInt(value, 'input_tokens'),
      outputTokens: _optionalInt(value, 'output_tokens'),
      totalTokens: _optionalInt(value, 'total_tokens'),
      raw: JsonObject(value),
    );
  }

  OpenAIResponseUsage._({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.raw,
  });

  /// Input tokens.
  final int? inputTokens;

  /// Output tokens.
  final int? outputTokens;

  /// Total tokens.
  final int? totalTokens;

  /// Complete usage object.
  final JsonObject raw;
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return value;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

OpenAIResponseStatus _status(String status) => switch (status) {
  'completed' => OpenAIResponseStatus.completed,
  'failed' => OpenAIResponseStatus.failed,
  'in_progress' => OpenAIResponseStatus.inProgress,
  'cancelled' => OpenAIResponseStatus.cancelled,
  'queued' => OpenAIResponseStatus.queued,
  'incomplete' => OpenAIResponseStatus.incomplete,
  _ => OpenAIResponseStatus.unknown,
};

const _typedResponseFields = {
  'model',
  'input',
  'instructions',
  'max_output_tokens',
  'temperature',
  'top_p',
  'store',
  'stream',
};

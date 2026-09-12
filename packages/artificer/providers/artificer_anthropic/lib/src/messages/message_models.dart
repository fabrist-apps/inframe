import 'dart:convert';

import 'package:artificer_core/json.dart';

/// Prompt-cache lifetime supported by Anthropic.
enum AnthropicCacheTtl {
  /// Five minutes.
  fiveMinutes('5m'),

  /// One hour.
  oneHour('1h');

  const AnthropicCacheTtl(this.wireValue);

  /// Native value.
  final String wireValue;
}

/// A cache breakpoint placed at a supported native location.
final class AnthropicCacheControl {
  /// Creates an ephemeral cache breakpoint.
  const AnthropicCacheControl({this.ttl = AnthropicCacheTtl.fiveMinutes});

  /// Breakpoint lifetime.
  final AnthropicCacheTtl ttl;

  /// Encodes this breakpoint.
  Map<String, Object?> toDart() => {'type': 'ephemeral', 'ttl': ttl.wireValue};
}

/// One typed Messages input turn.
final class AnthropicInputMessage {
  /// Creates an input message with ordered content blocks.
  AnthropicInputMessage({
    required this.role,
    required Iterable<AnthropicContentBlock> content,
  }) : content = List.unmodifiable(content) {
    if (this.content.isEmpty && role == AnthropicMessageRole.user) {
      throw ArgumentError.value(content, 'content', 'must not be empty');
    }
  }

  /// Creates a user turn with one text block.
  AnthropicInputMessage.userText(String text)
    : this(role: AnthropicMessageRole.user, content: [AnthropicTextBlock(text)]);

  /// Native conversation role.
  final AnthropicMessageRole role;

  /// Ordered native content blocks.
  final List<AnthropicContentBlock> content;

  /// Encodes this turn for Messages.
  Map<String, Object?> toDart() => {
    'role': role.name,
    'content': content.map((block) => block.toDart()).toList(),
  };
}

/// A native Messages conversation role.
enum AnthropicMessageRole {
  /// A caller-authored turn.
  user,

  /// A model-authored turn.
  assistant,
}

/// A typed native Messages content block.
sealed class AnthropicContentBlock {
  const AnthropicContentBlock();

  /// Native discriminator.
  String get type;

  /// Complete immutable native object.
  JsonObject get raw;

  /// Encodes the block for Messages or exact replay.
  Map<String, Object?> toDart() => raw.toDart();

  /// Decodes a native response or replay block.
  static AnthropicContentBlock fromJson(JsonObject raw) {
    final value = raw.toDart();
    return switch (_string(value, 'type')) {
      'text' => AnthropicTextBlock._(
        text: _string(value, 'text'),
        citations: _nullableObjects(value, 'citations'),
        raw: raw,
      ),
      'image' => AnthropicImageBlock._(raw),
      'document' => AnthropicDocumentBlock._(raw),
      'tool_use' => AnthropicToolUseBlock._(
        id: _string(value, 'id'),
        name: _string(value, 'name'),
        input: JsonValue.fromDart(value['input']),
        raw: raw,
      ),
      'tool_result' => AnthropicToolResultBlock._(raw),
      final type => AnthropicUnknownContentBlock._(type: type, raw: raw),
    };
  }
}

/// Native text content with optional citation records.
final class AnthropicTextBlock extends AnthropicContentBlock {
  /// Creates text input.
  AnthropicTextBlock(
    String text, {
    Iterable<JsonObject>? citations,
    AnthropicCacheControl? cacheControl,
  }) : this._(
         text: _nonEmpty(text, 'text'),
         citations: citations == null ? null : List.unmodifiable(citations),
         raw: JsonObject({
           'type': 'text',
           'text': text,
           if (citations != null) 'citations': citations.map((item) => item.toDart()).toList(),
           if (cacheControl != null) 'cache_control': cacheControl.toDart(),
         }),
       );

  AnthropicTextBlock._({required this.text, required this.citations, required this.raw});

  /// Text content.
  final String text;

  /// Ordered native citations, when present.
  final List<JsonObject>? citations;

  @override
  String get type => 'text';

  @override
  final JsonObject raw;
}

/// Native image input from copied base64 bytes, URL, or Anthropic file ID.
final class AnthropicImageBlock extends AnthropicContentBlock {
  AnthropicImageBlock._(this.raw);

  /// Creates an inline image.
  AnthropicImageBlock.bytes(
    Iterable<int> bytes, {
    required String mimeType,
    AnthropicCacheControl? cacheControl,
  }) : raw = JsonObject({
         'type': 'image',
         'source': {
           'type': 'base64',
           'media_type': mimeType,
           'data': base64Encode(bytes.toList(growable: false)),
         },
         if (cacheControl != null) 'cache_control': cacheControl.toDart(),
       });

  /// Creates a native URL image.
  AnthropicImageBlock.url(Uri url, {AnthropicCacheControl? cacheControl})
    : raw = JsonObject({
        'type': 'image',
        'source': {'type': 'url', 'url': url.toString()},
        if (cacheControl != null) 'cache_control': cacheControl.toDart(),
      });

  /// Creates an image reference to an existing Anthropic file.
  AnthropicImageBlock.file(String fileId, {AnthropicCacheControl? cacheControl})
    : raw = JsonObject({
        'type': 'image',
        'source': {'type': 'file', 'file_id': _nonEmpty(fileId, 'fileId')},
        if (cacheControl != null) 'cache_control': cacheControl.toDart(),
      });

  @override
  String get type => 'image';

  @override
  final JsonObject raw;
}

/// Native document input from copied content, URL, or Anthropic file ID.
final class AnthropicDocumentBlock extends AnthropicContentBlock {
  AnthropicDocumentBlock._(this.raw);

  /// Creates an inline PDF document.
  AnthropicDocumentBlock.pdfBytes(
    Iterable<int> bytes, {
    AnthropicCacheControl? cacheControl,
  }) : raw = JsonObject({
         'type': 'document',
         'source': {
           'type': 'base64',
           'media_type': 'application/pdf',
           'data': base64Encode(bytes.toList(growable: false)),
         },
         if (cacheControl != null) 'cache_control': cacheControl.toDart(),
       });

  /// Creates an inline plain-text document.
  AnthropicDocumentBlock.text(String text, {AnthropicCacheControl? cacheControl})
    : raw = JsonObject({
        'type': 'document',
        'source': {'type': 'text', 'media_type': 'text/plain', 'data': text},
        if (cacheControl != null) 'cache_control': cacheControl.toDart(),
      });

  /// Creates a URL PDF document.
  AnthropicDocumentBlock.url(Uri url, {AnthropicCacheControl? cacheControl})
    : raw = JsonObject({
        'type': 'document',
        'source': {'type': 'url', 'url': url.toString()},
        if (cacheControl != null) 'cache_control': cacheControl.toDart(),
      });

  /// Creates a document reference to an existing Anthropic file.
  AnthropicDocumentBlock.file(String fileId, {AnthropicCacheControl? cacheControl})
    : raw = JsonObject({
        'type': 'document',
        'source': {'type': 'file', 'file_id': _nonEmpty(fileId, 'fileId')},
        if (cacheControl != null) 'cache_control': cacheControl.toDart(),
      });

  @override
  String get type => 'document';

  @override
  final JsonObject raw;
}

/// A caller-owned native tool call returned by the model.
final class AnthropicToolUseBlock extends AnthropicContentBlock {
  /// Creates a tool-use replay block.
  AnthropicToolUseBlock({
    required String id,
    required String name,
    required JsonValue input,
  }) : id = _nonEmpty(id, 'id'),
       name = _nonEmpty(name, 'name'),
       input = input,
       raw = JsonObject({
         'type': 'tool_use',
         'id': id,
         'name': name,
         'input': input.toDart(),
       });

  AnthropicToolUseBlock._({
    required this.id,
    required this.name,
    required this.input,
    required this.raw,
  });

  /// Tool-use ID.
  final String id;

  /// Tool name.
  final String name;

  /// Complete tool input.
  final JsonValue input;

  @override
  String get type => 'tool_use';

  @override
  final JsonObject raw;
}

/// A caller-supplied tool result replay block.
final class AnthropicToolResultBlock extends AnthropicContentBlock {
  /// Creates a result with native string or ordered content.
  AnthropicToolResultBlock({
    required String toolUseId,
    required Object content,
    bool isError = false,
  }) : raw = JsonObject({
         'type': 'tool_result',
         'tool_use_id': _nonEmpty(toolUseId, 'toolUseId'),
         'content': content,
         if (isError) 'is_error': true,
       });

  AnthropicToolResultBlock._(this.raw);

  @override
  String get type => 'tool_result';

  @override
  final JsonObject raw;
}

/// A typed definition accepted by the Messages tools array.
abstract interface class AnthropicToolDefinition {
  /// Tool name used for collision checks and selection.
  String get name;

  /// Encodes the complete native definition.
  JsonObject toJson();
}

/// An application-defined JSON Schema tool.
final class AnthropicClientTool implements AnthropicToolDefinition {
  /// Creates a caller-executed tool definition.
  AnthropicClientTool({
    required String name,
    required this.inputSchema,
    this.description,
  }) : name = _nonEmpty(name, 'name');

  @override
  final String name;

  /// Optional description.
  final String? description;

  /// Tool input JSON Schema.
  final JsonObject inputSchema;

  @override
  JsonObject toJson() => JsonObject({
    'name': name,
    'description': ?description,
    'input_schema': inputSchema.toDart(),
  });
}

/// Native Messages tool-selection policy.
sealed class AnthropicToolChoice {
  const AnthropicToolChoice();

  /// Encodes this choice.
  JsonObject toJson();
}

/// Let Claude decide whether to call a tool.
final class AnthropicAutoToolChoice extends AnthropicToolChoice {
  /// Creates automatic selection.
  const AnthropicAutoToolChoice({this.disableParallelToolUse});

  /// Whether parallel tool use is disabled.
  final bool? disableParallelToolUse;

  @override
  JsonObject toJson() => JsonObject({
    'type': 'auto',
    'disable_parallel_tool_use': ?disableParallelToolUse,
  });
}

/// Require any available tool.
final class AnthropicAnyToolChoice extends AnthropicToolChoice {
  /// Creates required tool selection.
  const AnthropicAnyToolChoice({this.disableParallelToolUse});

  /// Whether parallel tool use is disabled.
  final bool? disableParallelToolUse;

  @override
  JsonObject toJson() => JsonObject({
    'type': 'any',
    'disable_parallel_tool_use': ?disableParallelToolUse,
  });
}

/// Require one named tool.
final class AnthropicNamedToolChoice extends AnthropicToolChoice {
  /// Creates named selection.
  AnthropicNamedToolChoice(String name, {this.disableParallelToolUse})
    : name = _nonEmpty(name, 'name');

  /// Selected tool name.
  final String name;

  /// Whether parallel tool use is disabled.
  final bool? disableParallelToolUse;

  @override
  JsonObject toJson() => JsonObject({
    'type': 'tool',
    'name': name,
    'disable_parallel_tool_use': ?disableParallelToolUse,
  });
}

/// Disable tools.
final class AnthropicNoToolChoice extends AnthropicToolChoice {
  /// Creates disabled tool selection.
  const AnthropicNoToolChoice();

  @override
  JsonObject toJson() => JsonObject({'type': 'none'});
}

/// Native structured-output configuration.
final class AnthropicOutputConfig {
  /// Creates native output configuration.
  const AnthropicOutputConfig({this.effort, this.schema});

  /// Creates JSON Schema output configuration.
  const AnthropicOutputConfig.jsonSchema(this.schema) : effort = null;

  /// Native effort level.
  final String? effort;

  /// Output JSON Schema, when selected.
  final JsonObject? schema;

  /// Encodes this configuration.
  JsonObject toJson() => JsonObject({
    'effort': ?effort,
    if (schema case final value?) 'format': {'type': 'json_schema', 'schema': value.toDart()},
  });
}

/// A content type outside this pinned snapshot, retained without loss.
final class AnthropicUnknownContentBlock extends AnthropicContentBlock {
  AnthropicUnknownContentBlock._({required this.type, required this.raw});

  @override
  final String type;

  @override
  final JsonObject raw;
}

/// A complete native Messages request.
final class AnthropicMessageRequest {
  /// Creates a request with the native required fields.
  AnthropicMessageRequest({
    required String model,
    required this.maxTokens,
    required Iterable<AnthropicInputMessage> messages,
    Iterable<AnthropicTextBlock> system = const [],
    this.temperature,
    this.topP,
    Iterable<String> stopSequences = const [],
    Iterable<AnthropicToolDefinition> tools = const [],
    this.toolChoice,
    this.outputConfig,
    this.cacheControl,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       messages = List.unmodifiable(messages),
       system = List.unmodifiable(system),
       stopSequences = List.unmodifiable(stopSequences),
       tools = List.unmodifiable(tools),
       extraBody = extraBody ?? JsonObject({}) {
    if (maxTokens < 0) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must not be negative');
    }
    if (this.messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    if (this.stopSequences.any((value) => value.isEmpty)) {
      throw ArgumentError.value(stopSequences, 'stopSequences', 'must not contain empty values');
    }
    final names = <String>{};
    for (final tool in this.tools) {
      if (!names.add(tool.name)) {
        throw ArgumentError.value(tool.name, 'tools', 'contains a duplicate name');
      }
    }
  }

  /// Provider-local model identifier.
  final String model;

  /// Maximum output tokens.
  final int maxTokens;

  /// Ordered conversation turns.
  final List<AnthropicInputMessage> messages;

  /// Top-level system blocks.
  final List<AnthropicTextBlock> system;

  /// Optional sampling temperature.
  final double? temperature;

  /// Optional nucleus sampling value.
  final double? topP;

  /// Optional stop sequences.
  final List<String> stopSequences;

  /// Native tool definitions.
  final List<AnthropicToolDefinition> tools;

  /// Native tool-selection policy.
  final AnthropicToolChoice? toolChoice;

  /// Native output settings.
  final AnthropicOutputConfig? outputConfig;

  /// Top-level prompt-cache breakpoint.
  final AnthropicCacheControl? cacheControl;

  /// Forward-compatible fields.
  final JsonObject extraBody;

  /// Encodes this request, rejecting collisions with typed fields.
  JsonObject toJson({required bool stream}) {
    const typed = {
      'model',
      'max_tokens',
      'messages',
      'system',
      'temperature',
      'top_p',
      'stop_sequences',
      'tools',
      'tool_choice',
      'output_config',
      'cache_control',
      'stream',
    };
    final collision = extraBody.toDart().keys.where(typed.contains).firstOrNull;
    if (collision != null) {
      throw ArgumentError.value(collision, 'extraBody', 'collides with a typed field');
    }
    return JsonObject({
      ...extraBody.toDart(),
      'model': model,
      'max_tokens': maxTokens,
      'messages': messages.map((message) => message.toDart()).toList(),
      if (system.isNotEmpty) 'system': system.map((block) => block.toDart()).toList(),
      'temperature': ?temperature,
      'top_p': ?topP,
      if (stopSequences.isNotEmpty) 'stop_sequences': stopSequences,
      if (tools.isNotEmpty) 'tools': tools.map((tool) => tool.toJson().toDart()).toList(),
      if (toolChoice case final value?) 'tool_choice': value.toJson().toDart(),
      if (outputConfig case final value?) 'output_config': value.toJson().toDart(),
      if (cacheControl case final value?) 'cache_control': value.toDart(),
      'stream': stream,
    });
  }
}

/// Native token usage.
final class AnthropicUsage {
  /// Creates decoded usage while retaining its full native object.
  const AnthropicUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.raw,
  });

  /// Decodes usage. Stream deltas may omit input tokens.
  factory AnthropicUsage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicUsage(
      inputTokens: _optionalInt(value, 'input_tokens'),
      outputTokens: _optionalInt(value, 'output_tokens'),
      raw: raw,
    );
  }

  /// Input tokens, when reported.
  final int? inputTokens;

  /// Output tokens, when reported.
  final int? outputTokens;

  /// Complete immutable usage object.
  final JsonObject raw;
}

/// A decoded native Anthropic Message.
final class AnthropicMessage {
  AnthropicMessage._({
    required this.id,
    required this.model,
    required this.content,
    required this.stopReason,
    required this.stopSequence,
    required this.usage,
    required this.stopDetails,
    required this.extensions,
    required this.raw,
  });

  /// Decodes one complete Message.
  factory AnthropicMessage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    if (_string(value, 'type') != 'message' || _string(value, 'role') != 'assistant') {
      throw const FormatException('Expected an assistant message object.');
    }
    return AnthropicMessage._(
      id: _string(value, 'id'),
      model: _string(value, 'model'),
      content: List.unmodifiable(
        _objects(value, 'content').map(AnthropicContentBlock.fromJson),
      ),
      stopReason: value['stop_reason'] as String?,
      stopSequence: value['stop_sequence'] as String?,
      usage: AnthropicUsage.fromJson(JsonObject.fromDart(value['usage'])),
      stopDetails: switch (value['stop_details']) {
        final Map<String, Object?> details => JsonObject(details),
        _ => null,
      },
      extensions: JsonObject(
        _without(value, {
          'id',
          'type',
          'role',
          'model',
          'content',
          'stop_reason',
          'stop_sequence',
          'usage',
          'stop_details',
        }),
      ),
      raw: raw,
    );
  }

  /// Message identifier.
  final String id;

  /// Actual model identifier.
  final String model;

  /// Ordered response content.
  final List<AnthropicContentBlock> content;

  /// Native stop reason.
  final String? stopReason;

  /// Matching native stop sequence.
  final String? stopSequence;

  /// Token usage.
  final AnthropicUsage usage;

  /// Structured refusal details, when supplied.
  final JsonObject? stopDetails;

  /// Fields outside this pinned typed shape.
  final JsonObject extensions;

  /// Complete immutable message.
  final JsonObject raw;
}

/// One typed native Messages stream event.
sealed class AnthropicMessageEvent {
  AnthropicMessageEvent({required this.type, required this.raw});

  /// Decodes a stream event.
  factory AnthropicMessageEvent.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    return switch (type) {
      'message_start' => AnthropicMessageStartEvent._(
        AnthropicMessage.fromJson(JsonObject.fromDart(value['message'])),
        raw,
      ),
      'content_block_start' => AnthropicContentBlockStartEvent._(
        index: _int(value, 'index'),
        contentBlock: AnthropicContentBlock.fromJson(
          JsonObject.fromDart(value['content_block']),
        ),
        raw: raw,
      ),
      'content_block_delta' => AnthropicContentBlockDeltaEvent._(
        index: _int(value, 'index'),
        delta: JsonObject.fromDart(value['delta']),
        raw: raw,
      ),
      'content_block_stop' => AnthropicContentBlockStopEvent._(_int(value, 'index'), raw),
      'message_delta' => AnthropicMessageDeltaEvent._(
        delta: JsonObject.fromDart(value['delta']),
        usage: AnthropicUsage.fromJson(JsonObject.fromDart(value['usage'])),
        raw: raw,
      ),
      'message_stop' => AnthropicMessageStopEvent._(raw),
      'ping' => AnthropicPingEvent._(raw),
      'error' => AnthropicErrorEvent._(JsonObject.fromDart(value['error']), raw),
      _ => AnthropicUnknownMessageEvent._(type, raw),
    };
  }

  /// Native discriminator.
  final String type;

  /// Complete immutable event.
  final JsonObject raw;
}

/// Initial message state.
final class AnthropicMessageStartEvent extends AnthropicMessageEvent {
  AnthropicMessageStartEvent._(this.message, JsonObject raw)
    : super(type: 'message_start', raw: raw);

  /// Initial message.
  final AnthropicMessage message;
}

/// Starts an indexed content block.
final class AnthropicContentBlockStartEvent extends AnthropicMessageEvent {
  AnthropicContentBlockStartEvent._({
    required this.index,
    required this.contentBlock,
    required super.raw,
  }) : super(type: 'content_block_start');

  /// Content index.
  final int index;

  /// Initial block state.
  final AnthropicContentBlock contentBlock;
}

/// Applies a delta to an indexed content block.
final class AnthropicContentBlockDeltaEvent extends AnthropicMessageEvent {
  AnthropicContentBlockDeltaEvent._({
    required this.index,
    required this.delta,
    required super.raw,
  }) : super(type: 'content_block_delta');

  /// Content index.
  final int index;

  /// Typed-by-discriminator immutable delta.
  final JsonObject delta;
}

/// Completes an indexed content block.
final class AnthropicContentBlockStopEvent extends AnthropicMessageEvent {
  AnthropicContentBlockStopEvent._(this.index, JsonObject raw)
    : super(type: 'content_block_stop', raw: raw);

  /// Content index.
  final int index;
}

/// Supplies stop details and cumulative usage.
final class AnthropicMessageDeltaEvent extends AnthropicMessageEvent {
  AnthropicMessageDeltaEvent._({
    required this.delta,
    required this.usage,
    required super.raw,
  }) : super(type: 'message_delta');

  /// Native message delta.
  final JsonObject delta;

  /// Latest cumulative usage.
  final AnthropicUsage usage;
}

/// Terminal message event.
final class AnthropicMessageStopEvent extends AnthropicMessageEvent {
  AnthropicMessageStopEvent._(JsonObject raw) : super(type: 'message_stop', raw: raw);
}

/// Keep-alive event.
final class AnthropicPingEvent extends AnthropicMessageEvent {
  AnthropicPingEvent._(JsonObject raw) : super(type: 'ping', raw: raw);
}

/// Error delivered within a successful HTTP stream.
final class AnthropicErrorEvent extends AnthropicMessageEvent {
  AnthropicErrorEvent._(this.error, JsonObject raw) : super(type: 'error', raw: raw);

  /// Native service error.
  final JsonObject error;
}

/// An event outside the pinned snapshot.
final class AnthropicUnknownMessageEvent extends AnthropicMessageEvent {
  AnthropicUnknownMessageEvent._(String type, JsonObject raw) : super(type: type, raw: raw);
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int _int(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int || field < 0) throw FormatException('$key must be a nonnegative integer.');
  return field;
}

Iterable<JsonObject> _objects(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field.map(JsonObject.fromDart);
}

List<JsonObject>? _nullableObjects(Map<String, Object?> value, String key) {
  if (value[key] == null) return null;
  return List.unmodifiable(_objects(value, key));
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) => {
  for (final entry in value.entries)
    if (!keys.contains(entry.key)) entry.key: entry.value,
};

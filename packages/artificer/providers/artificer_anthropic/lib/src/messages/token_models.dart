import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_core/json.dart';

/// A typed native request for `POST /messages/count_tokens`.
final class AnthropicMessageTokensRequest {
  /// Creates a request from the count endpoint's body fields.
  AnthropicMessageTokensRequest({
    required String model,
    required Iterable<AnthropicInputMessage> messages,
    this.cacheControl,
    this.outputConfig,
    Iterable<AnthropicTextBlock> system = const [],
    this.thinking,
    this.toolChoice,
    Iterable<AnthropicToolDefinition>? tools,
    Iterable<String> betaFeatures = const [],
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       messages = List.unmodifiable(messages),
       system = List.unmodifiable(system),
       tools = tools == null ? null : List.unmodifiable(tools),
       betaFeatures = List.unmodifiable(betaFeatures),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.messages.isEmpty || this.messages.length > 100000) {
      throw ArgumentError.value(
        messages,
        'messages',
        'must contain between 1 and 100000 messages',
      );
    }
    if (this.betaFeatures.any((value) => value.isEmpty)) {
      throw ArgumentError.value(betaFeatures, 'betaFeatures', 'must not contain empty values');
    }
    final collision = this.extraBody
        .toDart()
        .keys
        .where(_reservedRequestFields.contains)
        .firstOrNull;
    if (collision != null) {
      throw ArgumentError.value(
        collision,
        'extraBody',
        'is reserved by the token-count request',
      );
    }
  }

  /// Provider-local model identifier.
  final String model;

  /// Ordered conversation turns whose input tokens will be counted.
  final List<AnthropicInputMessage> messages;

  /// Top-level prompt-cache control.
  final AnthropicCacheControl? cacheControl;

  /// Native output configuration that affects input tokenization.
  final AnthropicOutputConfig? outputConfig;

  /// Top-level system content blocks.
  final List<AnthropicTextBlock> system;

  /// Native thinking configuration.
  final AnthropicThinkingConfig? thinking;

  /// Native tool-selection configuration.
  final AnthropicToolChoice? toolChoice;

  /// Native application or provider tool definitions.
  final List<AnthropicToolDefinition>? tools;

  /// Per-request beta header values, excluded from the JSON body.
  final List<String> betaFeatures;

  /// Forward-compatible count-request body fields.
  final JsonObject extraBody;

  /// Encodes the count endpoint body.
  ///
  /// Provider-level user-profile and workspace settings are request headers and
  /// therefore never appear in this value.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'messages': messages.map((message) => message.toDart()).toList(),
    if (cacheControl case final value?) 'cache_control': value.toDart(),
    if (outputConfig case final value?) 'output_config': value.toJson().toDart(),
    if (system.isNotEmpty) 'system': system.map((block) => block.toDart()).toList(),
    if (thinking case final value?) 'thinking': value.toJson().toDart(),
    if (toolChoice case final value?) 'tool_choice': value.toJson().toDart(),
    if (tools case final value?) 'tools': value.map((tool) => tool.toJson().toDart()).toList(),
  });
}

/// The input-token count returned by Anthropic Messages.
final class AnthropicMessageTokensCount {
  /// Decodes a token-count response while preserving unknown fields.
  factory AnthropicMessageTokensCount.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final inputTokens = value['input_tokens'];
    if (inputTokens is! int || inputTokens < 0) {
      throw const FormatException(
        'input_tokens must be a nonnegative integer.',
      );
    }
    return AnthropicMessageTokensCount._(
      inputTokens: inputTokens,
      raw: raw,
      extensions: JsonObject({
        for (final entry in value.entries)
          if (entry.key != 'input_tokens') entry.key: entry.value,
      }),
    );
  }

  const AnthropicMessageTokensCount._({
    required this.inputTokens,
    required this.raw,
    required this.extensions,
  });

  /// Total input tokens across messages, system content, and tools.
  final int inputTokens;

  /// Complete immutable count response.
  final JsonObject raw;

  /// Fields outside the pinned typed shape.
  final JsonObject extensions;
}

const _reservedRequestFields = {
  'model',
  'messages',
  'cache_control',
  'output_config',
  'system',
  'thinking',
  'tool_choice',
  'tools',
  'user_profile_id',
  'workspace_id',
};

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

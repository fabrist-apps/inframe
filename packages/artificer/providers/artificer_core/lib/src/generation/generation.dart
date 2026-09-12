import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';

/// A normalized reason that generation stopped.
enum FinishReason {
  /// The model completed normally.
  stop,

  /// The model requested one or more application tools.
  toolCalls,

  /// The configured or provider output limit ended generation.
  outputLimit,

  /// The provider refused the request.
  refusal,

  /// A provider content filter ended generation.
  contentFilter,

  /// Provider-hosted work paused and may be continued explicitly.
  paused,

  /// The native reason has no common equivalent.
  other,
}

/// Common generation settings.
final class GenerationOptions {
  /// Creates a [GenerationOptions].
  GenerationOptions({
    this.maxOutputTokens = 4096,
    this.temperature,
    this.topP,
    Iterable<String> stopSequences = const [],
  }) : stopSequences = List.unmodifiable(stopSequences) {
    if (maxOutputTokens <= 0) {
      throw ArgumentError.value(maxOutputTokens, 'maxOutputTokens', 'must be positive');
    }
    _validateUnit(temperature, 'temperature');
    _validateUnit(topP, 'topP');
    if (this.stopSequences.any((value) => value.isEmpty)) {
      throw ArgumentError.value(stopSequences, 'stopSequences', 'must not contain empty values');
    }
  }

  /// Creates a validated immutable value from Dart data.
  factory GenerationOptions.fromDart(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('options must be an object.');
    }
    final stops = value['stopSequences'];
    if (stops is! List<Object?> || stops.any((item) => item is! String)) {
      throw const FormatException('stopSequences must contain strings.');
    }
    return GenerationOptions(
      maxOutputTokens: value['maxOutputTokens']! as int,
      temperature: (value['temperature'] as num?)?.toDouble(),
      topP: (value['topP'] as num?)?.toDouble(),
      stopSequences: stops.cast<String>(),
    );
  }

  /// The maximum generated token count.
  final int maxOutputTokens;

  /// The sampling temperature, when explicitly supplied.
  final double? temperature;

  /// The nucleus sampling threshold, when explicitly supplied.
  final double? topP;

  /// The immutable stop sequences.
  final List<String> stopSequences;

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart() => {
    'maxOutputTokens': maxOutputTokens,
    'temperature': ?temperature,
    'topP': ?topP,
    'stopSequences': stopSequences,
  };
}

/// A request for one foreground generation candidate.
final class GenerationRequest {
  /// Creates a [GenerationRequest].
  GenerationRequest({
    required Iterable<Message> messages,
    this.instructions,
    GenerationOptions? options,
    Iterable<FunctionTool> tools = const [],
    ToolChoice? toolChoice,
    OutputFormat? output,
  }) : messages = List.unmodifiable(messages),
       options = options ?? GenerationOptions(),
       tools = List.unmodifiable(tools),
       toolChoice = toolChoice ?? const AutoToolChoice(),
       output = output ?? const TextOutputFormat() {
    if (this.messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    _validateTools(this.tools);
    if (this.toolChoice case FunctionToolChoice(:final name)
        when !this.tools.any((tool) => tool.name == name)) {
      throw ArgumentError.value(name, 'toolChoice', 'must name a declared function tool');
    }
    _validateHistory(this.messages);
  }

  /// Deserializes and validates a schema-versioned value.
  factory GenerationRequest.fromJson(JsonObject json) {
    final value = _versioned(json);
    return GenerationRequest(
      instructions: value['instructions'] as String?,
      messages: _list(value, 'messages').map(
        (message) => Message.fromJson(JsonObject.fromDart(message)),
      ),
      options: GenerationOptions.fromDart(value['options']),
      tools: _list(value, 'tools').map(FunctionTool.fromDart),
      toolChoice: ToolChoice.fromDart(value['toolChoice']),
      output: OutputFormat.fromDart(value['output']),
    );
  }

  /// Instructions supplied separately from the conversation.
  final String? instructions;

  /// The ordered conversation messages.
  final List<Message> messages;

  /// The common request options.
  final GenerationOptions options;

  /// The application tool declarations available to the model.
  final List<FunctionTool> tools;

  /// The rule controlling whether the model may call a tool.
  final ToolChoice toolChoice;

  /// The requested output format.
  final OutputFormat output;

  /// Rejects replay data owned by a different provider, API, or model.
  InvalidRequestError? validateReplayTarget({
    required String providerId,
    required String api,
    required String modelId,
  }) {
    for (final message in messages.whereType<AssistantMessage>()) {
      final replay = message.replay;
      if (replay != null &&
          (replay.providerId != providerId || replay.api != api || replay.modelId != modelId)) {
        return const InvalidRequestError(
          'Provider replay cannot be submitted to a different provider, API, or model.',
        );
      }
    }
    return null;
  }

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'instructions': ?instructions,
    'messages': messages.map((message) => message.toJson().toDart()).toList(),
    'options': options.toDart(),
    'tools': tools.map((tool) => tool.toDart()).toList(),
    'toolChoice': toolChoice.toDart(),
    'output': output.toDart(),
  });
}

/// An application-owned function declaration without an execution callback.
final class FunctionTool {
  /// Creates a [FunctionTool].
  FunctionTool({required String name, required this.inputSchema, this.description})
    : name = _nonEmpty(name, 'name');

  /// Creates a validated immutable value from Dart data.
  factory FunctionTool.fromDart(Object? value) {
    final map = _object(value, 'function tool');
    return FunctionTool(
      name: _string(map, 'name'),
      description: map['description'] as String?,
      inputSchema: JsonObject.fromDart(map['inputSchema']),
    );
  }

  /// The declared name.
  final String name;

  /// The optional human-readable description.
  final String? description;

  /// The immutable JSON input schema.
  final JsonObject inputSchema;

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart() => {
    'name': name,
    'description': ?description,
    'inputSchema': inputSchema.toDart(),
  };
}

/// Common application-tool selection.
sealed class ToolChoice {
  const ToolChoice();

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart();

  /// Creates a validated immutable value from Dart data.
  static ToolChoice fromDart(Object? value) {
    final map = _object(value, 'tool choice');
    return switch (_string(map, 'type')) {
      'auto' => const AutoToolChoice(),
      'none' => const NoToolChoice(),
      'required' => const RequiredToolChoice(),
      'function' => FunctionToolChoice(_string(map, 'name')),
      final type => throw FormatException('Unknown tool choice: $type'),
    };
  }
}

/// The auto tool choice.
final class AutoToolChoice extends ToolChoice {
  /// Creates an [AutoToolChoice].
  const AutoToolChoice();

  @override
  Map<String, Object?> toDart() => {'type': 'auto'};
}

/// Disables application tool calls.
final class NoToolChoice extends ToolChoice {
  /// Creates a [NoToolChoice].
  const NoToolChoice();

  @override
  Map<String, Object?> toDart() => {'type': 'none'};
}

/// Requires the model to call an application tool.
final class RequiredToolChoice extends ToolChoice {
  /// Creates a [RequiredToolChoice].
  const RequiredToolChoice();

  @override
  Map<String, Object?> toDart() => {'type': 'required'};
}

/// The function tool choice.
final class FunctionToolChoice extends ToolChoice {
  /// Creates a [FunctionToolChoice].
  FunctionToolChoice(String name) : name = _nonEmpty(name, 'name');

  /// The declared name.
  final String name;

  @override
  Map<String, Object?> toDart() => {'type': 'function', 'name': name};
}

/// Common generated-output configuration.
sealed class OutputFormat {
  const OutputFormat();

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart();

  /// Creates a validated immutable value from Dart data.
  static OutputFormat fromDart(Object? value) {
    final map = _object(value, 'output format');
    return switch (_string(map, 'type')) {
      'text' => const TextOutputFormat(),
      'jsonObject' => const JsonObjectOutputFormat(),
      'jsonSchema' => JsonSchemaOutputFormat(
        name: _string(map, 'name'),
        description: map['description'] as String?,
        schema: JsonObject.fromDart(map['schema']),
      ),
      final type => throw FormatException('Unknown output format: $type'),
    };
  }
}

/// The text output format.
final class TextOutputFormat extends OutputFormat {
  /// Creates a [TextOutputFormat].
  const TextOutputFormat();

  @override
  Map<String, Object?> toDart() => {'type': 'text'};
}

/// Requests a JSON object without an application schema.
final class JsonObjectOutputFormat extends OutputFormat {
  /// Creates a [JsonObjectOutputFormat].
  const JsonObjectOutputFormat();

  @override
  Map<String, Object?> toDart() => {'type': 'jsonObject'};
}

/// Requests output matching the supplied JSON Schema.
final class JsonSchemaOutputFormat extends OutputFormat {
  /// Creates a [JsonSchemaOutputFormat].
  JsonSchemaOutputFormat({required String name, required this.schema, this.description})
    : name = _nonEmpty(name, 'name');

  /// The declared name.
  final String name;

  /// The optional human-readable description.
  final String? description;

  /// The immutable JSON Schema.
  final JsonObject schema;

  @override
  Map<String, Object?> toDart() => {
    'type': 'jsonSchema',
    'name': name,
    'description': ?description,
    'schema': schema.toDart(),
  };
}

/// Token accounting reported by a provider.
final class Usage {
  /// Creates a [Usage].
  const Usage({this.inputTokens, this.outputTokens, this.totalTokens});

  /// Creates a validated immutable value from Dart data.
  factory Usage.fromDart(Object? value) {
    final map = _object(value, 'usage');
    return Usage(
      inputTokens: map['inputTokens'] as int?,
      outputTokens: map['outputTokens'] as int?,
      totalTokens: map['totalTokens'] as int?,
    );
  }

  /// The input token count, when reported.
  final int? inputTokens;

  /// The output token count, when reported.
  final int? outputTokens;

  /// The total token count, when reported.
  final int? totalTokens;

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart() => {
    'inputTokens': ?inputTokens,
    'outputTokens': ?outputTokens,
    'totalTokens': ?totalTokens,
  };
}

/// A normalized generation outcome.
final class GenerationResult {
  /// Creates a [GenerationResult].
  GenerationResult({
    required this.message,
    required this.finishReason,
    required this.nativePayload,
    required this.metadata,
    this.nativeFinishReason,
    this.usage,
    this.responseId,
    this.requestId,
  });

  /// Deserializes and validates a schema-versioned value.
  factory GenerationResult.fromJson(JsonObject json) {
    final value = _versioned(json);
    final finishName = _string(value, 'finishReason');
    final finishReason = FinishReason.values
        .where((reason) => reason.name == finishName)
        .firstOrNull;
    if (finishReason == null) throw FormatException('Unknown finish reason: $finishName');
    final message = Message.fromJson(JsonObject.fromDart(value['message']));
    if (message is! AssistantMessage) {
      throw const FormatException('Generation result message must be an assistant message.');
    }
    return GenerationResult(
      message: message,
      finishReason: finishReason,
      nativeFinishReason: value['nativeFinishReason'] as String?,
      usage: switch (value['usage']) {
        final Map<String, Object?> usage => Usage.fromDart(usage),
        _ => null,
      },
      responseId: value['responseId'] as String?,
      requestId: value['requestId'] as String?,
      nativePayload: NativePayload.fromJson(JsonObject.fromDart(value['nativePayload'])),
      metadata: ResponseMetadata.fromJson(JsonObject.fromDart(value['metadata'])),
    );
  }

  /// The human-readable failure or result message.
  final AssistantMessage message;

  /// The normalized reason generation ended.
  final FinishReason finishReason;

  /// The original provider finish reason, when available.
  final String? nativeFinishReason;

  /// The available token usage.
  final Usage? usage;

  /// The provider response identifier, when available.
  final String? responseId;

  /// The provider request identifier, when available.
  final String? requestId;

  /// The complete retained provider response payload.
  final NativePayload nativePayload;

  /// The HTTP response metadata.
  final ResponseMetadata metadata;

  /// The text content.
  String get text => message.text;

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'message': message.toJson().toDart(),
    'finishReason': finishReason.name,
    'nativeFinishReason': ?nativeFinishReason,
    if (usage case final value?) 'usage': value.toDart(),
    'responseId': ?responseId,
    'requestId': ?requestId,
    'nativePayload': nativePayload.toJson().toDart(),
    'metadata': metadata.toJson().toDart(),
  });
}

/// One event emitted by a generation stream.
sealed class GenerationEvent {
  const GenerationEvent();
}

/// The kind of output represented by a streaming part.
enum GenerationPartKind {
  /// User-visible generated text.
  text,

  /// A provider-supplied reasoning summary.
  reasoning,

  /// A provider refusal.
  refusal,

  /// A tool call that the application may execute.
  applicationToolCall,

  /// A provider-owned tool record.
  providerTool,

  /// Provider content without a common representation.
  opaque,
}

/// The component responsible for acting on a streaming part.
enum GenerationPartOwner {
  /// The application owns execution of the part.
  application,

  /// The provider owns execution of the part.
  provider,
}

/// The first event in one generation consumption.
final class GenerationStarted extends GenerationEvent {
  /// Creates a [GenerationStarted].
  const GenerationStarted({required this.metadata, this.responseId});

  /// The provider response identifier, when available.
  final String? responseId;

  /// The HTTP response metadata.
  final ResponseMetadata metadata;
}

/// Declares the stable local identity of one output part.
final class PartStarted extends GenerationEvent {
  /// Creates a [PartStarted].
  const PartStarted({
    required this.partId,
    required this.index,
    required this.kind,
    required this.owner,
  });

  /// The stable provider-independent part identifier.
  final String partId;

  /// The provider or local order index.
  final int index;

  /// The media or part kind.
  final GenerationPartKind kind;

  /// The component responsible for executing the tool.
  final GenerationPartOwner owner;
}

/// An incremental update for one previously started part.
sealed class PartDelta extends GenerationEvent {
  const PartDelta({required this.partId, required this.index});

  /// The stable provider-independent part identifier.
  final String partId;

  /// The provider or local order index.
  final int index;
}

/// Incremental visible text.
final class TextPartDelta extends PartDelta {
  /// Creates a [TextPartDelta].
  const TextPartDelta({required super.partId, required super.index, required this.text});

  /// The text content.
  final String text;
}

/// Incremental provider-supplied reasoning summary.
final class ReasoningPartDelta extends PartDelta {
  /// Creates a [ReasoningPartDelta].
  const ReasoningPartDelta({required super.partId, required super.index, required this.text});

  /// The text content.
  final String text;
}

/// Incremental provider-supplied refusal text.
final class RefusalPartDelta extends PartDelta {
  /// Creates a [RefusalPartDelta].
  const RefusalPartDelta({required super.partId, required super.index, required this.text});

  /// The text content.
  final String text;
}

/// Incremental application-tool arguments in their native text form.
final class ToolArgumentsPartDelta extends PartDelta {
  /// Creates a [ToolArgumentsPartDelta].
  const ToolArgumentsPartDelta({required super.partId, required super.index, required this.text});

  /// The text content.
  final String text;
}

/// Incremental native data that has no common representation.
final class OpaquePartDelta extends PartDelta {
  /// Creates an [OpaquePartDelta].
  const OpaquePartDelta({required super.partId, required super.index, required this.data});

  /// The immutable native replay data.
  final JsonObject data;
}

/// Completes one part without changing its local stream identity.
final class PartFinished extends GenerationEvent {
  /// Creates a [PartFinished].
  const PartFinished({required this.partId, required this.index, required this.part});

  /// The stable provider-independent part identifier.
  final String partId;

  /// The provider or local order index.
  final int index;

  /// The part.
  final OutputPart part;
}

/// A cumulative usage snapshot from the provider.
final class UsageUpdated extends GenerationEvent {
  /// Creates a [UsageUpdated].
  const UsageUpdated(this.usage);

  /// The available token usage.
  final Usage usage;
}

/// A native event retained because the common protocol does not interpret it.
final class ProviderEvent extends GenerationEvent {
  /// Creates a [ProviderEvent].
  ProviderEvent({
    required this.providerId,
    required this.api,
    required String name,
    required this.data,
  }) : name = _nonEmpty(name, 'name');

  /// The stable provider identifier used in diagnostics and replay data.
  final String providerId;

  /// The native API or dialect identifier.
  final String api;

  /// The declared name.
  final String name;

  /// The immutable native replay data.
  final JsonObject data;
}

/// The successful terminal event for a generation stream.
final class GenerationFinished extends GenerationEvent {
  /// Creates a [GenerationFinished].
  const GenerationFinished(this.result);

  /// The tool result.
  final GenerationResult result;
}

void _validateUnit(double? value, String name) {
  if (value != null && (!value.isFinite || value < 0 || value > 1)) {
    throw ArgumentError.value(value, name, 'must be finite and between 0 and 1');
  }
}

void _validateTools(List<FunctionTool> tools) {
  final names = <String>{};
  for (final tool in tools) {
    if (!names.add(tool.name)) {
      throw ArgumentError.value(tool.name, 'tools', 'contains a duplicate tool name');
    }
  }
}

void _validateHistory(List<Message> messages) {
  final calls = <String, ApplicationToolCallPart>{};
  final results = <String>{};
  for (final message in messages) {
    if (message is AssistantMessage) {
      for (final call in message.parts.whereType<ApplicationToolCallPart>()) {
        if (calls.containsKey(call.id)) {
          throw ArgumentError.value(call.id, 'messages', 'contains a duplicate call ID');
        }
        calls[call.id] = call;
      }
    } else if (message is ToolMessage) {
      for (final result in message.results) {
        if (!results.add(result.callId)) {
          throw ArgumentError.value(result.callId, 'messages', 'contains a duplicate result ID');
        }
        final call = calls[result.callId];
        if (call == null) {
          throw ArgumentError.value(result.callId, 'messages', 'references a missing call');
        }
        if (result is NativeToolResult) {
          final arguments = call.arguments;
          if (arguments is! NativeToolArguments ||
              arguments.providerId != result.providerId ||
              arguments.api != result.api) {
            throw ArgumentError.value(
              result.callId,
              'messages',
              'native result target does not match its call',
            );
          }
        }
      }
    }
  }
}

Map<String, Object?> _versioned(JsonObject json) {
  final value = json.toDart();
  if (value['schemaVersion'] != 1) {
    throw FormatException('Unsupported schema version: ${value['schemaVersion']}');
  }
  return value;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

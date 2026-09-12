import '../errors.dart';
import '../json/json_value.dart';
import '../messages/messages.dart';
import '../native.dart';

/// A normalized reason that generation stopped.
enum FinishReason { stop, toolCalls, outputLimit, refusal, contentFilter, paused, other }

/// Common generation settings.
final class GenerationOptions {
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

  final int maxOutputTokens;
  final double? temperature;
  final double? topP;
  final List<String> stopSequences;

  Map<String, Object?> toDart() => {
    'maxOutputTokens': maxOutputTokens,
    if (temperature case final value?) 'temperature': value,
    if (topP case final value?) 'topP': value,
    'stopSequences': stopSequences,
  };

  static GenerationOptions fromDart(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('options must be an object.');
    }
    final stops = value['stopSequences'];
    if (stops is! List<Object?> || stops.any((item) => item is! String)) {
      throw const FormatException('stopSequences must contain strings.');
    }
    return GenerationOptions(
      maxOutputTokens: value['maxOutputTokens'] as int,
      temperature: (value['temperature'] as num?)?.toDouble(),
      topP: (value['topP'] as num?)?.toDouble(),
      stopSequences: stops.cast<String>(),
    );
  }
}

/// A request for one foreground generation candidate.
final class GenerationRequest {
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

  final String? instructions;
  final List<Message> messages;
  final GenerationOptions options;
  final List<FunctionTool> tools;
  final ToolChoice toolChoice;
  final OutputFormat output;

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

  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    if (instructions case final value?) 'instructions': value,
    'messages': messages.map((message) => message.toJson().toDart()).toList(),
    'options': options.toDart(),
    'tools': tools.map((tool) => tool.toDart()).toList(),
    'toolChoice': toolChoice.toDart(),
    'output': output.toDart(),
  });

  static GenerationRequest fromJson(JsonObject json) {
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
}

/// An application-owned function declaration without an execution callback.
final class FunctionTool {
  FunctionTool({required String name, this.description, required this.inputSchema})
    : name = _nonEmpty(name, 'name');

  final String name;
  final String? description;
  final JsonObject inputSchema;

  Map<String, Object?> toDart() => {
    'name': name,
    if (description case final value?) 'description': value,
    'inputSchema': inputSchema.toDart(),
  };

  static FunctionTool fromDart(Object? value) {
    final map = _object(value, 'function tool');
    return FunctionTool(
      name: _string(map, 'name'),
      description: map['description'] as String?,
      inputSchema: JsonObject.fromDart(map['inputSchema']),
    );
  }
}

/// Common application-tool selection.
sealed class ToolChoice {
  const ToolChoice();

  Map<String, Object?> toDart();

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

final class AutoToolChoice extends ToolChoice {
  const AutoToolChoice();

  @override
  Map<String, Object?> toDart() => {'type': 'auto'};
}

final class NoToolChoice extends ToolChoice {
  const NoToolChoice();

  @override
  Map<String, Object?> toDart() => {'type': 'none'};
}

final class RequiredToolChoice extends ToolChoice {
  const RequiredToolChoice();

  @override
  Map<String, Object?> toDart() => {'type': 'required'};
}

final class FunctionToolChoice extends ToolChoice {
  FunctionToolChoice(String name) : name = _nonEmpty(name, 'name');

  final String name;

  @override
  Map<String, Object?> toDart() => {'type': 'function', 'name': name};
}

/// Common generated-output configuration.
sealed class OutputFormat {
  const OutputFormat();

  Map<String, Object?> toDart();

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

final class TextOutputFormat extends OutputFormat {
  const TextOutputFormat();

  @override
  Map<String, Object?> toDart() => {'type': 'text'};
}

final class JsonObjectOutputFormat extends OutputFormat {
  const JsonObjectOutputFormat();

  @override
  Map<String, Object?> toDart() => {'type': 'jsonObject'};
}

final class JsonSchemaOutputFormat extends OutputFormat {
  JsonSchemaOutputFormat({required String name, this.description, required this.schema})
    : name = _nonEmpty(name, 'name');

  final String name;
  final String? description;
  final JsonObject schema;

  @override
  Map<String, Object?> toDart() => {
    'type': 'jsonSchema',
    'name': name,
    if (description case final value?) 'description': value,
    'schema': schema.toDart(),
  };
}

/// Token accounting reported by a provider.
final class Usage {
  const Usage({this.inputTokens, this.outputTokens, this.totalTokens});

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;

  Map<String, Object?> toDart() => {
    if (inputTokens case final value?) 'inputTokens': value,
    if (outputTokens case final value?) 'outputTokens': value,
    if (totalTokens case final value?) 'totalTokens': value,
  };

  static Usage fromDart(Object? value) {
    final map = _object(value, 'usage');
    return Usage(
      inputTokens: map['inputTokens'] as int?,
      outputTokens: map['outputTokens'] as int?,
      totalTokens: map['totalTokens'] as int?,
    );
  }
}

/// A normalized generation outcome.
final class GenerationResult {
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

  final AssistantMessage message;
  final FinishReason finishReason;
  final String? nativeFinishReason;
  final Usage? usage;
  final String? responseId;
  final String? requestId;
  final NativePayload nativePayload;
  final ResponseMetadata metadata;

  String get text => message.text;

  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'message': message.toJson().toDart(),
    'finishReason': finishReason.name,
    if (nativeFinishReason case final value?) 'nativeFinishReason': value,
    if (usage case final value?) 'usage': value.toDart(),
    if (responseId case final value?) 'responseId': value,
    if (requestId case final value?) 'requestId': value,
    'nativePayload': nativePayload.toJson().toDart(),
    'metadata': metadata.toJson().toDart(),
  });

  static GenerationResult fromJson(JsonObject json) {
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
        Map<String, Object?> usage => Usage.fromDart(usage),
        _ => null,
      },
      responseId: value['responseId'] as String?,
      requestId: value['requestId'] as String?,
      nativePayload: NativePayload.fromJson(JsonObject.fromDart(value['nativePayload'])),
      metadata: ResponseMetadata.fromJson(JsonObject.fromDart(value['metadata'])),
    );
  }
}

/// One event emitted by a generation stream.
sealed class GenerationEvent {
  const GenerationEvent();
}

/// The successful terminal event for a generation stream.
final class GenerationFinished extends GenerationEvent {
  const GenerationFinished(this.result);

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

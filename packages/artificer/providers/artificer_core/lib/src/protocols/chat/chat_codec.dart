import 'dart:convert';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/chat/chat_dialect.dart';
import 'package:artificer_core/src/protocols/chat/chat_models.dart';
import 'package:artificer_core/src/protocols/text_request_policy.dart';
import 'package:artificer_core/src/tools/tools.dart';
import 'package:conflux/result.dart';

/// Pure Chat conversion shared by ordinary, native, and streamed operations.
final class ChatCodec {
  /// Creates a codec for one provider-owned wire dialect.
  const ChatCodec(this.dialect);

  /// Routing, identity, field names and pinned inventory.
  final ChatDialect dialect;

  /// Converts common history without sorting messages or losing tool text parts.
  Result<Map<String, Object?>, AiError> request(
    String model,
    GenerationRequest request, {
    GenerationOptions defaults = const GenerationOptions(),
    ChatOptions options = const ChatOptions(),
    ChatOptions optionDefaults = const ChatOptions(),
    bool stream = false,
  }) {
    try {
      for (final tool in request.tools) {
        JsonValues.validate(tool.inputSchema);
      }
      if (request.output case JsonSchemaOutput(:final schema)) JsonValues.validate(schema);
      for (final message in request.messages) {
        if (message is AssistantMessage) {
          JsonValues.validate(message.replay?.items);
          for (final part in message.parts) {
            if (part is ToolCallPart) {
              if (part.arguments case JsonToolArguments(:final value)) JsonValues.validate(value);
              if (part.arguments case NativeToolArguments(:final value)) JsonValues.validate(value);
            }
            if (part is TextOutputPart) {
              for (final citation in part.citations) {
                JsonValues.validate(citation.data);
              }
            }
          }
        }
        if (message is ToolMessage) {
          for (final result in message.results) {
            switch (result.content) {
              case JsonToolResultContent(:final value):
                JsonValues.validate(value);
              case NativeToolResultContent(:final value):
                JsonValues.validate(value);
              case TextToolResultContent():
                break;
            }
          }
        }
      }
      final invalid = request.validate(
        providerId: dialect.providerId,
        api: dialect.api,
        modelId: model,
      );
      if (invalid != null) return Failure(invalid);
      final resolved = request.options.resolve(defaults);
      if (resolved.validate() case final error?) return Failure(error);
      final messages = <Map<String, Object?>>[];
      if (request.instructions case final instructions?) {
        messages.add({'role': dialect.instructionRole, 'content': instructions});
      }
      for (final message in request.messages) {
        switch (message) {
          case UserMessage(:final parts):
            messages.add({
              'role': 'user',
              'content': [
                for (final part in parts) {'type': 'text', 'text': (part as TextInputPart).text},
              ],
            });
          case AssistantMessage(:final replay, :final parts):
            if (replay != null) {
              if (replay.items.length != 1 || replay.items.single is! Map<String, Object?>) {
                return const Failure(
                  InvalidRequestError('Chat replay requires one native assistant message.'),
                );
              }
              messages.add(replay.items.single! as Map<String, Object?>);
              continue;
            }
            if (parts.any(
              (part) =>
                  part is OpaqueOutputPart ||
                  part is ProviderToolPart ||
                  (part is ToolCallPart &&
                      part.arguments is! JsonToolArguments &&
                      part.arguments is! MalformedToolArguments),
            )) {
              return const Failure(
                UnsupportedFeatureError('Native assistant content requires compatible replay.'),
              );
            }
            final native = <String, Object?>{'role': 'assistant'};
            final text = parts.whereType<TextOutputPart>().toList();
            if (text.isNotEmpty) {
              native['content'] = [
                for (final part in text) {'type': 'text', 'text': part.text},
              ];
            }
            final annotations = [
              for (final part in text)
                for (final citation in part.citations) citation.data,
            ];
            if (annotations.isNotEmpty) native['annotations'] = annotations;
            final reasoning = parts.whereType<ReasoningOutputPart>().toList();
            if (reasoning.isNotEmpty) {
              native[dialect.reasoningField] = reasoning.map((part) => part.summary).join();
            }
            final refusals = parts.whereType<RefusalOutputPart>().toList();
            if (refusals.isNotEmpty) native['refusal'] = refusals.map((part) => part.text).join();
            final calls = parts.whereType<ToolCallPart>().toList();
            if (calls.isNotEmpty) {
              native['tool_calls'] = [
                for (final call in calls)
                  {
                    'id': call.callId,
                    'type': 'function',
                    'function': {
                      'name': call.name,
                      'arguments': switch (call.arguments) {
                        JsonToolArguments(:final value, :final original) =>
                          original ?? jsonEncode(value),
                        MalformedToolArguments(:final original) => original,
                        _ => throw StateError('Validated Chat tool argument kind changed.'),
                      },
                    },
                  },
              ];
            }
            messages.add(native);
          case ToolMessage(:final results):
            for (final result in results) {
              final content = switch (result.content) {
                JsonToolResultContent(:final value) => jsonEncode(value),
                TextToolResultContent(:final parts) => [
                  for (final text in parts) {'type': 'text', 'text': text},
                ],
                NativeToolResultContent(:final value) => value,
              };
              messages.add({
                'role': 'tool',
                'tool_call_id': result.callId,
                'content': result is ToolFailure
                    ? jsonEncode({'error': true, 'content': content})
                    : content,
              });
            }
        }
      }
      final seed = options.seed.resolve(optionDefaults.seed.resolve(null));
      final user = options.user.resolve(optionDefaults.user.resolve(null));
      final parallel = options.parallelToolCalls.resolve(
        optionDefaults.parallelToolCalls.resolve(null),
      );
      final body = <String, Object?>{
        'model': model,
        'messages': messages,
        'n': 1,
        'stream': stream,
        if (stream) 'stream_options': {'include_usage': true},
        ...resolved.toWire(maxOutputTokensKey: dialect.maxTokensField),
        'seed': ?seed,
        'user': ?user,
        'parallel_tool_calls': ?parallel,
        if (request.tools.isNotEmpty)
          'tools': [
            for (final tool in request.tools)
              {
                'type': 'function',
                'function': {
                  'name': tool.name,
                  if (tool.description != null) 'description': tool.description,
                  'parameters': tool.inputSchema,
                },
              },
          ],
        if (request.tools.isNotEmpty || request.toolChoice is! AutoToolChoice)
          'tool_choice': switch (request.toolChoice) {
            AutoToolChoice() => 'auto',
            NoToolChoice() => 'none',
            RequiredToolChoice() => 'required',
            NamedToolChoice(:final name) => {
              'type': 'function',
              'function': {'name': name},
            },
          },
        if (request.output is! TextOutput)
          'response_format': switch (request.output) {
            JsonObjectOutput() => {'type': 'json_object'},
            JsonSchemaOutput(:final name, :final description, :final schema) => {
              'type': 'json_schema',
              'json_schema': {
                'name': name,
                'description': ?description,
                'schema': schema,
                'strict': true,
              },
            },
            TextOutput() => {'type': 'text'},
          },
      };
      return _prepare(
        body,
        options.extraBody.resolve(optionDefaults.extraBody.resolve(null)) ?? const {},
      );
    } on FormatException {
      return const Failure(InvalidRequestError('Chat request contains invalid JSON values.'));
    }
  }

  /// Converts native input using its own defaults and the same scope policy.
  Result<Map<String, Object?>, AiError> nativeRequest(
    NativeChatRequest request, {
    bool stream = false,
  }) {
    if (request.messages.isEmpty ||
        request.model.isEmpty ||
        (request.n != null && request.n! <= 0)) {
      return const Failure(
        InvalidRequestError('Native Chat identity, messages or candidate count is invalid.'),
      );
    }
    final body = <String, Object?>{
      'model': request.model,
      'messages': request.messages,
      'stream': stream,
      if (stream) 'stream_options': {'include_usage': true},
      if (request.n != null) 'n': request.n,
      if (request.tools != null) 'tools': request.tools,
      if (request.responseFormat != null) 'response_format': request.responseFormat,
    };
    request.maxTokens?.writeTo(body, dialect.maxTokensField);
    request.temperature?.writeTo(body, 'temperature');
    request.topP?.writeTo(body, 'top_p');
    request.stop?.writeTo(body, 'stop');
    request.toolChoice?.writeTo(body, 'tool_choice');
    request.seed?.writeTo(body, 'seed');
    request.user?.writeTo(body, 'user');
    request.parallelToolCalls?.writeTo(body, 'parallel_tool_calls');
    return _prepare(body, request.extraBody);
  }

  Result<Map<String, Object?>, AiError> _prepare(
    Map<String, Object?> body,
    Map<String, Object?> extras,
  ) {
    final baseline = TextRequestPolicy(
      typedFields: {
        'model',
        'messages',
        'n',
        'stream',
        'stream_options',
        dialect.maxTokensField,
        'temperature',
        'top_p',
        'stop',
        'tools',
        'tool_choice',
        'response_format',
        'seed',
        'user',
        'parallel_tool_calls',
        'store',
      },
      hostedToolTypes: dialect.policy?.hostedToolTypes ?? const {},
      storageField: 'store',
    );
    return baseline
        .prepare(native: body, extraBody: extras)
        .flatMap((prepared) => dialect.policy?.prepare(native: prepared) ?? Success(prepared));
  }

  /// Classifies native error envelopes without hiding HTTP or unknown details.
  AiError? error(Map<String, Object?> data, ResponseMetadata metadata) {
    final configured = dialect.decodeError?.call(data, metadata);
    if (configured is ProviderError) {
      return ProviderError(
        configured.message,
        statusCode: configured.statusCode ?? metadata.statusCode,
        code: configured.code,
        details: configured.details ?? data,
        requestId: configured.requestId ?? metadata.requestId,
        retryAfter: configured.retryAfter ?? metadata.headers['retry-after']?.firstOrNull,
        partialOutput: configured.partialOutput,
      );
    }
    if (configured != null) return configured;
    final value = data['error'];
    if (value is Map<String, Object?> || (value is String && value.isNotEmpty)) {
      return ProviderError(
        'Provider returned a native error.',
        statusCode: metadata.statusCode,
        code: value is Map<String, Object?> && value['code'] is String
            ? value['code']! as String
            : null,
        details: data,
        requestId: metadata.requestId,
      );
    }
    return null;
  }

  /// Decodes a native response once while preserving its complete raw object.
  Result<NativeResponse<ChatResponse>, AiError> decode(Object? data, ResponseMetadata metadata) {
    final Map<String, Object?> raw;
    try {
      JsonValues.validate(data);
      raw = object(data);
    } on FormatException {
      return const Failure(ProtocolError('Malformed native Chat response.'));
    }
    // Provider callbacks are outside structural decoding catches: a callback
    // programming exception must remain a defect, even if it is FormatException.
    if (error(raw, metadata) case final failure?) return Failure(failure);
    try {
      final model = string(raw['model']);
      final choices = <ChatChoice>[];
      final indices = <int>{};
      for (final item in list(raw['choices'])) {
        final choice = object(item);
        final index = integer(choice['index']);
        if (!indices.add(index)) throw const FormatException('Duplicate choice index.');
        final message = object(choice['message']);
        if (message['role'] != 'assistant') throw const FormatException('Missing assistant role.');
        choices.add(
          ChatChoice(
            index: index,
            message: message,
            finishReason: optionalString(choice['finish_reason']),
          ),
        );
      }
      if (choices.isEmpty) throw const FormatException('No choices.');
      final value = ChatResponse(
        model: model,
        choices: choices,
        id: optionalString(raw['id']),
        usage: usage(raw['usage']),
      );
      return Success(
        NativeResponse(
          value: value,
          raw: NativePayload(
            providerId: dialect.providerId,
            api: dialect.api,
            modelId: model,
            data: raw,
          ),
          metadata: metadata,
        ),
      );
    } on FormatException {
      return const Failure(ProtocolError('Malformed native Chat response.'));
    }
  }

  /// Authoritative normalization, also usable on a persisted native response.
  /// Multiple choices require an explicit provider candidate index.
  Result<GenerationResult, AiError> normalize(
    NativeResponse<ChatResponse> response, {
    int? choiceIndex,
  }) {
    if (choiceIndex == null && response.value.choices.length != 1) {
      return const Failure(InvalidRequestError('Select an explicit native choice index.'));
    }
    final matches = response.value.choices
        .where((choice) => choiceIndex == null || choice.index == choiceIndex)
        .toList();
    if (matches.length != 1) {
      return const Failure(InvalidRequestError('Selected native choice is missing or duplicated.'));
    }
    final choice = matches.single;
    try {
      final parts = outputParts(choice.message);
      return Success(
        GenerationResult(
          message: AssistantMessage(
            parts,
            replay: ProviderReplay(
              providerId: dialect.providerId,
              api: dialect.api,
              modelId: response.value.model,
              items: [choice.message],
            ),
          ),
          finishReason: finishReason(choice.finishReason),
          nativeFinishReason: choice.finishReason,
          native: response.raw,
          usage: response.value.usage,
          responseId: response.value.id,
          metadata: response.metadata,
        ),
      );
    } on FormatException {
      return const Failure(ProtocolError('Malformed native Chat message.'));
    }
  }

  /// Converts one fully assembled native assistant message without I/O.
  List<OutputPart> outputParts(Map<String, Object?> message) {
    final parts = <OutputPart>[];
    final citations = <Citation>[];
    if (message['annotations'] case final List<Object?> annotations) {
      for (final item in annotations) {
        final annotation = object(item);
        final source = annotation['url_citation'] is Map<String, Object?>
            ? object(annotation['url_citation'])
            : annotation;
        citations.add(
          Citation(
            data: annotation,
            url: optionalString(source['url']),
            title: optionalString(source['title']),
            start: optionalInteger(source['start_index']),
            end: optionalInteger(source['end_index']),
          ),
        );
      }
    }
    final content = message['content'];
    if (content is String) {
      parts.add(TextOutputPart(content, citations: citations));
    } else if (content is List<Object?>) {
      for (final item in content) {
        final part = object(item);
        if (part['type'] == 'text') {
          parts.add(TextOutputPart(string(part['text'], allowEmpty: true), citations: citations));
        } else if (part['type'] == 'refusal') {
          parts.add(RefusalOutputPart(text: string(part['refusal'], allowEmpty: true)));
        } else {
          parts.add(OpaqueOutputPart(providerId: dialect.providerId, api: dialect.api, data: part));
        }
      }
    } else if (content != null) {
      throw const FormatException('Invalid content.');
    }
    if (message[dialect.reasoningField] != null) {
      parts.add(
        ReasoningOutputPart(summary: string(message[dialect.reasoningField], allowEmpty: true)),
      );
    }
    if (message['refusal'] != null) {
      parts.add(RefusalOutputPart(text: string(message['refusal'], allowEmpty: true)));
    }
    if (message['tool_calls'] != null) {
      for (final item in list(message['tool_calls'])) {
        final call = object(item);
        if (call['type'] != 'function') {
          parts.add(OpaqueOutputPart(providerId: dialect.providerId, api: dialect.api, data: call));
          continue;
        }
        final function = object(call['function']);
        parts.add(
          ToolCallPart(
            callId: string(call['id']),
            name: string(function['name']),
            arguments: ToolArguments.parse(string(function['arguments'], allowEmpty: true)),
          ),
        );
      }
    }
    return parts;
  }

  /// Maps native completion reasons consistently for unary and streams.
  static FinishReason finishReason(String? native) => switch (native) {
    'stop' => FinishReason.stop,
    'tool_calls' || 'function_call' => FinishReason.toolCalls,
    'length' || 'max_tokens' || 'model_length' => FinishReason.outputLimit,
    'content_filter' => FinishReason.contentFilter,
    'refusal' => FinishReason.refusal,
    'paused' => FinishReason.paused,
    _ => FinishReason.other,
  };

  /// Decodes nullable cumulative native usage without inventing accounting.
  static Usage? usage(Object? value) {
    if (value == null) return null;
    final map = object(value);
    return Usage(
      inputTokens: optionalInteger(map['prompt_tokens']),
      outputTokens: optionalInteger(map['completion_tokens']),
      totalTokens: optionalInteger(map['total_tokens']),
    );
  }

  /// Requires a native object; structural failures remain protocol errors.
  static Map<String, Object?> object(Object? value) {
    if (value is! Map<String, Object?>) throw const FormatException('Expected object.');
    return value;
  }

  /// Requires a native array.
  static List<Object?> list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Expected list.');
    return value;
  }

  /// Requires a native string, nonempty for identity fields.
  static String string(Object? value, {bool allowEmpty = false}) {
    if (value is! String || (!allowEmpty && value.isEmpty)) {
      throw const FormatException('Expected string.');
    }
    return value;
  }

  /// Reads an optional native string.
  static String? optionalString(Object? value) =>
      value == null ? null : string(value, allowEmpty: true);

  /// Requires a nonnegative native integer.
  static int integer(Object? value) {
    if (value is! int || value < 0) throw const FormatException('Expected nonnegative integer.');
    return value;
  }

  /// Reads optional native accounting or indices.
  static int? optionalInteger(Object? value) => value == null ? null : integer(value);
}

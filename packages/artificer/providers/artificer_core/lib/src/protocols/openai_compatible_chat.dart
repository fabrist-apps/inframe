import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/generation_stream.dart';
import 'package:artificer_core/src/protocols/sse.dart';
import 'package:conflux/conflux.dart';

/// Provider-owned hooks around the genuinely shared compatible-chat shape.
abstract interface class OpenAiCompatibleChatDialect<O> {
  /// The stable provider identifier used in diagnostics and replay data.
  String get providerId;

  /// The native API or dialect identifier.
  String get api;

  /// Rejects known unsupported common or typed provider options before I/O.
  AiError? validate(GenerationRequest request, O options);

  /// Adds provider fields that do not overlap the compatible typed request.
  JsonObject requestFields(O options);
}

/// An encoded compatible-chat request ready for the shared JSON transport.
final class OpenAiCompatibleChatRequest {
  /// Creates an [OpenAiCompatibleChatRequest].
  const OpenAiCompatibleChatRequest({required this.modelId, required this.body});

  /// The provider-local model identifier.
  final String modelId;

  /// The immutable encoded request body.
  final JsonObject body;
}

/// A typed compatible-chat function call.
final class OpenAiCompatibleToolCall {
  /// Creates an [OpenAiCompatibleToolCall].
  OpenAiCompatibleToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    required this.raw,
    required this.extensions,
  });

  /// Creates a validated immutable value from Dart data.
  factory OpenAiCompatibleToolCall.fromDart(Object? value) {
    final map = _object(value, 'tool call');
    final function = _object(map['function'], 'tool call function');
    return OpenAiCompatibleToolCall(
      id: _string(map, 'id'),
      name: _string(function, 'name'),
      arguments: _string(function, 'arguments'),
      raw: JsonObject(map),
      extensions: JsonObject({
        ..._without(map, {'id', 'type', 'function'}),
        ..._without(function, {'name', 'arguments'}),
      }),
    );
  }

  /// The stable identifier.
  final String id;

  /// The declared name.
  final String name;

  /// The tool arguments exactly as supplied by the model.
  final String arguments;

  /// The complete immutable native JSON object.
  final JsonObject raw;

  /// Unknown native fields retained for typed access.
  final JsonObject extensions;
}

/// A typed assistant message in one native choice.
final class OpenAiCompatibleMessage {
  /// Creates an [OpenAiCompatibleMessage].
  OpenAiCompatibleMessage({
    required Iterable<OpenAiCompatibleToolCall> toolCalls,
    required this.raw,
    required this.extensions,
    this.content,
    this.refusal,
  }) : toolCalls = List.unmodifiable(toolCalls);

  /// Creates a validated immutable value from Dart data.
  factory OpenAiCompatibleMessage.fromDart(Object? value) {
    final map = _object(value, 'choice message');
    final content = map['content'];
    if (content != null && content is! String) {
      throw const FormatException('message content must be a string or null.');
    }
    final refusal = map['refusal'];
    if (refusal != null && refusal is! String) {
      throw const FormatException('message refusal must be a string or null.');
    }
    return OpenAiCompatibleMessage(
      content: content as String?,
      refusal: refusal as String?,
      toolCalls: _optionalList(map, 'tool_calls').map(OpenAiCompatibleToolCall.fromDart),
      raw: JsonObject(map),
      extensions: JsonObject(_without(map, {'role', 'content', 'refusal', 'tool_calls'})),
    );
  }

  /// The ordered content.
  final String? content;

  /// The provider refusal text, when present.
  final String? refusal;

  /// The immutable native function calls.
  final List<OpenAiCompatibleToolCall> toolCalls;

  /// The complete immutable native JSON object.
  final JsonObject raw;

  /// Unknown native fields retained for typed access.
  final JsonObject extensions;
}

/// One indexed native response choice.
final class OpenAiCompatibleChoice {
  /// Creates an [OpenAiCompatibleChoice].
  const OpenAiCompatibleChoice({
    required this.index,
    required this.message,
    required this.finishReason,
    required this.raw,
    required this.extensions,
  });

  /// Creates a validated immutable value from Dart data.
  factory OpenAiCompatibleChoice.fromDart(Object? value) {
    final map = _object(value, 'choice');
    return OpenAiCompatibleChoice(
      index: _integer(map, 'index'),
      message: OpenAiCompatibleMessage.fromDart(map['message']),
      finishReason: _nullableString(map, 'finish_reason'),
      raw: JsonObject(map),
      extensions: JsonObject(_without(map, {'index', 'message', 'finish_reason'})),
    );
  }

  /// The provider or local order index.
  final int index;

  /// The human-readable failure or result message.
  final OpenAiCompatibleMessage message;

  /// The normalized reason generation ended.
  final String? finishReason;

  /// The complete immutable native JSON object.
  final JsonObject raw;

  /// Unknown native fields retained for typed access.
  final JsonObject extensions;
}

/// A typed native compatible-chat response with retained extensions and raw JSON.
final class OpenAiCompatibleChatResponse {
  /// Creates an [OpenAiCompatibleChatResponse].
  OpenAiCompatibleChatResponse({
    required this.id,
    required this.model,
    required Iterable<OpenAiCompatibleChoice> choices,
    required this.raw,
    required this.extensions,
    this.usage,
  }) : choices = List.unmodifiable(choices);

  /// Deserializes and validates a schema-versioned value.
  factory OpenAiCompatibleChatResponse.fromJson(JsonObject json) {
    final map = json.toDart();
    final choices = _list(map, 'choices').map(OpenAiCompatibleChoice.fromDart).toList();
    if (choices.isEmpty) throw const FormatException('choices must not be empty.');
    return OpenAiCompatibleChatResponse(
      id: _string(map, 'id'),
      model: _string(map, 'model'),
      choices: choices,
      usage: _usage(map['usage']),
      raw: json,
      extensions: JsonObject(
        _without(map, {'id', 'object', 'created', 'model', 'choices', 'usage'}),
      ),
    );
  }

  /// The stable identifier.
  final String id;

  /// The provider-reported model identifier.
  final String model;

  /// The immutable indexed native choices.
  final List<OpenAiCompatibleChoice> choices;

  /// The available token usage.
  final Usage? usage;

  /// The complete immutable native JSON object.
  final JsonObject raw;

  /// Unknown native fields retained for typed access.
  final JsonObject extensions;
}

/// One typed event from a compatible-chat SSE stream.
sealed class OpenAiCompatibleStreamEvent {
  const OpenAiCompatibleStreamEvent();
}

/// One indexed delta choice in a native stream chunk.
final class OpenAiCompatibleChunkChoice {
  /// Creates an [OpenAiCompatibleChunkChoice].
  const OpenAiCompatibleChunkChoice({
    required this.index,
    required this.delta,
    required this.finishReason,
    required this.extensions,
  });

  /// Creates a validated immutable value from Dart data.
  factory OpenAiCompatibleChunkChoice.fromDart(Object? value) {
    final map = _object(value, 'stream choice');
    return OpenAiCompatibleChunkChoice(
      index: _integer(map, 'index'),
      delta: JsonObject.fromDart(map['delta']),
      finishReason: _nullableString(map, 'finish_reason'),
      extensions: JsonObject(_without(map, {'index', 'delta', 'finish_reason'})),
    );
  }

  /// The provider or local order index.
  final int index;

  /// The immutable native delta object.
  final JsonObject delta;

  /// The normalized reason generation ended.
  final String? finishReason;

  /// Unknown native fields retained for typed access.
  final JsonObject extensions;
}

/// A typed native delta or trailing-usage chunk.
final class OpenAiCompatibleChunk extends OpenAiCompatibleStreamEvent {
  /// Creates an [OpenAiCompatibleChunk].
  OpenAiCompatibleChunk({
    required this.id,
    required this.model,
    required Iterable<OpenAiCompatibleChunkChoice> choices,
    required this.raw,
    required this.extensions,
    this.usage,
  }) : choices = List.unmodifiable(choices);

  /// The stable identifier.
  final String? id;

  /// The provider-reported model identifier.
  final String? model;

  /// The immutable indexed native choices.
  final List<OpenAiCompatibleChunkChoice> choices;

  /// The available token usage.
  final Usage? usage;

  /// The complete immutable native JSON object.
  final JsonObject raw;

  /// Unknown native fields retained for typed access.
  final JsonObject extensions;
}

/// An unrecognized native object retained as a typed stream event.
final class OpenAiCompatibleUnknownEvent extends OpenAiCompatibleStreamEvent {
  /// Creates an [OpenAiCompatibleUnknownEvent].
  const OpenAiCompatibleUnknownEvent(this.raw);

  /// The complete immutable native JSON object.
  final JsonObject raw;
}

/// The compatible `[DONE]` sentinel, emitted after transport cleanup.
final class OpenAiCompatibleDone extends OpenAiCompatibleStreamEvent {
  /// Creates an [OpenAiCompatibleDone].
  const OpenAiCompatibleDone();
}

/// Shared request, response, and streaming codec for compatible chat providers.
final class OpenAiCompatibleChatCodec<O> {
  /// Creates an [OpenAiCompatibleChatCodec].
  OpenAiCompatibleChatCodec(this.dialect);

  /// The dialect.
  final OpenAiCompatibleChatDialect<O> dialect;

  /// Encodes one common candidate and rejects all extension collisions.
  Result<OpenAiCompatibleChatRequest, AiError> encode(
    GenerationRequest request, {
    required String modelId,
    required O options,
    JsonObject? extraBody,
  }) {
    if (dialect.providerId.isEmpty || dialect.api.isEmpty) {
      return const Failure(
        InvalidRequestError('Compatible dialect providerId and api must not be empty.'),
      );
    }
    final replayError = request.validateReplayTarget(
      providerId: dialect.providerId,
      api: dialect.api,
      modelId: modelId,
    );
    if (replayError != null) return Failure(replayError);
    final validation = dialect.validate(request, options);
    if (validation != null) return Failure(validation);
    try {
      final body = _encodeRequest(request, modelId);
      final dialectFields = dialect.requestFields(options).toDart();
      final collision = dialectFields.keys.where(_reservedRequestFields.contains).firstOrNull;
      if (collision != null) {
        return Failure(
          InvalidRequestError('Dialect field "$collision" collides with a typed request field.'),
        );
      }
      final extras = extraBody?.toDart() ?? const <String, Object?>{};
      final extraCollision = extras.keys
          .where((key) => _reservedRequestFields.contains(key) || dialectFields.containsKey(key))
          .firstOrNull;
      if (extraCollision != null) {
        return Failure(
          InvalidRequestError('extraBody field "$extraCollision" collides with a typed field.'),
        );
      }
      return Success(
        OpenAiCompatibleChatRequest(
          modelId: modelId,
          body: JsonObject({...body, ...dialectFields, ...extras}),
        ),
      );
    } on AiError catch (error) {
      return Failure(error);
    } on Object catch (error) {
      return Failure(InvalidRequestError('The compatible request is invalid: $error'));
    }
  }

  /// Decodes an HTTP JSON response into the typed native model.
  Result<NativeResponse<OpenAiCompatibleChatResponse>, AiError> decodeNative(
    NativeResponse<JsonObject> response,
  ) {
    try {
      return Success(
        NativeResponse(
          value: OpenAiCompatibleChatResponse.fromJson(response.value),
          payload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on Object catch (error) {
      return Failure(ProtocolError('Malformed compatible-chat response: $error'));
    }
  }

  /// Authoritatively maps an already-decoded native response to common output.
  Result<GenerationResult, AiError> normalize(
    NativeResponse<OpenAiCompatibleChatResponse> response, {
    int? choiceIndex,
  }) {
    final native = response.value;
    if (native.choices.length != 1 && choiceIndex == null) {
      return const Failure(
        InvalidRequestError('Multiple native choices require an explicit choiceIndex.'),
      );
    }
    final selectedIndex = choiceIndex ?? native.choices.single.index;
    final choice = native.choices.where((value) => value.index == selectedIndex).firstOrNull;
    if (choice == null) {
      return Failure(InvalidRequestError('Native choice $selectedIndex was not present.'));
    }
    final parts = <OutputPart>[
      if (choice.message.content case final content? when content.isNotEmpty)
        TextOutputPart(content),
      if (choice.message.refusal case final refusal? when refusal.isNotEmpty) RefusalPart(refusal),
      ...choice.message.toolCalls.map(_normalizeToolCall),
    ];
    final message = AssistantMessage(
      parts,
      replay: ProviderReplay(
        providerId: dialect.providerId,
        api: dialect.api,
        modelId: native.model,
        items: [ReplayItem(id: native.id, phase: 'choice', data: choice.raw)],
      ),
    );
    return Success(
      GenerationResult(
        message: message,
        finishReason: _finishReason(choice.finishReason),
        nativeFinishReason: choice.finishReason,
        usage: native.usage,
        responseId: native.id,
        requestId: response.metadata.requestId,
        nativePayload: NativePayload(
          providerId: dialect.providerId,
          api: dialect.api,
          modelId: native.model,
          json: native.raw,
        ),
        metadata: response.metadata,
      ),
    );
  }

  /// Decodes one SSE record into a typed native stream event.
  Result<OpenAiCompatibleStreamEvent, AiError> decodeStreamEvent(SseEvent event) {
    if (event.data == '[DONE]') return const Success(OpenAiCompatibleDone());
    try {
      final raw = JsonObject.parse(event.data);
      final map = raw.toDart();
      if (map['error'] case final error?) {
        final details = error is Map<String, Object?> ? JsonObject(error) : raw;
        final message = error is Map<String, Object?> && error['message'] is String
            ? error['message']! as String
            : 'The compatible provider returned a streamed error.';
        final code = error is Map<String, Object?> && error['code'] is String
            ? error['code']! as String
            : null;
        return Failure(ProviderError(message, code: code, details: details));
      }
      final choicesValue = map['choices'];
      if (choicesValue is! List<Object?>) {
        return Success(OpenAiCompatibleUnknownEvent(raw));
      }
      return Success(
        OpenAiCompatibleChunk(
          id: _nullableString(map, 'id'),
          model: _nullableString(map, 'model'),
          choices: choicesValue.map(OpenAiCompatibleChunkChoice.fromDart),
          usage: _usage(map['usage']),
          raw: raw,
          extensions: JsonObject(
            _without(map, {'id', 'object', 'created', 'model', 'choices', 'usage'}),
          ),
        ),
      );
    } on Object catch (error) {
      return Failure(ProtocolError('Malformed compatible-chat stream event: $error'));
    }
  }

  /// Creates a native-event protocol for the shared SSE transport.
  SseProtocol<OpenAiCompatibleStreamEvent> toNativeStream() =>
      _OpenAiCompatibleNativeProtocol(this);

  /// Creates the common generation protocol for the shared SSE transport.
  SseProtocol<GenerationEvent> commonStream({
    required String modelId,
    int maxAssembledBytes = 64 * 1024 * 1024,
  }) => _OpenAiCompatibleCommonProtocol(
    this,
    modelId: modelId,
    maxAssembledBytes: maxAssembledBytes,
  );
}

final class _OpenAiCompatibleNativeProtocol<O> implements SseProtocol<OpenAiCompatibleStreamEvent> {
  _OpenAiCompatibleNativeProtocol(this.codec);

  final OpenAiCompatibleChatCodec<O> codec;
  var _done = false;

  @override
  bool get isTerminal => _done;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<OpenAiCompatibleStreamEvent> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<OpenAiCompatibleStreamEvent> decode(SseEvent event) {
    return switch (codec.decodeStreamEvent(event)) {
      Success(:final value) when value is OpenAiCompatibleDone => _markDone(),
      Success(:final value) => [value],
      Failure(:final error) => throw error,
    };
  }

  Iterable<OpenAiCompatibleStreamEvent> _markDone() {
    _done = true;
    return const [];
  }

  @override
  Iterable<OpenAiCompatibleStreamEvent> finish() {
    if (!_done) throw const ProtocolError('Compatible stream ended before [DONE].');
    return const [OpenAiCompatibleDone()];
  }
}

final class _OpenAiCompatibleCommonProtocol<O> implements SseProtocol<GenerationEvent> {
  _OpenAiCompatibleCommonProtocol(
    this.codec, {
    required this.modelId,
    required int maxAssembledBytes,
  }) : assembler = GenerationStreamAssembler(
         providerId: codec.dialect.providerId,
         api: codec.dialect.api,
         modelId: modelId,
         maxAssembledBytes: maxAssembledBytes,
       );

  final OpenAiCompatibleChatCodec<O> codec;
  final String modelId;
  final GenerationStreamAssembler assembler;
  final StringBuffer _text = StringBuffer();
  final StringBuffer _refusal = StringBuffer();
  final Map<int, _ToolStreamState> _tools = {};
  final Map<String, Object?> _choiceExtensions = {};
  final List<ReplayItem> _replay = [];
  JsonObject? _nativeUsage;
  String? _responseId;
  String? _actualModel;
  String? _nativeFinishReason;
  var _startedText = false;
  var _startedRefusal = false;
  var _done = false;
  var _partsFinished = false;

  @override
  bool get isTerminal => _done;

  @override
  Object? get partialOutput => assembler.partialMessage;

  @override
  Iterable<GenerationEvent> start(ResponseMetadata metadata) {
    return [assembler.start(metadata)];
  }

  @override
  Iterable<GenerationEvent> decode(SseEvent event) {
    return switch (codec.decodeStreamEvent(event)) {
      Failure(:final error) => throw _withPartial(error),
      Success(:final value) => switch (value) {
        OpenAiCompatibleDone() => _markDone(),
        OpenAiCompatibleUnknownEvent(:final raw) => _unknown(raw),
        OpenAiCompatibleChunk() => _chunk(value),
      },
    };
  }

  Iterable<GenerationEvent> _markDone() {
    _done = true;
    return const [];
  }

  Iterable<GenerationEvent> _unknown(JsonObject raw) {
    _replay.add(ReplayItem(phase: 'unknown-event', data: raw));
    return [assembler.providerEvent('compatible.unknown', raw)];
  }

  Iterable<GenerationEvent> _chunk(OpenAiCompatibleChunk chunk) sync* {
    if (chunk.id case final id?) {
      _responseId ??= id;
      assembler.setResponseId(id);
    }
    if (chunk.model case final model?) {
      if (_actualModel != null && _actualModel != model) {
        throw ProtocolError(
          'The model ID changed during streaming.',
          partialOutput: assembler.partialMessage,
        );
      }
      _actualModel = model;
    }
    if (chunk.extensions.toDart().isNotEmpty) {
      _replay.add(ReplayItem(phase: 'chunk-extension', data: chunk.extensions));
      yield assembler.providerEvent('compatible.chunk-extension', chunk.extensions);
    }
    for (final choice in chunk.choices) {
      if (choice.index != 0) {
        throw ProtocolError(
          'The common compatible stream received choice ${choice.index}; expected choice 0.',
          partialOutput: assembler.partialMessage,
        );
      }
      _choiceExtensions.addAll(choice.extensions.toDart());
      yield* _delta(choice.delta);
      if (choice.finishReason case final reason?) {
        _nativeFinishReason = reason;
        yield* _finishParts();
      }
    }
    if (chunk.usage case final usage?) {
      _nativeUsage = JsonObject.fromDart(chunk.raw.toDart()['usage']);
      yield assembler.updateUsage(usage);
    }
  }

  Iterable<GenerationEvent> _delta(JsonObject delta) sync* {
    final value = delta.toDart();
    if (value['content'] case final String content) {
      if (!_startedText) {
        _startedText = true;
        yield assembler.startPart(index: 0, kind: GenerationPartKind.text);
      }
      _text.write(content);
      yield assembler.appendText(0, content);
    }
    if (value['refusal'] case final String refusal) {
      if (!_startedRefusal) {
        _startedRefusal = true;
        yield assembler.startPart(index: 1, kind: GenerationPartKind.refusal);
      }
      _refusal.write(refusal);
      yield assembler.appendText(1, refusal);
    }
    for (final rawCall in _optionalList(value, 'tool_calls')) {
      final call = _object(rawCall, 'stream tool call');
      final nativeIndex = _integer(call, 'index');
      final partIndex = nativeIndex + 2;
      final state = _tools.putIfAbsent(nativeIndex, _ToolStreamState.new);
      if (!state.started) {
        state.started = true;
        yield assembler.startPart(
          index: partIndex,
          kind: GenerationPartKind.applicationToolCall,
        );
      }
      if (call['id'] case final String id) state.id = id;
      state.extensions.addAll(_without(call, {'index', 'id', 'type', 'function'}));
      if (call['function'] case final Map<String, Object?> function) {
        if (function['name'] case final String name) state.name = name;
        state.functionExtensions.addAll(_without(function, {'name', 'arguments'}));
        if (function['arguments'] case final String arguments) {
          state.arguments.write(arguments);
          yield assembler.appendText(partIndex, arguments);
        }
      }
    }
    final extensions = _without(value, {'role', 'content', 'refusal', 'tool_calls'});
    if (extensions.isNotEmpty) {
      final raw = JsonObject(extensions);
      _replay.add(ReplayItem(phase: 'delta-extension', data: raw));
      yield assembler.providerEvent('compatible.delta-extension', raw);
    }
  }

  Iterable<GenerationEvent> _finishParts() sync* {
    if (_partsFinished) return;
    _partsFinished = true;
    if (_startedText) yield assembler.finishPart(0, TextOutputPart(_text.toString()));
    if (_startedRefusal) yield assembler.finishPart(1, RefusalPart(_refusal.toString()));
    for (final entry in _tools.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      final state = entry.value;
      if (state.id == null || state.id!.isEmpty || state.name == null || state.name!.isEmpty) {
        throw ProtocolError(
          'Streamed tool ${entry.key} ended without its native ID or name.',
          partialOutput: assembler.partialMessage,
        );
      }
      final arguments = _toolArguments(state.arguments.toString());
      yield assembler.finishPart(
        entry.key + 2,
        ApplicationToolCallPart(
          id: state.id!,
          name: state.name!,
          arguments: arguments,
        ),
      );
    }
  }

  @override
  Iterable<GenerationEvent> finish() sync* {
    if (!_done || _nativeFinishReason == null) {
      throw ProtocolError(
        'Compatible stream ended before finish metadata and [DONE].',
        partialOutput: assembler.partialMessage,
      );
    }
    yield* _finishParts();
    final nativeResponse = _toAssembledResponse();
    final nativeChoice = (nativeResponse.toDart()['choices']! as List<Object?>).single;
    yield assembler.finish(
      finishReason: _finishReason(_nativeFinishReason),
      nativeFinishReason: _nativeFinishReason,
      nativeResponse: nativeResponse,
      replay: [
        ReplayItem(
          phase: 'choice',
          data: JsonObject.fromDart(nativeChoice),
        ),
        ..._replay,
      ],
    );
  }

  JsonObject _toAssembledResponse() {
    final toolCalls = _tools.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return JsonObject({
      'id': _responseId ?? '',
      'model': _actualModel ?? modelId,
      'choices': [
        {
          ..._choiceExtensions,
          'index': 0,
          'message': {
            'role': 'assistant',
            if (_startedText) 'content': _text.toString(),
            if (_startedRefusal) 'refusal': _refusal.toString(),
            if (toolCalls.isNotEmpty)
              'tool_calls': [
                for (final entry in toolCalls)
                  {
                    ...entry.value.extensions,
                    'id': entry.value.id,
                    'type': 'function',
                    'function': {
                      ...entry.value.functionExtensions,
                      'name': entry.value.name,
                      'arguments': entry.value.arguments.toString(),
                    },
                  },
              ],
          },
          'finish_reason': _nativeFinishReason,
        },
      ],
      if (_nativeUsage case final usage?) 'usage': usage.toDart(),
    });
  }

  AiError _withPartial(AiError error) => switch (error) {
    ProviderError() => ProviderError(
      error.message,
      statusCode: error.statusCode,
      code: error.code,
      details: error.details,
      requestId: error.requestId,
      retryAfter: error.retryAfter,
      rawRetryAfter: error.rawRetryAfter,
      partialOutput: error.partialOutput ?? assembler.partialMessage,
      remoteResourceId: error.remoteResourceId,
    ),
    ProtocolError() => ProtocolError(
      error.message,
      partialOutput: error.partialOutput ?? assembler.partialMessage,
      remoteResourceId: error.remoteResourceId,
    ),
    _ => error,
  };
}

final class _ToolStreamState {
  bool started = false;
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
  final Map<String, Object?> extensions = {};
  final Map<String, Object?> functionExtensions = {};
}

Map<String, Object?> _encodeRequest(GenerationRequest request, String modelId) {
  if (modelId.isEmpty) throw ArgumentError.value(modelId, 'modelId');
  final messages = <Map<String, Object?>>[
    if (request.instructions case final instructions?) {'role': 'system', 'content': instructions},
    for (final message in request.messages) ..._encodeMessage(message),
  ];
  return {
    'model': modelId,
    'messages': messages,
    'n': 1,
    'max_tokens': request.options.maxOutputTokens,
    'temperature': ?request.options.temperature,
    'top_p': ?request.options.topP,
    if (request.options.stopSequences.isNotEmpty) 'stop': request.options.stopSequences,
    if (request.tools.isNotEmpty)
      'tools': request.tools
          .map(
            (tool) => {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': ?tool.description,
                'parameters': tool.inputSchema.toDart(),
              },
            },
          )
          .toList(),
    if (request.tools.isNotEmpty) 'tool_choice': _toolChoice(request.toolChoice),
    if (request.output is! TextOutputFormat) 'response_format': _outputFormat(request.output),
  };
}

Iterable<Map<String, Object?>> _encodeMessage(Message message) sync* {
  switch (message) {
    case UserMessage(:final parts):
      final text = <String>[];
      for (final part in parts) {
        if (part is! TextInputPart) {
          throw const UnsupportedFeatureError(
            'Compatible chat only shares text input; dialects must own media extensions.',
            feature: 'mediaInput',
          );
        }
        text.add(part.text);
      }
      yield {'role': 'user', 'content': text.join()};
    case AssistantMessage(:final parts, :final replay):
      if (replay != null) {
        yield _compatibleReplayMessage(replay);
        return;
      }
      final text = parts.whereType<TextOutputPart>().map((part) => part.text).join();
      final calls = parts.whereType<ApplicationToolCallPart>().toList();
      final unsupported = parts.where(
        (part) => part is! TextOutputPart && part is! ApplicationToolCallPart,
      );
      if (unsupported.isNotEmpty) {
        throw const UnsupportedFeatureError(
          'Compatible chat cannot encode this assistant output part.',
          feature: 'assistantOutputPart',
        );
      }
      yield {
        'role': 'assistant',
        if (text.isNotEmpty) 'content': text,
        if (calls.isNotEmpty)
          'tool_calls': calls
              .map(
                (call) => {
                  'id': call.id,
                  'type': 'function',
                  'function': {
                    'name': call.name,
                    'arguments': _argumentsText(call.arguments),
                  },
                },
              )
              .toList(),
      };
    case ToolMessage(:final results):
      for (final result in results) {
        yield {
          'role': 'tool',
          'tool_call_id': result.callId,
          'content': _toolResultText(result),
        };
      }
  }
}

Object _toolChoice(ToolChoice choice) => switch (choice) {
  AutoToolChoice() => 'auto',
  NoToolChoice() => 'none',
  RequiredToolChoice() => 'required',
  FunctionToolChoice(:final name) => {
    'type': 'function',
    'function': {'name': name},
  },
};

Map<String, Object?> _outputFormat(OutputFormat output) => switch (output) {
  JsonObjectOutputFormat() => {'type': 'json_object'},
  JsonSchemaOutputFormat(:final name, :final description, :final schema) => {
    'type': 'json_schema',
    'json_schema': {
      'name': name,
      'description': ?description,
      'schema': schema.toDart(),
    },
  },
  TextOutputFormat() => {'type': 'text'},
};

String _argumentsText(ToolArguments arguments) => switch (arguments) {
  JsonToolArguments(:final value, :final originalText) => originalText ?? value.encode(),
  TextToolArguments(:final text) => text,
  MalformedToolArguments(:final originalText) => originalText,
  NativeToolArguments() => throw const UnsupportedFeatureError(
    'Compatible chat cannot encode provider-native tool arguments.',
    feature: 'nativeToolArguments',
  ),
};

String _toolResultText(ToolResult result) => switch (result) {
  JsonToolResult(:final value) => value.encode(),
  TextToolResult(:final content) => content.map((part) {
    if (part is! TextInputPart) {
      throw const UnsupportedFeatureError(
        'Compatible chat cannot encode media tool results.',
        feature: 'mediaToolResult',
      );
    }
    return part.text;
  }).join(),
  NativeToolResult(:final value) => value.encode(),
  ApplicationErrorToolResult(:final message) => message,
};

Map<String, Object?> _compatibleReplayMessage(ProviderReplay replay) {
  final choice = replay.items.where((item) => item.phase == 'choice').firstOrNull;
  if (choice == null) {
    throw const InvalidRequestError(
      'Compatible assistant replay is missing its native choice.',
    );
  }
  final choiceData = choice.data.toDart();
  final message = _object(choiceData['message'], 'compatible replay message');
  if (message['role'] != 'assistant') {
    throw const InvalidRequestError(
      'Compatible assistant replay must contain an assistant message.',
    );
  }
  return message;
}

ApplicationToolCallPart _normalizeToolCall(OpenAiCompatibleToolCall call) =>
    ApplicationToolCallPart(
      id: call.id,
      name: call.name,
      arguments: _toolArguments(call.arguments),
    );

ToolArguments _toolArguments(String source) {
  try {
    return JsonToolArguments(JsonObject.parse(source), originalText: source);
  } on Object catch (error) {
    return MalformedToolArguments(originalText: source, issue: error.toString());
  }
}

Usage? _usage(Object? value) {
  if (value == null) return null;
  final map = _object(value, 'usage');
  return Usage(
    inputTokens: _nullableInteger(map, 'prompt_tokens'),
    outputTokens: _nullableInteger(map, 'completion_tokens'),
    totalTokens: _nullableInteger(map, 'total_tokens'),
  );
}

FinishReason _finishReason(String? reason) => switch (reason) {
  'stop' => FinishReason.stop,
  'tool_calls' || 'function_call' => FinishReason.toolCalls,
  'length' => FinishReason.outputLimit,
  'content_filter' => FinishReason.contentFilter,
  'refusal' => FinishReason.refusal,
  _ => FinishReason.other,
};

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return value;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

List<Object?> _optionalList(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return const [];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

String? _nullableString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field != null && field is! String) throw FormatException('$key must be a string or null.');
  return field as String?;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

int? _nullableInteger(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field != null && field is! int) throw FormatException('$key must be an integer or null.');
  return field as int?;
}

Map<String, Object?> _without(Map<String, Object?> source, Set<String> known) => {
  for (final entry in source.entries)
    if (!known.contains(entry.key)) entry.key: entry.value,
};

const _reservedRequestFields = {
  'model',
  'messages',
  'n',
  'max_tokens',
  'temperature',
  'top_p',
  'stop',
  'tools',
  'tool_choice',
  'response_format',
  'stream',
  'stream_options',
};

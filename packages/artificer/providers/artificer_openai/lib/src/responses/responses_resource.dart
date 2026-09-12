import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_openai/src/responses/response_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'openai';
const _api = 'responses';

/// Typed native Responses operations and common normalization.
final class OpenAIResponsesResource {
  /// Creates the resource over one provider-owned core client.
  const OpenAIResponsesResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one ordinary response.
  Effect<NativeResponse<OpenAIResponse>, AiError> create(OpenAIResponseRequest request) {
    final body = _encode(request, stream: false);
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'POST', path: 'responses', body: body),
          providerId: _providerId,
          api: _api,
          modelId: request.model,
        )
        .flatMap(_decode);
  }

  /// Streams typed native Responses events.
  Flow<OpenAIResponseEvent, AiError> stream(OpenAIResponseRequest request) {
    final body = _encode(request, stream: true);
    return _client.sendSse(
      ProviderHttpRequest(method: 'POST', path: 'responses', body: body),
      createProtocol: _OpenAINativeResponsesProtocol.new,
    );
  }

  /// Streams common events from the same Responses wire decoder.
  Flow<GenerationEvent, AiError> streamCommon(OpenAIResponseRequest request) {
    final body = _encode(request, stream: true);
    return _client.sendSse(
      ProviderHttpRequest(method: 'POST', path: 'responses', body: body),
      createProtocol: () => _OpenAICommonResponsesProtocol(this, request.model),
    );
  }

  /// Normalizes an already-decoded native response without issuing I/O.
  GenerationResult normalize(NativeResponse<OpenAIResponse> response) {
    final value = response.value;
    final parts = <OutputPart>[];
    for (final item in value.output) {
      if (item case OpenAIResponseMessageItem(:final content)) {
        for (final part in content) {
          switch (part) {
            case OpenAIOutputTextContent(:final text):
              parts.add(TextOutputPart(text));
            case OpenAIRefusalContent(:final refusal):
              parts.add(RefusalPart(refusal));
            case OpenAIUnknownOutputContent():
              parts.add(
                OpaqueOutputPart(
                  providerId: _providerId,
                  api: _api,
                  kind: part.type,
                  data: part.raw,
                ),
              );
          }
        }
      } else {
        parts.add(
          OpaqueOutputPart(
            providerId: _providerId,
            api: _api,
            kind: item.type,
            data: item.raw,
          ),
        );
      }
    }
    final usage = value.usage;
    return GenerationResult(
      message: AssistantMessage(
        parts,
        replay: ProviderReplay(
          providerId: _providerId,
          api: _api,
          modelId: response.payload.modelId,
          items: [
            for (final item in value.output)
              ReplayItem(
                id: item.id,
                phase: item.extensions.toDart()['phase'] as String?,
                data: item.raw,
              ),
          ],
        ),
      ),
      finishReason: _finishReason(value),
      nativeFinishReason: value.status.name,
      usage: usage == null
          ? null
          : Usage(
              inputTokens: usage.inputTokens,
              outputTokens: usage.outputTokens,
              totalTokens: usage.totalTokens,
            ),
      responseId: value.id,
      requestId: response.metadata.requestId,
      nativePayload: response.payload,
      metadata: response.metadata,
    );
  }

  JsonObject _encode(OpenAIResponseRequest request, {required bool stream}) =>
      JsonObject({...request.toJson().toDart(), 'stream': stream});

  Effect<NativeResponse<OpenAIResponse>, AiError> _decode(NativeResponse<JsonObject> response) {
    try {
      return Effect.succeed(
        NativeResponse(
          value: OpenAIResponse.fromJson(response.value),
          payload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Effect.fail(ProtocolError(error.message));
    }
  }
}

/// One typed native Responses stream event.
sealed class OpenAIResponseEvent {
  OpenAIResponseEvent({required this.type, required this.raw, required this.extensions});

  /// Decodes an event from its complete JSON payload.
  factory OpenAIResponseEvent.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    final extensions = JsonObject(
      _without(value, {'type', 'sequence_number', 'response', 'delta'}),
    );
    return switch (type) {
      'response.created' => OpenAIResponseCreatedEvent._(
        response: OpenAIResponse.fromJson(JsonObject.fromDart(value['response'])),
        raw: raw,
        extensions: extensions,
      ),
      'response.output_text.delta' => OpenAIResponseTextDeltaEvent._(
        delta: _string(value, 'delta'),
        raw: raw,
        extensions: extensions,
      ),
      'response.completed' || 'response.incomplete' => OpenAIResponseCompletedEvent._(
        type: type,
        response: OpenAIResponse.fromJson(JsonObject.fromDart(value['response'])),
        raw: raw,
        extensions: extensions,
      ),
      _ => OpenAIUnknownResponseEvent._(type: type, raw: raw, extensions: extensions),
    };
  }

  /// Native event type.
  final String type;

  /// Complete native event JSON.
  final JsonObject raw;

  /// Fields outside this event's typed members.
  final JsonObject extensions;
}

/// The initial native response state.
final class OpenAIResponseCreatedEvent extends OpenAIResponseEvent {
  OpenAIResponseCreatedEvent._({
    required this.response,
    required super.raw,
    required super.extensions,
  }) : super(type: 'response.created');

  /// The created response.
  final OpenAIResponse response;
}

/// One visible text delta.
final class OpenAIResponseTextDeltaEvent extends OpenAIResponseEvent {
  OpenAIResponseTextDeltaEvent._({
    required this.delta,
    required super.raw,
    required super.extensions,
  }) : super(type: 'response.output_text.delta');

  /// New visible text.
  final String delta;
}

/// A successful or incomplete terminal response event.
final class OpenAIResponseCompletedEvent extends OpenAIResponseEvent {
  OpenAIResponseCompletedEvent._({
    required super.type,
    required this.response,
    required super.raw,
    required super.extensions,
  });

  /// The terminal response.
  final OpenAIResponse response;
}

/// An event outside the typed snapshot, retained without loss.
final class OpenAIUnknownResponseEvent extends OpenAIResponseEvent {
  OpenAIUnknownResponseEvent._({
    required super.type,
    required super.raw,
    required super.extensions,
  });
}

final class _OpenAINativeResponsesProtocol implements SseProtocol<OpenAIResponseEvent> {
  var _terminal = false;

  @override
  bool get isTerminal => _terminal;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<OpenAIResponseEvent> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<OpenAIResponseEvent> decode(SseEvent event) {
    final decoded = _decodeEvent(event);
    if (decoded.type == 'response.failed' || decoded.type == 'error') {
      throw ProviderError('OpenAI reported a streaming error.', details: decoded.raw);
    }
    if (decoded is OpenAIResponseCompletedEvent) _terminal = true;
    return [decoded];
  }

  @override
  Iterable<OpenAIResponseEvent> finish() {
    if (!_terminal) throw const ProtocolError('Responses stream ended before a terminal event.');
    return const [];
  }
}

final class _OpenAICommonResponsesProtocol implements SseProtocol<GenerationEvent> {
  _OpenAICommonResponsesProtocol(this.resource, this.modelId)
    : assembler = GenerationStreamAssembler(
        providerId: _providerId,
        api: _api,
        modelId: modelId,
      );

  final OpenAIResponsesResource resource;
  final String modelId;
  final GenerationStreamAssembler assembler;
  var _terminal = false;
  var _textStarted = false;

  @override
  bool get isTerminal => _terminal;

  @override
  Object? get partialOutput => assembler.partialMessage;

  @override
  Iterable<GenerationEvent> start(ResponseMetadata metadata) => [assembler.start(metadata)];

  @override
  Iterable<GenerationEvent> decode(SseEvent event) sync* {
    final decoded = _decodeEvent(event);
    switch (decoded) {
      case OpenAIResponseCreatedEvent(:final response):
        assembler.setResponseId(response.id);
      case OpenAIResponseTextDeltaEvent(:final delta):
        if (!_textStarted) {
          _textStarted = true;
          yield assembler.startPart(index: 0, kind: GenerationPartKind.text);
        }
        yield assembler.appendText(0, delta);
      case OpenAIResponseCompletedEvent(:final response):
        _terminal = true;
        _lastTerminal = response;
        final native = NativeResponse(
          value: response,
          payload: NativePayload(
            providerId: _providerId,
            api: _api,
            modelId: modelId,
            json: response.raw,
          ),
          metadata: ResponseMetadata(statusCode: 200),
        );
        final result = resource.normalize(native);
        final text = result.message.parts
            .whereType<TextOutputPart>()
            .map((part) => part.text)
            .join();
        if (!_textStarted && text.isNotEmpty) {
          _textStarted = true;
          yield assembler.startPart(index: 0, kind: GenerationPartKind.text);
        }
        if (_textStarted) yield assembler.finishPart(0, TextOutputPart(text));
        if (result.usage case final usage?) yield assembler.updateUsage(usage);
      case OpenAIUnknownResponseEvent():
        if (decoded.type == 'response.failed' || decoded.type == 'error') {
          throw ProviderError(
            'OpenAI reported a streaming error.',
            details: decoded.raw,
            partialOutput: assembler.partialMessage,
          );
        }
        yield assembler.providerEvent(decoded.type, decoded.raw);
    }
  }

  @override
  Iterable<GenerationEvent> finish() sync* {
    if (!_terminal) {
      throw ProtocolError(
        'Responses stream ended before a terminal event.',
        partialOutput: assembler.partialMessage,
      );
    }
    // Re-decode the terminal payload through the assembler's retained parts.
    final terminal = _lastTerminal;
    if (terminal == null) throw const ProtocolError('Responses terminal payload was not retained.');
    yield assembler.finish(
      finishReason: _finishReason(terminal),
      nativeFinishReason: terminal.status.name,
      nativeResponse: terminal.raw,
      replay: [
        for (final item in terminal.output)
          ReplayItem(
            id: item.id,
            phase: item.extensions.toDart()['phase'] as String?,
            data: item.raw,
          ),
      ],
    );
  }

  OpenAIResponse? _lastTerminal;
}

OpenAIResponseEvent _decodeEvent(SseEvent event) {
  try {
    return OpenAIResponseEvent.fromJson(JsonObject.parse(event.data));
  } on FormatException catch (error) {
    throw ProtocolError(error.message);
  }
}

FinishReason _finishReason(OpenAIResponse response) {
  if (response.status == OpenAIResponseStatus.incomplete) {
    final details = response.raw.toDart()['incomplete_details'];
    if (details is Map<String, Object?>) {
      return switch (details['reason']) {
        'max_output_tokens' || 'max_messages' => FinishReason.outputLimit,
        'content_filter' => FinishReason.contentFilter,
        _ => FinishReason.other,
      };
    }
  }
  if (response.output
      .whereType<OpenAIResponseMessageItem>()
      .expand((item) => item.content)
      .any((part) => part is OpenAIRefusalContent)) {
    return FinishReason.refusal;
  }
  return FinishReason.stop;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

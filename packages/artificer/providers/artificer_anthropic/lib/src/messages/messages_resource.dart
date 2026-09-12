import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'anthropic';
const _api = 'messages';

/// Typed native Messages operations and common normalization.
final class AnthropicMessagesResource {
  /// Creates this resource over one provider-owned core client.
  const AnthropicMessagesResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one native Message.
  Effect<NativeResponse<AnthropicMessage>, AiError> create(AnthropicMessageRequest request) =>
      _client
          .sendJson(
            ProviderHttpRequest(
              method: 'POST',
              path: 'messages',
              body: request.toJson(stream: false),
            ),
            providerId: _providerId,
            api: _api,
            modelId: request.model,
          )
          .flatMap(_decodeMessage);

  /// Streams typed native Messages events.
  Flow<AnthropicMessageEvent, AiError> stream(
    AnthropicMessageRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) => _client.sendSse(
    ProviderHttpRequest(
      method: 'POST',
      path: 'messages',
      body: request.toJson(stream: true),
    ),
    createProtocol: _AnthropicNativeProtocol.new,
    decodedEventCapacity: decodedEventCapacity,
    maxEventBytes: maxEventBytes,
    maxStreamBytes: maxStreamBytes,
  );

  /// Streams normalized generation events through the same native decoder.
  Flow<GenerationEvent, AiError> streamCommon(
    AnthropicMessageRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
    int maxAssembledBytes = 64 * 1024 * 1024,
  }) => _client.sendSse(
    ProviderHttpRequest(
      method: 'POST',
      path: 'messages',
      body: request.toJson(stream: true),
    ),
    createProtocol: () => _AnthropicCommonProtocol(
      request.model,
      maxAssembledBytes: maxAssembledBytes,
    ),
    decodedEventCapacity: decodedEventCapacity,
    maxEventBytes: maxEventBytes,
    maxStreamBytes: maxStreamBytes,
  );

  /// Normalizes an already-decoded Message without issuing I/O.
  GenerationResult normalize(NativeResponse<AnthropicMessage> response) {
    final value = response.value;
    final usage = _commonUsage(value.usage);
    return GenerationResult(
      message: AssistantMessage(
        value.content.map(_commonPart),
        replay: ProviderReplay(
          providerId: _providerId,
          api: _api,
          modelId: response.payload.modelId,
          items: [
            for (final block in value.content) ReplayItem(data: block.raw),
          ],
        ),
      ),
      finishReason: _finishReason(value.stopReason),
      nativeFinishReason: value.stopReason,
      usage: usage,
      responseId: value.id,
      requestId: response.metadata.requestId,
      nativePayload: response.payload,
      metadata: response.metadata,
    );
  }
}

Effect<NativeResponse<AnthropicMessage>, AiError> _decodeMessage(
  NativeResponse<JsonObject> response,
) {
  try {
    return Effect.succeed(
      NativeResponse(
        value: AnthropicMessage.fromJson(response.value),
        payload: response.payload,
        metadata: response.metadata,
      ),
    );
  } on FormatException catch (error) {
    return Effect.fail(ProtocolError(error.message));
  }
}

final class _AnthropicNativeProtocol implements SseProtocol<AnthropicMessageEvent> {
  var _terminal = false;
  ResponseMetadata? _metadata;

  @override
  bool get isTerminal => _terminal;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<AnthropicMessageEvent> start(ResponseMetadata metadata) {
    _metadata = metadata;
    return const [];
  }

  @override
  Iterable<AnthropicMessageEvent> decode(SseEvent event) {
    final decoded = _decodeEvent(event);
    if (decoded case AnthropicErrorEvent(:final error)) {
      throw _streamError(error, _metadata);
    }
    if (decoded is AnthropicMessageStopEvent) _terminal = true;
    return [decoded];
  }

  @override
  Iterable<AnthropicMessageEvent> finish() {
    if (!_terminal) {
      throw const ProtocolError('Messages stream ended before message_stop.');
    }
    return const [];
  }
}

final class _AnthropicCommonProtocol implements SseProtocol<GenerationEvent> {
  _AnthropicCommonProtocol(this.modelId, {required int maxAssembledBytes})
    : assembler = GenerationStreamAssembler(
        providerId: _providerId,
        api: _api,
        modelId: modelId,
        maxAssembledBytes: maxAssembledBytes,
      );

  final String modelId;
  final GenerationStreamAssembler assembler;
  final Map<int, StringBuffer> _text = {};
  final Map<int, JsonObject> _startedBlocks = {};
  final List<ReplayItem> _unknownEvents = [];
  AnthropicMessage? _startMessage;
  AnthropicMessageDeltaEvent? _lastDelta;
  var _terminal = false;

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
      case AnthropicMessageStartEvent(:final message):
        _startMessage = message;
        assembler.setResponseId(message.id);
        yield assembler.updateUsage(_commonUsage(message.usage));
      case AnthropicContentBlockStartEvent(:final index, :final contentBlock):
        if (contentBlock is! AnthropicTextBlock) {
          throw ProtocolError(
            'Content block ${contentBlock.type} is not supported by this Messages snapshot.',
            partialOutput: assembler.partialMessage,
          );
        }
        _startedBlocks[index] = contentBlock.raw;
        _text[index] = StringBuffer(contentBlock.text);
        yield assembler.startPart(index: index, kind: GenerationPartKind.text);
      case AnthropicContentBlockDeltaEvent(:final index, :final delta):
        final value = delta.toDart();
        if (value['type'] != 'text_delta' || value['text'] is! String) {
          throw ProtocolError(
            'Content block delta is not valid text.',
            partialOutput: assembler.partialMessage,
          );
        }
        final text = value['text']! as String;
        final buffer = _text[index];
        if (buffer == null) {
          throw ProtocolError(
            'Text delta arrived before block start.',
            partialOutput: partialOutput,
          );
        }
        buffer.write(text);
        yield assembler.appendText(index, text);
      case AnthropicContentBlockStopEvent(:final index):
        final buffer = _text[index];
        final start = _startedBlocks[index];
        if (buffer == null || start == null) {
          throw ProtocolError(
            'Content block stopped before it started.',
            partialOutput: partialOutput,
          );
        }
        final raw = JsonObject({...start.toDart(), 'text': buffer.toString()});
        yield assembler.finishPart(index, _commonPart(AnthropicContentBlock.fromJson(raw)));
      case AnthropicMessageDeltaEvent():
        _lastDelta = decoded;
        final start = _startMessage;
        yield assembler.updateUsage(
          Usage(
            inputTokens: decoded.usage.inputTokens ?? start?.usage.inputTokens,
            outputTokens: decoded.usage.outputTokens,
            totalTokens: _sum(
              decoded.usage.inputTokens ?? start?.usage.inputTokens,
              decoded.usage.outputTokens,
            ),
          ),
        );
      case AnthropicMessageStopEvent():
        _terminal = true;
      case AnthropicPingEvent():
        yield assembler.providerEvent(decoded.type, decoded.raw);
      case AnthropicUnknownMessageEvent():
        _unknownEvents.add(ReplayItem(phase: 'unknown-event', data: decoded.raw));
        yield assembler.providerEvent(decoded.type, decoded.raw);
      case AnthropicErrorEvent(:final error):
        throw _streamError(error, null, partialOutput: partialOutput);
    }
  }

  @override
  Iterable<GenerationEvent> finish() sync* {
    if (!_terminal) {
      throw ProtocolError(
        'Messages stream ended before message_stop.',
        partialOutput: partialOutput,
      );
    }
    final start = _startMessage;
    final delta = _lastDelta;
    if (start == null || delta == null) {
      throw ProtocolError(
        'Messages stream omitted required message state.',
        partialOutput: partialOutput,
      );
    }
    final deltaValue = delta.delta.toDart();
    final content = <Object?>[
      for (final index in (_startedBlocks.keys.toList()..sort()))
        {..._startedBlocks[index]!.toDart(), 'text': _text[index].toString()},
    ];
    final native = JsonObject({
      ...start.raw.toDart(),
      'content': content,
      'stop_reason': deltaValue['stop_reason'],
      'stop_sequence': deltaValue['stop_sequence'],
      if (deltaValue.containsKey('stop_details')) 'stop_details': deltaValue['stop_details'],
      'usage': {
        ...start.usage.raw.toDart(),
        ...delta.usage.raw.toDart(),
      },
    });
    yield assembler.finish(
      finishReason: _finishReason(deltaValue['stop_reason'] as String?),
      nativeFinishReason: deltaValue['stop_reason'] as String?,
      nativeResponse: native,
      replay: [
        for (final block in content) ReplayItem(data: JsonObject.fromDart(block)),
        ..._unknownEvents,
      ],
    );
  }
}

AnthropicMessageEvent _decodeEvent(SseEvent event) {
  try {
    return AnthropicMessageEvent.fromJson(JsonObject.parse(event.data));
  } on FormatException catch (error) {
    throw ProtocolError(error.message);
  }
}

ProviderError _streamError(
  JsonObject error,
  ResponseMetadata? metadata, {
  Object? partialOutput,
}) {
  final value = error.toDart();
  return ProviderError(
    value['message'] is String ? value['message']! as String : 'Anthropic stream failed.',
    code: value['type'] as String?,
    details: error,
    requestId: metadata?.requestId,
    partialOutput: partialOutput,
  );
}

Usage _commonUsage(AnthropicUsage usage) => Usage(
  inputTokens: usage.inputTokens,
  outputTokens: usage.outputTokens,
  totalTokens: _sum(usage.inputTokens, usage.outputTokens),
);

int? _sum(int? left, int? right) => left == null || right == null ? null : left + right;

OutputPart _commonPart(AnthropicContentBlock block) => switch (block) {
  AnthropicTextBlock(:final text, :final citations) => TextOutputPart(
    text,
    citations: (citations ?? const []).map(
      (citation) => Citation(
        uri: Uri.parse(
          (citation.toDart()['url'] as String?) ??
              'anthropic://citation/${Uri.encodeComponent(citation.encode())}',
        ),
        title: citation.toDart()['title'] as String?,
        documentReference:
            citation.toDart()['document_id'] as String? ?? citation.toDart()['file_id'] as String?,
        nativeMetadata: citation,
      ),
    ),
  ),
  AnthropicUnknownContentBlock() => OpaqueOutputPart(
    providerId: _providerId,
    api: _api,
    kind: block.type,
    data: block.raw,
  ),
};

FinishReason _finishReason(String? reason) => switch (reason) {
  'end_turn' || 'stop_sequence' => FinishReason.stop,
  'max_tokens' || 'model_context_window_exceeded' => FinishReason.outputLimit,
  'tool_use' => FinishReason.toolCalls,
  'pause_turn' => FinishReason.paused,
  'refusal' => FinishReason.refusal,
  _ => FinishReason.other,
};

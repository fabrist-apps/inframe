import 'dart:convert';

import 'package:artificer_anthropic/src/messages/message_models.dart';
import 'package:artificer_anthropic/src/messages/token_models.dart';
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

  /// Counts input tokens for the supplied native Messages fields.
  Effect<NativeResponse<AnthropicMessageTokensCount>, AiError> countTokens(
    AnthropicMessageTokensRequest request,
  ) => _client
      .sendJson(
        ProviderHttpRequest(
          method: 'POST',
          path: 'messages/count_tokens',
          headers: _betaHeaders(request.betaFeatures),
          body: request.toJson(),
        ),
        providerId: _providerId,
        api: 'messages.count_tokens',
        modelId: request.model,
      )
      .flatMap(_decodeTokenCount);

  /// Creates one native Message.
  Effect<NativeResponse<AnthropicMessage>, AiError> create(AnthropicMessageRequest request) =>
      _client
          .sendJson(
            ProviderHttpRequest(
              method: 'POST',
              path: 'messages',
              headers: _betaHeaders(request.betaFeatures),
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
      headers: _betaHeaders(request.betaFeatures),
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
      headers: _betaHeaders(request.betaFeatures),
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
    final parts = value.content.map(_commonPart).toList();
    if (value.stopReason == 'refusal' && value.stopDetails != null) {
      parts.add(_refusalPart(value.stopDetails!));
    }
    return GenerationResult(
      message: AssistantMessage(
        parts,
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

Map<String, String> _betaHeaders(List<String> betaFeatures) => {
  if (betaFeatures.isNotEmpty) 'anthropic-beta': betaFeatures.join(','),
};

Effect<NativeResponse<AnthropicMessageTokensCount>, AiError> _decodeTokenCount(
  NativeResponse<JsonObject> response,
) {
  try {
    return Effect.succeed(
      NativeResponse(
        value: AnthropicMessageTokensCount.fromJson(response.value),
        payload: response.payload,
        metadata: response.metadata,
      ),
    );
  } on FormatException catch (error) {
    return Effect.fail(ProtocolError(error.message));
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
    : _maxAssembledBytes = maxAssembledBytes,
      assembler = GenerationStreamAssembler(
        providerId: _providerId,
        api: _api,
        modelId: modelId,
        maxAssembledBytes: maxAssembledBytes,
      );

  final String modelId;
  final int _maxAssembledBytes;
  final GenerationStreamAssembler assembler;
  final Map<int, _AnthropicBlockAssembly> _blocks = {};
  final List<ReplayItem> _unknownEvents = [];
  AnthropicMessage? _startMessage;
  AnthropicMessageDeltaEvent? _lastDelta;
  ResponseMetadata? _metadata;
  var _terminal = false;

  @override
  bool get isTerminal => _terminal;

  @override
  Object? get partialOutput => assembler.partialMessage;

  @override
  Iterable<GenerationEvent> start(ResponseMetadata metadata) {
    _metadata = metadata;
    return [assembler.start(metadata)];
  }

  @override
  Iterable<GenerationEvent> decode(SseEvent event) sync* {
    final decoded = _decodeEvent(event);
    switch (decoded) {
      case AnthropicMessageStartEvent(:final message):
        if (_startMessage != null || _blocks.isNotEmpty || _lastDelta != null) {
          throw ProtocolError(
            'message_start arrived after message state was initialized.',
            partialOutput: partialOutput,
          );
        }
        _startMessage = message;
        assembler.setResponseId(message.id);
        yield assembler.updateUsage(_commonUsage(message.usage));
      case AnthropicContentBlockStartEvent(:final index, :final contentBlock):
        if (_startMessage == null) {
          throw ProtocolError(
            'Content block started before message_start.',
            partialOutput: partialOutput,
          );
        }
        if (_blocks.containsKey(index)) {
          throw ProtocolError(
            'Content block $index started more than once.',
            partialOutput: partialOutput,
          );
        }
        final block = _AnthropicBlockAssembly(contentBlock);
        _blocks[index] = block;
        yield assembler.startPart(
          index: index,
          kind: block.kind,
          owner: block.owner,
        );
      case AnthropicContentBlockDeltaEvent(:final index, :final delta):
        final block = _blocks[index];
        if (block == null || block.finished) {
          throw ProtocolError(
            'Content block delta arrived outside an open block.',
            partialOutput: partialOutput,
          );
        }
        final value = delta.toDart();
        switch (value['type']) {
          case 'text_delta':
            final text = _deltaString(value, 'text', partialOutput);
            block.appendText(text, expectedType: 'text', partialOutput: partialOutput);
            yield assembler.appendText(index, text);
          case 'thinking_delta':
            final text = _deltaString(value, 'thinking', partialOutput);
            block.appendText(text, expectedType: 'thinking', partialOutput: partialOutput);
            yield assembler.appendText(index, text);
          case 'signature_delta':
            block.appendSignature(
              _deltaString(value, 'signature', partialOutput),
              partialOutput: partialOutput,
            );
            yield assembler.providerEvent('signature_delta', delta);
          case 'citations_delta':
            try {
              block.appendCitation(
                JsonObject.fromDart(value['citation']),
                partialOutput: partialOutput,
              );
            } on FormatException catch (error) {
              throw ProtocolError(error.message, partialOutput: partialOutput);
            }
            yield assembler.providerEvent('citations_delta', delta);
          case 'input_json_delta':
            final fragment = _deltaString(value, 'partial_json', partialOutput);
            block.appendInput(fragment, partialOutput: partialOutput);
            if (block.kind == GenerationPartKind.applicationToolCall) {
              yield assembler.appendText(index, fragment);
            } else {
              yield assembler.appendOpaque(index, delta);
            }
          default:
            throw ProtocolError(
              'Unknown content block delta ${value['type']}.',
              partialOutput: partialOutput,
            );
        }
      case AnthropicContentBlockStopEvent(:final index):
        final block = _blocks[index];
        if (block == null || block.finished) {
          throw ProtocolError(
            'Content block stopped outside an open block.',
            partialOutput: partialOutput,
          );
        }
        block.finished = true;
        yield assembler.finishPart(
          index,
          _commonPart(
            block.finish(),
            malformedInputIssue: block.inputIssue,
          ),
        );
      case AnthropicMessageDeltaEvent():
        if (_startMessage == null) {
          throw ProtocolError(
            'message_delta arrived before message_start.',
            partialOutput: partialOutput,
          );
        }
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
        if (_startMessage == null || _lastDelta == null) {
          throw ProtocolError(
            'message_stop arrived before required message state.',
            partialOutput: partialOutput,
          );
        }
        _terminal = true;
      case AnthropicPingEvent():
        yield assembler.providerEvent(decoded.type, decoded.raw);
      case AnthropicUnknownMessageEvent():
        _unknownEvents.add(ReplayItem(phase: 'unknown-event', data: decoded.raw));
        yield assembler.providerEvent(decoded.type, decoded.raw);
      case AnthropicErrorEvent(:final error):
        throw _streamError(error, _metadata, partialOutput: partialOutput);
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
    final orderedBlocks = _blocks.keys.toList()..sort();
    final content = <Object?>[
      for (final index in orderedBlocks) _blocks[index]!.finish().toDart(),
    ];
    final native = JsonObject({
      ...start.raw.toDart(),
      'content': content,
      ...deltaValue,
      'usage': {
        ...start.usage.raw.toDart(),
        ...delta.usage.raw.toDart(),
      },
    });
    final retainedBytes =
        utf8.encode(native.encode()).length +
        _unknownEvents.fold<int>(
          0,
          (total, item) => total + utf8.encode(item.data.encode()).length,
        );
    if (retainedBytes > _maxAssembledBytes) {
      throw ResponseLimitError(
        'The assembled native response and retained events exceeded the configured byte limit.',
        limit: _maxAssembledBytes,
        actual: retainedBytes,
        partialOutput: partialOutput,
      );
    }
    if (deltaValue['stop_reason'] == 'refusal') {
      if (deltaValue['stop_details'] case final Map<String, Object?> details) {
        final index = orderedBlocks.isEmpty ? 0 : orderedBlocks.last + 1;
        final refusal = _refusalPart(JsonObject(details));
        yield assembler.startPart(index: index, kind: GenerationPartKind.refusal);
        yield assembler.finishPart(index, refusal);
      }
    }
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

final class _AnthropicBlockAssembly {
  _AnthropicBlockAssembly(this.start)
    : _text = StringBuffer(
        switch (start) {
          AnthropicTextBlock(:final text) => text,
          AnthropicThinkingBlock(:final thinking) => thinking,
          _ => '',
        },
      ),
      _signature = StringBuffer(
        start is AnthropicThinkingBlock ? start.signature : '',
      ),
      _citations = switch (start) {
        AnthropicTextBlock(:final citations?) => citations.toList(),
        _ => <JsonObject>[],
      };

  final AnthropicContentBlock start;
  final StringBuffer _text;
  final StringBuffer _signature;
  final List<JsonObject> _citations;
  final StringBuffer _input = StringBuffer();
  var _hasInputDelta = false;
  bool finished = false;
  String? inputIssue;

  GenerationPartKind get kind => switch (_commonPart(start)) {
    TextOutputPart() => GenerationPartKind.text,
    ReasoningSummaryPart() => GenerationPartKind.reasoning,
    RefusalPart() => GenerationPartKind.refusal,
    ApplicationToolCallPart() => GenerationPartKind.applicationToolCall,
    ProviderToolRecordPart() => GenerationPartKind.providerTool,
    OpaqueOutputPart() => GenerationPartKind.opaque,
  };

  GenerationPartOwner get owner => switch (kind) {
    GenerationPartKind.providerTool ||
    GenerationPartKind.reasoning ||
    GenerationPartKind.opaque => GenerationPartOwner.provider,
    _ => GenerationPartOwner.application,
  };

  void appendText(
    String value, {
    required String expectedType,
    required Object? partialOutput,
  }) {
    if (start.type != expectedType) {
      throw ProtocolError(
        '$expectedType delta does not match ${start.type} block.',
        partialOutput: partialOutput,
      );
    }
    _text.write(value);
  }

  void appendSignature(String value, {required Object? partialOutput}) {
    if (start is! AnthropicThinkingBlock) {
      throw ProtocolError(
        'signature delta does not match ${start.type} block.',
        partialOutput: partialOutput,
      );
    }
    _signature.write(value);
  }

  void appendCitation(JsonObject value, {required Object? partialOutput}) {
    if (start is! AnthropicTextBlock) {
      throw ProtocolError(
        'citation delta does not match ${start.type} block.',
        partialOutput: partialOutput,
      );
    }
    _citations.add(value);
  }

  void appendInput(String value, {required Object? partialOutput}) {
    if (start is! AnthropicToolUseBlock && start is! AnthropicServerToolUseBlock) {
      throw ProtocolError(
        'input JSON delta does not match ${start.type} block.',
        partialOutput: partialOutput,
      );
    }
    _hasInputDelta = true;
    _input.write(value);
  }

  AnthropicContentBlock finish() {
    final raw = start.raw.toDart();
    final complete = switch (start) {
      AnthropicTextBlock(:final citations) => {
        ...raw,
        'text': _text.toString(),
        if (_citations.isNotEmpty)
          'citations': _citations.map((citation) => citation.toDart()).toList()
        else if (citations == null)
          'citations': null,
      },
      AnthropicThinkingBlock() => {
        ...raw,
        'thinking': _text.toString(),
        'signature': _signature.toString(),
      },
      AnthropicToolUseBlock() || AnthropicServerToolUseBlock() when _hasInputDelta => {
        ...raw,
        'input': _decodedInput(),
      },
      _ => raw,
    };
    return AnthropicContentBlock.fromJson(JsonObject(complete));
  }

  Object? _decodedInput() {
    final source = _input.toString();
    try {
      return JsonValue.parse(source).toDart();
    } on FormatException catch (error) {
      inputIssue = error.message;
      return source;
    }
  }
}

String _deltaString(Map<String, Object?> value, String field, Object? partialOutput) {
  final result = value[field];
  if (result is! String) {
    throw ProtocolError('$field must be a string.', partialOutput: partialOutput);
  }
  return result;
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

OutputPart _commonPart(
  AnthropicContentBlock block, {
  String? malformedInputIssue,
}) => switch (block) {
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
  AnthropicToolUseBlock(:final id, :final name, :final input) => ApplicationToolCallPart(
    id: id,
    name: name,
    arguments: input is JsonObject
        ? _callerNativeToolNames.contains(name)
              ? NativeToolArguments(providerId: _providerId, api: _api, action: input)
              : JsonToolArguments(input, originalText: input.encode())
        : MalformedToolArguments(
            originalText: input is JsonString ? input.value : input.encode(),
            issue: malformedInputIssue ?? 'Anthropic client-tool input must be a JSON object.',
          ),
  ),
  AnthropicThinkingBlock(:final thinking) => ReasoningSummaryPart(thinking),
  AnthropicRedactedThinkingBlock() => OpaqueOutputPart(
    providerId: _providerId,
    api: _api,
    kind: block.type,
    data: block.raw,
  ),
  AnthropicServerToolUseBlock(:final id, :final name) => ProviderToolRecordPart(
    id: id,
    name: name,
    owner: ToolExecutionOwner.provider,
    status: _providerToolStatus(block.raw, fallback: ProviderToolStatus.pending),
    details: block.raw,
  ),
  AnthropicProviderToolResultBlock(:final toolUseId) => ProviderToolRecordPart(
    id: toolUseId,
    name: _providerResultName(block.type),
    owner: ToolExecutionOwner.provider,
    status: _providerToolStatus(block.raw, fallback: _providerResultStatus(block)),
    details: block.raw,
  ),
  AnthropicImageBlock() ||
  AnthropicDocumentBlock() ||
  AnthropicToolResultBlock() ||
  AnthropicUnknownContentBlock() => OpaqueOutputPart(
    providerId: _providerId,
    api: _api,
    kind: block.type,
    data: block.raw,
  ),
};

RefusalPart _refusalPart(JsonObject details) {
  final raw = details.toDart();
  return RefusalPart(
    raw['message'] as String? ?? raw['reason'] as String? ?? details.encode(),
  );
}

ProviderToolStatus _providerToolStatus(
  JsonObject raw, {
  required ProviderToolStatus fallback,
}) => switch (raw.toDart()['status']) {
  'pending' => ProviderToolStatus.pending,
  'running' => ProviderToolStatus.running,
  'completed' => ProviderToolStatus.completed,
  'failed' => ProviderToolStatus.failed,
  null => fallback,
  _ => ProviderToolStatus.unknown,
};

ProviderToolStatus _providerResultStatus(AnthropicProviderToolResultBlock block) {
  final content = block.content.toDart();
  if (content case final Map<String, Object?> value) {
    if (value['type'] case final String type when type.endsWith('_error')) {
      return ProviderToolStatus.failed;
    }
  }
  return ProviderToolStatus.completed;
}

String _providerResultName(String type) => switch (type) {
  'web_search_tool_result' => 'web_search',
  'web_fetch_tool_result' => 'web_fetch',
  'code_execution_tool_result' => 'code_execution',
  'bash_code_execution_tool_result' => 'bash_code_execution',
  'text_editor_code_execution_tool_result' => 'text_editor_code_execution',
  'tool_search_tool_result' => 'tool_search',
  _ => type,
};

const _callerNativeToolNames = {
  'computer',
  'bash',
  'str_replace_based_edit_tool',
  'memory',
};

FinishReason _finishReason(String? reason) => switch (reason) {
  'end_turn' || 'stop_sequence' => FinishReason.stop,
  'max_tokens' || 'model_context_window_exceeded' => FinishReason.outputLimit,
  'tool_use' => FinishReason.toolCalls,
  'pause_turn' => FinishReason.paused,
  'refusal' => FinishReason.refusal,
  _ => FinishReason.other,
};

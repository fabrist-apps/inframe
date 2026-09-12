import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:artificer_google/src/generate_content/tool_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'google';
const _api = 'generateContent';

/// Typed native GenerateContent operations and common response normalization.
final class GoogleGenerateContentResource {
  /// Creates the resource over one provider-owned core client.
  const GoogleGenerateContentResource(this._client);

  final ProviderHttpClient _client;

  /// Runs one native GenerateContent inference attempt.
  Effect<NativeResponse<GoogleGenerateContentResponse>, AiError> create(
    GoogleGenerateContentRequest request,
  ) {
    final modelId = _modelId(request.model);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1beta/models/${Uri.encodeComponent(modelId)}:generateContent',
            body: request.toJson(),
          ),
          providerId: _providerId,
          api: _api,
          modelId: modelId,
        )
        .flatMap(
          (response) => _decodeTyped(
            response,
            GoogleGenerateContentResponse.fromJson,
          ),
        );
  }

  /// Counts tokens in one explicit native request.
  Effect<NativeResponse<GoogleCountTokensResponse>, AiError> countTokens(
    GoogleCountTokensRequest request,
  ) {
    final modelId = _modelId(request.model);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1beta/models/${Uri.encodeComponent(modelId)}:countTokens',
            body: request.toJson(),
          ),
          providerId: _providerId,
          api: _api,
          modelId: modelId,
        )
        .flatMap((response) => _decodeTyped(response, GoogleCountTokensResponse.fromJson));
  }

  /// Streams native GenerateContent response fragments until normal EOF.
  Flow<GoogleGenerateContentChunk, AiError> stream(
    GoogleGenerateContentRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) {
    final modelId = _modelId(request.model);
    return _client.sendSse(
      ProviderHttpRequest(
        method: 'POST',
        path: '/v1beta/models/${Uri.encodeComponent(modelId)}:streamGenerateContent?alt=sse',
        body: request.toJson(),
      ),
      createProtocol: () => _GoogleNativeGenerateContentProtocol(modelId),
      decodedEventCapacity: decodedEventCapacity,
      maxEventBytes: maxEventBytes,
      maxStreamBytes: maxStreamBytes,
    );
  }

  /// Streams common events through the same native response decoder.
  Flow<GenerationEvent, AiError> streamCommon(
    GoogleGenerateContentRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
    int maxAssembledBytes = 64 * 1024 * 1024,
  }) {
    final modelId = _modelId(request.model);
    return _client.sendSse(
      ProviderHttpRequest(
        method: 'POST',
        path: '/v1beta/models/${Uri.encodeComponent(modelId)}:streamGenerateContent?alt=sse',
        body: request.toJson(),
      ),
      createProtocol: () => _GoogleCommonGenerateContentProtocol(
        modelId,
        request: request,
        maxAssembledBytes: maxAssembledBytes,
      ),
      decodedEventCapacity: decodedEventCapacity,
      maxEventBytes: maxEventBytes,
      maxStreamBytes: maxStreamBytes,
    );
  }

  /// Normalizes an already-decoded response without issuing another request.
  GenerationResult normalize(
    NativeResponse<GoogleGenerateContentResponse> response, {
    int? candidateIndex,
    GoogleGenerateContentRequest? request,
  }) {
    final value = response.value;
    if (value.candidates.length > 1 && candidateIndex == null) {
      throw const InvalidRequestError(
        'A candidateIndex is required to normalize multiple Google candidates.',
      );
    }
    if (value.candidates.isEmpty) {
      final blockReason = value.promptFeedback?.blockReason;
      if (!_isBlocked(blockReason)) {
        throw const ProtocolError('Google returned neither a candidate nor prompt feedback.');
      }
      return _result(
        response,
        parts: [RefusalPart('Google blocked the prompt ($blockReason).')],
        finishReason: FinishReason.contentFilter,
        nativeFinishReason: blockReason,
        replay: [ReplayItem(phase: 'prompt-feedback', data: value.promptFeedback!.raw)],
      );
    }
    final selected = candidateIndex ?? 0;
    if (selected < 0 || selected >= value.candidates.length) {
      throw ArgumentError.value(candidateIndex, 'candidateIndex', 'is outside the candidate page');
    }
    final candidate = value.candidates[selected];
    final content = candidate.content;
    final citations = _citations(candidate.extensions);
    final requestTools = request?.tools ?? const <GoogleToolDefinition>[];
    final callerFunctionNames = requestTools.expand((tool) => tool.functionNames).toSet();
    final allowsComputerUse = requestTools.any((tool) => tool is GoogleComputerUseTool);
    var callIndex = 0;
    final parts = <OutputPart>[];
    if (content != null) {
      for (final part in content.parts) {
        final normalized = _normalizePart(
          part,
          index: parts.length,
          callIndex: callIndex,
          citations: parts.whereType<TextOutputPart>().isEmpty ? citations : const [],
          callerFunctionNames: callerFunctionNames,
          allowsComputerUse: allowsComputerUse,
        );
        if (part.functionCall != null) callIndex++;
        if (normalized != null) parts.add(normalized);
      }
    }
    return _result(
      response,
      parts: parts,
      finishReason: _finishReason(candidate.finishReason),
      nativeFinishReason: candidate.finishReason,
      replay: [
        if (content != null) ReplayItem(phase: 'content', data: content.toJson()),
        ReplayItem(phase: 'candidate-metadata', data: candidate.raw),
      ],
    );
  }

  GenerationResult _result(
    NativeResponse<GoogleGenerateContentResponse> response, {
    required Iterable<OutputPart> parts,
    required FinishReason finishReason,
    required String? nativeFinishReason,
    required Iterable<ReplayItem> replay,
  }) => GenerationResult(
    message: AssistantMessage(
      parts,
      replay: ProviderReplay(
        providerId: _providerId,
        api: _api,
        modelId: response.payload.modelId,
        items: replay,
      ),
    ),
    finishReason: finishReason,
    nativeFinishReason: nativeFinishReason,
    usage: response.value.usageMetadata?.toCommon(),
    responseId: response.value.responseId,
    requestId: response.metadata.requestId,
    nativePayload: response.payload,
    metadata: response.metadata,
  );
}

OutputPart? _normalizePart(
  GooglePart part, {
  required int index,
  required int callIndex,
  required List<Citation> citations,
  required Set<String> callerFunctionNames,
  required bool allowsComputerUse,
}) {
  if (part.text case final text?) {
    if (text.isEmpty && part.thoughtSignature != null) return null;
    return part.thought == true
        ? ReasoningSummaryPart(text)
        : TextOutputPart(text, citations: citations);
  }
  if (part.functionCall case final call?) {
    final isApplicationFunction = callerFunctionNames.contains(call.name);
    if (!isApplicationFunction && !allowsComputerUse) {
      return OpaqueOutputPart(
        providerId: _providerId,
        api: _api,
        kind: 'unclassified-function-call',
        data: part.toJson(),
      );
    }
    return ApplicationToolCallPart(
      id: call.id ?? 'google-call-$callIndex',
      name: call.name,
      arguments: isApplicationFunction
          ? call.rawArgs.toDart() is Map<String, Object?>
                ? JsonToolArguments(call.args)
                : MalformedToolArguments(
                    originalText: call.rawArgs.encode(),
                    issue: 'Google functionCall.args must be a JSON object.',
                  )
          : NativeToolArguments(
              providerId: _providerId,
              api: _api,
              action: part.toJson(),
            ),
    );
  }
  final providerActivity =
      part.executableCode ?? part.codeExecutionResult ?? part.toolCall ?? part.toolResponse;
  if (providerActivity != null) {
    final name = switch ((part.executableCode, part.codeExecutionResult, part.toolCall)) {
      (final value?, _, _) => value.toDart()['language']?.toString() ?? 'code_execution',
      (_, final value?, _) => value.toDart()['outcome']?.toString() ?? 'code_execution_result',
      (_, _, final value?) => value.toDart()['toolType']?.toString() ?? 'hosted_tool',
      _ => 'hosted_tool_result',
    };
    return ProviderToolRecordPart(
      id: 'google-provider-$index',
      name: name,
      owner: ToolExecutionOwner.provider,
      status: part.executableCode != null || part.toolCall != null
          ? ProviderToolStatus.running
          : ProviderToolStatus.completed,
      details: part.toJson(),
    );
  }
  return OpaqueOutputPart(
    providerId: _providerId,
    api: _api,
    kind: 'part',
    data: part.toJson(),
  );
}

List<Citation> _citations(JsonObject extensions) {
  final metadata = extensions.toDart()['groundingMetadata'];
  if (metadata is! Map<String, Object?>) return const [];
  final chunks = metadata['groundingChunks'];
  if (chunks is! List<Object?>) return const [];
  final citations = <Citation>[];
  for (final chunk in chunks.whereType<Map<String, Object?>>()) {
    final web = chunk['web'];
    if (web is! Map<String, Object?>) continue;
    final uriValue = web['uri'];
    if (uriValue is! String) continue;
    final uri = Uri.tryParse(uriValue);
    if (uri == null || !uri.isAbsolute) continue;
    citations.add(
      Citation(
        uri: uri,
        title: web['title'] as String?,
        nativeMetadata: JsonObject(chunk),
      ),
    );
  }
  return List.unmodifiable(citations);
}

Effect<NativeResponse<T>, AiError> _decodeTyped<T>(
  NativeResponse<JsonObject> response,
  T Function(JsonObject) decode,
) {
  try {
    _throwServiceError(response.value, response.metadata);
    return Effect.succeed(
      NativeResponse(
        value: decode(response.value),
        payload: response.payload,
        metadata: response.metadata,
      ),
    );
  } on AiError catch (error) {
    return Effect.fail(error);
  } on FormatException catch (error) {
    return Effect.fail(ProtocolError(error.message));
  }
}

final class _GoogleNativeGenerateContentProtocol
    implements SseProtocol<GoogleGenerateContentChunk> {
  _GoogleNativeGenerateContentProtocol(this.modelId);

  final String modelId;
  final List<GoogleGenerateContentChunk> _chunks = [];
  late ResponseMetadata _metadata;
  var _terminal = false;

  // Google may send usage after finish metadata, so transport must read normal EOF.
  @override
  bool get isTerminal => false;

  @override
  Object? get partialOutput => List<GoogleGenerateContentChunk>.unmodifiable(_chunks);

  @override
  Iterable<GoogleGenerateContentChunk> start(ResponseMetadata metadata) {
    _metadata = metadata;
    return const [];
  }

  @override
  Iterable<GoogleGenerateContentChunk> decode(SseEvent event) {
    final raw = _decodeEvent(event);
    final metadata = _metadata;
    _throwServiceError(
      raw,
      metadata,
      partialOutput: List<GoogleGenerateContentChunk>.unmodifiable(_chunks),
    );
    final value = GoogleGenerateContentResponse.fromJson(raw);
    _terminal = _terminal || _isTerminal(value);
    final chunk = GoogleGenerateContentChunk(
      value: value,
      payload: NativePayload(
        providerId: _providerId,
        api: _api,
        modelId: modelId,
        json: raw,
      ),
      metadata: metadata,
      event: event.event,
      eventId: event.id,
      retry: event.retry,
    );
    _chunks.add(chunk);
    return [chunk];
  }

  @override
  Iterable<GoogleGenerateContentChunk> finish() {
    if (!_terminal) {
      throw const ProtocolError(
        'Google stream ended before candidate finish metadata or a blocked response.',
      );
    }
    return const [];
  }
}

final class _GoogleCommonGenerateContentProtocol implements SseProtocol<GenerationEvent> {
  _GoogleCommonGenerateContentProtocol(
    this.modelId, {
    required GoogleGenerateContentRequest request,
    required int maxAssembledBytes,
  }) : callerFunctionNames =
           request.tools?.expand((tool) => tool.functionNames).toSet() ?? const {},
       allowsComputerUse = request.tools?.any((tool) => tool is GoogleComputerUseTool) ?? false,
       assembler = GenerationStreamAssembler(
         providerId: _providerId,
         api: _api,
         modelId: modelId,
         maxAssembledBytes: maxAssembledBytes,
       );

  final String modelId;
  final Set<String> callerFunctionNames;
  final bool allowsComputerUse;
  final GenerationStreamAssembler assembler;
  final List<JsonObject> _rawChunks = [];
  final List<ReplayItem> _nativeEventReplay = [];
  final List<_GoogleStreamPart> _parts = [];
  final Map<String, Object?> _candidateMetadata = {};
  JsonObject? _promptFeedback;
  List<Citation> _latestCitations = const [];
  String? _finish;
  String? _blocked;
  String? _responseId;
  String? _modelVersion;
  String? _contentRole;
  late ResponseMetadata _streamMetadata;

  // Finish metadata is necessary but normal EOF is also part of success.
  @override
  bool get isTerminal => false;

  @override
  Object? get partialOutput => assembler.partialMessage;

  @override
  Iterable<GenerationEvent> start(ResponseMetadata metadata) {
    _streamMetadata = metadata;
    return [assembler.start(metadata)];
  }

  @override
  Iterable<GenerationEvent> decode(SseEvent event) sync* {
    final raw = _decodeEvent(event);
    _throwServiceError(raw, _streamMetadata, partialOutput: assembler.partialMessage);
    final value = GoogleGenerateContentResponse.fromJson(raw);
    _rawChunks.add(raw);
    if (event.event case final name? when name != 'message') {
      final envelope = _sseEnvelope(event, raw);
      _nativeEventReplay.add(ReplayItem(phase: 'sse-event', data: envelope));
      yield assembler.providerEvent(name, envelope);
    }
    if (value.responseId case final responseId?) {
      if (_responseId != null && _responseId != responseId) {
        throw ProtocolError(
          'Google response ID changed during streaming.',
          partialOutput: assembler.partialMessage,
        );
      }
      _responseId = responseId;
      assembler.setResponseId(responseId);
    }
    if (value.modelVersion case final modelVersion?) {
      if (_modelVersion != null && _modelVersion != modelVersion) {
        throw ProtocolError(
          'Google model version changed during streaming.',
          partialOutput: assembler.partialMessage,
        );
      }
      _modelVersion = modelVersion;
    }
    if (value.promptFeedback?.blockReason case final reason? when _isBlocked(reason)) {
      if (value.candidates.isNotEmpty || _parts.isNotEmpty) {
        throw ProtocolError(
          'Google returned prompt blocking after candidate content.',
          partialOutput: assembler.partialMessage,
        );
      }
      _blocked = reason;
      _promptFeedback = value.promptFeedback!.raw;
    }
    if (value.candidates.length > 1) {
      throw ProtocolError(
        'Google returned multiple candidates to a one-candidate common stream.',
        partialOutput: assembler.partialMessage,
      );
    }
    if (value.candidates.isNotEmpty) {
      if (_blocked != null) {
        throw ProtocolError(
          'Google returned candidate content after prompt blocking.',
          partialOutput: assembler.partialMessage,
        );
      }
      final candidate = value.candidates.first;
      if (candidate.index case final index? when index != 0) {
        throw ProtocolError(
          'Google returned candidate $index to a one-candidate common stream.',
          partialOutput: assembler.partialMessage,
        );
      }
      if (_isFinished(candidate.finishReason)) {
        if (_finish != null && _finish != candidate.finishReason) {
          throw ProtocolError(
            'Google candidate finish reason changed during streaming.',
            partialOutput: assembler.partialMessage,
          );
        }
        _finish = candidate.finishReason;
      }
      final metadata = Map<String, Object?>.of(candidate.raw.toDart())..remove('content');
      _candidateMetadata.addAll(metadata);
      if (candidate.content?.role case final role?) {
        if (_contentRole != null && _contentRole != role) {
          throw ProtocolError(
            'Google candidate content role changed during streaming.',
            partialOutput: assembler.partialMessage,
          );
        }
        _contentRole = role;
      }
      final currentCitations = _citations(candidate.extensions);
      if (currentCitations.isNotEmpty) _latestCitations = currentCitations;
      final nativeParts = candidate.content?.parts ?? const <GooglePart>[];
      for (final (chunkIndex, part) in nativeParts.indexed) {
        final canContinue = chunkIndex == 0 && _parts.isNotEmpty && _parts.last.canContinue(part);
        late final _GoogleStreamPart streamPart;
        if (canContinue) {
          streamPart = _parts.last;
        } else {
          final index = _parts.length;
          streamPart = _GoogleStreamPart(index, part);
          _parts.add(streamPart);
          final kind = _partKind(
            part,
            callerFunctionNames: callerFunctionNames,
            allowsComputerUse: allowsComputerUse,
          );
          yield assembler.startPart(
            index: index,
            kind: kind,
            owner: kind == GenerationPartKind.providerTool || kind == GenerationPartKind.opaque
                ? GenerationPartOwner.provider
                : GenerationPartOwner.application,
          );
        }
        streamPart.add(part);
        if (part.text case final delta? when delta.isNotEmpty) {
          yield assembler.appendText(streamPart.index, delta);
        } else if (streamPart.acceptsOpaqueDelta) {
          yield assembler.appendOpaque(streamPart.index, part.toJson());
        }
      }
    }
    if (value.usageMetadata case final usage?) {
      yield assembler.updateUsage(usage.toCommon());
    }
  }

  @override
  Iterable<GenerationEvent> finish() sync* {
    if (_finish == null && _blocked == null) {
      throw ProtocolError(
        'Google stream ended before candidate finish metadata or a blocked response.',
        partialOutput: assembler.partialMessage,
      );
    }
    var callIndex = 0;
    var citationsAttached = false;
    for (final streamPart in _parts) {
      final part = streamPart.value;
      final normalized = _normalizePart(
        part,
        index: streamPart.index,
        callIndex: callIndex,
        citations: citationsAttached ? const [] : _latestCitations,
        callerFunctionNames: callerFunctionNames,
        allowsComputerUse: allowsComputerUse,
      );
      if (part.functionCall != null) callIndex++;
      final output =
          normalized ??
          OpaqueOutputPart(
            providerId: _providerId,
            api: _api,
            kind: 'part-metadata',
            data: part.toJson(),
          );
      if (output is TextOutputPart) citationsAttached = true;
      yield assembler.finishPart(streamPart.index, output);
    }
    if (_blocked case final reason?) {
      final index = _parts.length;
      yield assembler.startPart(index: index, kind: GenerationPartKind.refusal);
      yield assembler.finishPart(index, RefusalPart('Google blocked the prompt ($reason).'));
    }
    final assembledContent = _parts.isEmpty
        ? null
        : GoogleContent(
            role: _contentRole ?? 'model',
            parts: _parts.map((part) => part.value),
          );
    final assembledCandidate = assembledContent == null
        ? null
        : JsonObject({
            ..._candidateMetadata,
            'content': assembledContent.toJson().toDart(),
          });
    yield assembler.finish(
      finishReason: _blocked == null ? _finishReason(_finish) : FinishReason.contentFilter,
      nativeFinishReason: _blocked ?? _finish,
      nativeResponse: JsonObject({
        'chunks': _rawChunks.map((chunk) => chunk.toDart()).toList(),
      }),
      replay: [
        if (assembledContent != null) ReplayItem(phase: 'content', data: assembledContent.toJson()),
        if (assembledCandidate != null)
          ReplayItem(phase: 'candidate-metadata', data: assembledCandidate),
        if (_promptFeedback case final feedback?)
          ReplayItem(phase: 'prompt-feedback', data: feedback),
        ..._nativeEventReplay,
      ],
    );
  }
}

final class _GoogleStreamPart {
  _GoogleStreamPart(this.index, GooglePart first)
    : _kind = _wirePartKind(first),
      _value = <String, Object?>{};

  final int index;
  final String _kind;
  final Map<String, Object?> _value;
  final StringBuffer _text = StringBuffer();

  bool get acceptsOpaqueDelta => _kind != 'text' && _kind != 'functionCall';

  bool canContinue(GooglePart next) {
    if (_kind != _wirePartKind(next)) return false;
    if (_kind == 'text') return value.thought == next.thought;
    return false;
  }

  void add(GooglePart part) {
    final raw = part.toJson().toDart();
    _value.addAll(raw);
    if (part.text case final text?) {
      _text.write(text);
      _value['text'] = _text.toString();
    }
  }

  GooglePart get value => GooglePart.fromJson(JsonObject(_value));
}

String _wirePartKind(GooglePart part) {
  if (part.text != null) return 'text';
  if (part.functionCall != null) return 'functionCall';
  if (part.functionResponse != null) return 'functionResponse';
  if (part.executableCode != null) return 'executableCode';
  if (part.codeExecutionResult != null) return 'codeExecutionResult';
  if (part.toolCall != null) return 'toolCall';
  if (part.toolResponse != null) return 'toolResponse';
  if (part.inlineData != null) return 'inlineData';
  if (part.fileData != null) return 'fileData';
  return 'unknown';
}

GenerationPartKind _partKind(
  GooglePart part, {
  required Set<String> callerFunctionNames,
  required bool allowsComputerUse,
}) {
  if (part.text != null) {
    return part.thought == true ? GenerationPartKind.reasoning : GenerationPartKind.text;
  }
  if (part.functionCall case final call?) {
    return callerFunctionNames.contains(call.name) || allowsComputerUse
        ? GenerationPartKind.applicationToolCall
        : GenerationPartKind.opaque;
  }
  if (part.executableCode != null ||
      part.codeExecutionResult != null ||
      part.toolCall != null ||
      part.toolResponse != null) {
    return GenerationPartKind.providerTool;
  }
  return GenerationPartKind.opaque;
}

JsonObject _sseEnvelope(SseEvent event, JsonObject raw) => JsonObject({
  'event': ?event.event,
  'id': ?event.id,
  if (event.retry case final retry?) 'retryMilliseconds': retry.inMilliseconds,
  'data': raw.toDart(),
});

JsonObject _decodeEvent(SseEvent event) {
  try {
    return JsonObject.parse(event.data);
  } on FormatException catch (error) {
    throw ProtocolError(error.message);
  }
}

void _throwServiceError(
  JsonObject raw,
  ResponseMetadata metadata, {
  Object? partialOutput,
}) {
  final value = raw.toDart();
  final error = value['error'];
  if (error is! Map<String, Object?>) return;
  final message = error['message'];
  final status = error['status'];
  final code = error['code'];
  final retry = metadata.headers['retry-after'];
  throw ProviderError(
    message is String ? message : 'Google returned an error record.',
    statusCode: code is int ? code : metadata.statusCode,
    code: status is String ? status : code?.toString(),
    details: JsonObject(error),
    requestId: metadata.requestId,
    retryAfter: _retryDelay(retry),
    rawRetryAfter: retry,
    partialOutput: partialOutput,
  );
}

bool _isTerminal(GoogleGenerateContentResponse value) =>
    _isBlocked(value.promptFeedback?.blockReason) ||
    value.candidates.any((candidate) => _isFinished(candidate.finishReason));

bool _isBlocked(String? reason) => reason != null && reason != 'BLOCK_REASON_UNSPECIFIED';

bool _isFinished(String? reason) => reason != null && reason != 'FINISH_REASON_UNSPECIFIED';

FinishReason _finishReason(String? reason) => switch (reason) {
  'STOP' => FinishReason.stop,
  'FUNCTION_CALL' => FinishReason.toolCalls,
  'MAX_TOKENS' => FinishReason.outputLimit,
  'SAFETY' ||
  'BLOCKLIST' ||
  'PROHIBITED_CONTENT' ||
  'RECITATION' ||
  'SPII' ||
  'IMAGE_SAFETY' ||
  'IMAGE_PROHIBITED_CONTENT' => FinishReason.contentFilter,
  _ => FinishReason.other,
};

String _modelId(String name) => name.substring('models/'.length);

Duration? _retryDelay(String? value) {
  final seconds = int.tryParse(value ?? '');
  return seconds != null && seconds >= 0 ? Duration(seconds: seconds) : null;
}

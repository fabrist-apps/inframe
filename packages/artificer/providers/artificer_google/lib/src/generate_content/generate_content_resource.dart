import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
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
        .flatMap(_decodeResponse);
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
    final parts = <OutputPart>[
      if (content != null)
        for (final part in content.parts)
          if (part.text case final text?)
            TextOutputPart(text)
          else
            OpaqueOutputPart(
              providerId: _providerId,
              api: _api,
              kind: 'part',
              data: part.toJson(),
            ),
    ];
    return _result(
      response,
      parts: parts,
      finishReason: _finishReason(candidate.finishReason),
      nativeFinishReason: candidate.finishReason,
      replay: [ReplayItem(phase: 'candidate', data: candidate.raw)],
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

Effect<NativeResponse<GoogleGenerateContentResponse>, AiError> _decodeResponse(
  NativeResponse<JsonObject> response,
) {
  try {
    _throwServiceError(response.value, response.metadata);
    return Effect.succeed(
      NativeResponse(
        value: GoogleGenerateContentResponse.fromJson(response.value),
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
    _throwServiceError(raw, metadata);
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
    required int maxAssembledBytes,
  }) : assembler = GenerationStreamAssembler(
         providerId: _providerId,
         api: _api,
         modelId: modelId,
         maxAssembledBytes: maxAssembledBytes,
       );

  final String modelId;
  final GenerationStreamAssembler assembler;
  final List<JsonObject> _rawChunks = [];
  final Map<int, StringBuffer> _text = {};
  final Map<int, JsonObject> _opaque = {};
  String? _finish;
  String? _blocked;
  String? _responseId;
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
    _throwServiceError(raw, _streamMetadata);
    final value = GoogleGenerateContentResponse.fromJson(raw);
    _rawChunks.add(raw);
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
    if (value.promptFeedback?.blockReason case final reason? when _isBlocked(reason)) {
      _blocked = reason;
    }
    if (value.candidates.length > 1) {
      throw ProtocolError(
        'Google returned multiple candidates to a one-candidate common stream.',
        partialOutput: assembler.partialMessage,
      );
    }
    if (value.candidates.isNotEmpty) {
      final candidate = value.candidates.first;
      if (_isFinished(candidate.finishReason)) {
        _finish = candidate.finishReason;
      }
      final nativeParts = candidate.content?.parts ?? const <GooglePart>[];
      for (final (index, part) in nativeParts.indexed) {
        if (part.text case final delta?) {
          final buffer = _text[index];
          if (buffer == null) {
            _text[index] = StringBuffer();
            yield assembler.startPart(index: index, kind: GenerationPartKind.text);
          }
          _text[index]!.write(delta);
          if (delta.isNotEmpty) yield assembler.appendText(index, delta);
        } else {
          _opaque[index] = part.toJson();
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
    for (final entry in _text.entries) {
      yield assembler.finishPart(entry.key, TextOutputPart(entry.value.toString()));
    }
    for (final entry in _opaque.entries) {
      yield assembler.startPart(index: entry.key, kind: GenerationPartKind.opaque);
      yield assembler.finishPart(
        entry.key,
        OpaqueOutputPart(
          providerId: _providerId,
          api: _api,
          kind: 'part',
          data: entry.value,
        ),
      );
    }
    if (_blocked case final reason?) {
      const index = 0;
      yield assembler.startPart(index: index, kind: GenerationPartKind.refusal);
      yield assembler.finishPart(index, RefusalPart('Google blocked the prompt ($reason).'));
    }
    yield assembler.finish(
      finishReason: _blocked == null ? _finishReason(_finish) : FinishReason.contentFilter,
      nativeFinishReason: _blocked ?? _finish,
      nativeResponse: JsonObject({
        'chunks': _rawChunks.map((chunk) => chunk.toDart()).toList(),
      }),
      replay: [
        for (final chunk in _rawChunks) ReplayItem(phase: 'stream-chunk', data: chunk),
      ],
    );
  }
}

JsonObject _decodeEvent(SseEvent event) {
  try {
    return JsonObject.parse(event.data);
  } on FormatException catch (error) {
    throw ProtocolError(error.message);
  }
}

void _throwServiceError(JsonObject raw, ResponseMetadata metadata) {
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
  );
}

bool _isTerminal(GoogleGenerateContentResponse value) =>
    _isBlocked(value.promptFeedback?.blockReason) ||
    value.candidates.any((candidate) => _isFinished(candidate.finishReason));

bool _isBlocked(String? reason) => reason != null && reason != 'BLOCK_REASON_UNSPECIFIED';

bool _isFinished(String? reason) => reason != null && reason != 'FINISH_REASON_UNSPECIFIED';

FinishReason _finishReason(String? reason) => switch (reason) {
  'STOP' => FinishReason.stop,
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

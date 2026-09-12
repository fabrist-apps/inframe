import 'package:artificer_baseten/src/chat/chat_models.dart';
import 'package:artificer_baseten/src/options.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'baseten';
const _api = 'chat.completions';

/// Typed native and common Baseten Chat Completions operations.
final class BasetenChatCompletionsResource {
  /// Creates the resource over one provider-owned core client.
  BasetenChatCompletionsResource(this._client)
    : _codec = OpenAiCompatibleChatCodec(const _BasetenChatDialect());

  final ProviderHttpClient _client;
  final OpenAiCompatibleChatCodec<BasetenModelOptions> _codec;

  /// Creates one native chat completion.
  Effect<NativeResponse<BasetenChatCompletion>, AiError> create(
    BasetenChatRequest request,
  ) => _client
      .sendJson(
        ProviderHttpRequest(
          method: 'POST',
          path: 'chat/completions',
          body: request.toJson(stream: false),
        ),
        providerId: _providerId,
        api: _api,
        modelId: request.model,
      )
      .flatMap((response) => Effect.fromResult(_codec.decodeNative(response)));

  /// Streams typed native chunks and a terminal done event.
  Flow<BasetenChatEvent, AiError> stream(
    BasetenChatRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) => _client.sendSse(
    ProviderHttpRequest(
      method: 'POST',
      path: 'chat/completions',
      body: request.toJson(stream: true),
    ),
    createProtocol: _codec.toNativeStream,
    decodedEventCapacity: decodedEventCapacity,
    maxEventBytes: maxEventBytes,
    maxStreamBytes: maxStreamBytes,
  );

  /// Normalizes one already-decoded choice without issuing I/O.
  Result<GenerationResult, AiError> normalize(
    NativeResponse<BasetenChatCompletion> response, {
    int? choiceIndex,
  }) => _codec.normalize(response, choiceIndex: choiceIndex);

  /// Executes one common generation through the native decoder path.
  Effect<GenerationResult, AiError> generate(
    GenerationRequest request, {
    required String modelId,
    required BasetenModelOptions options,
  }) {
    final encoded = _codec.encode(
      request,
      modelId: modelId,
      options: options,
      extraBody: options.extraBody,
    );
    return switch (encoded) {
      Failure(:final error) => Effect.fail(error),
      Success(:final value) =>
        _client
            .sendJson(
              ProviderHttpRequest(
                method: 'POST',
                path: 'chat/completions',
                body: JsonObject({...value.body.toDart(), 'stream': false}),
              ),
              providerId: _providerId,
              api: _api,
              modelId: modelId,
            )
            .flatMap((response) => Effect.fromResult(_codec.decodeNative(response)))
            .flatMap((response) => Effect.fromResult(_codec.normalize(response))),
    };
  }

  /// Executes one common generation stream through the native framing path.
  Flow<GenerationEvent, AiError> streamCommon(
    GenerationRequest request, {
    required String modelId,
    required BasetenModelOptions options,
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int maxAssembledBytes = 64 * 1024 * 1024,
    int? maxStreamBytes,
  }) {
    final encoded = _codec.encode(
      request,
      modelId: modelId,
      options: options,
      extraBody: options.extraBody,
    );
    return switch (encoded) {
      Failure(:final error) => Effect.fail<GenerationEvent, AiError>(error).asFlow(),
      Success(:final value) => _client.sendSse(
        ProviderHttpRequest(
          method: 'POST',
          path: 'chat/completions',
          body: JsonObject({...value.body.toDart(), 'stream': true}),
        ),
        createProtocol: () => _codec.commonStream(
          modelId: modelId,
          maxAssembledBytes: maxAssembledBytes,
        ),
        decodedEventCapacity: decodedEventCapacity,
        maxEventBytes: maxEventBytes,
        maxStreamBytes: maxStreamBytes,
      ),
    };
  }
}

final class _BasetenChatDialect implements OpenAiCompatibleChatDialect<BasetenModelOptions> {
  const _BasetenChatDialect();

  @override
  String get providerId => _providerId;

  @override
  String get api => _api;

  @override
  AiError? validate(GenerationRequest request, BasetenModelOptions options) => null;

  @override
  JsonObject requestFields(BasetenModelOptions options) => JsonObject({
    'top_k': ?options.topK,
    'repetition_penalty': ?options.repetitionPenalty,
  });
}

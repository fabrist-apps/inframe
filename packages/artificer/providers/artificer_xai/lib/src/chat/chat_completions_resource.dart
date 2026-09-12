import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_xai/src/chat/chat_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'xai';
const _api = 'chat.completions';

/// Typed native Xai Chat Completions operations.
final class XaiChatCompletionsResource {
  /// Creates the resource over one provider-owned core client.
  XaiChatCompletionsResource(this._client)
    : _codec = OpenAiCompatibleChatCodec(const _XaiChatDialect());

  final ProviderHttpClient _client;
  final OpenAiCompatibleChatCodec<Object?> _codec;

  /// Creates one native chat completion.
  Effect<NativeResponse<XaiChatCompletion>, AiError> create(XaiChatRequest request) => _client
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
      .flatMap((value, _) => _decode(value));

  /// Streams typed native chunks and a terminal done event.
  Flow<XaiChatEvent, AiError> stream(
    XaiChatRequest request, {
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
    NativeResponse<XaiChatCompletion> response, {
    int? choiceIndex,
  }) => _codec.normalize(
    NativeResponse(
      value: response.value.compatible,
      payload: response.payload,
      metadata: response.metadata,
    ),
    choiceIndex: choiceIndex,
  );

  Effect<NativeResponse<XaiChatCompletion>, AiError> _decode(
    NativeResponse<JsonObject> response,
  ) {
    return switch (_codec.decodeNative(response)) {
      Success(:final value) => Effect.succeed(
        NativeResponse(
          value: XaiChatCompletion.fromCompatible(value.value),
          payload: value.payload,
          metadata: value.metadata,
        ),
      ),
      Failure(:final error) => Effect.fail(error),
    };
  }
}

final class _XaiChatDialect implements OpenAiCompatibleChatDialect<Object?> {
  const _XaiChatDialect();

  @override
  String get providerId => _providerId;

  @override
  String get api => _api;

  @override
  AiError? validate(GenerationRequest request, Object? options) => null;

  @override
  JsonObject requestFields(Object? options) => JsonObject({});
}

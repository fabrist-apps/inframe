import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_xai/src/embeddings/embedding_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'xai';
const _api = 'embeddings';

/// Typed native Xai embedding operations.
final class XaiEmbeddingsResource {
  /// Creates the resource over one provider-owned core client.
  const XaiEmbeddingsResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one synchronous native embedding batch.
  Effect<NativeResponse<XaiEmbeddingResponse>, AiError> create(
    XaiEmbeddingRequest request,
  ) => _client
      .sendJson(
        ProviderHttpRequest(method: 'POST', path: 'embeddings', body: request.toJson()),
        providerId: _providerId,
        api: _api,
        modelId: request.model,
      )
      .flatMap((value, _) => _decode(value));

  Effect<NativeResponse<XaiEmbeddingResponse>, AiError> _decode(
    NativeResponse<JsonObject> response,
  ) {
    try {
      return Effect.succeed(
        NativeResponse(
          value: XaiEmbeddingResponse.fromJson(response.value),
          payload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Effect.fail(ProtocolError(error.message));
    }
  }
}

/// Xai adapter for the common synchronous embedding contract.
final class XaiEmbeddingModel implements EmbeddingModel {
  /// Creates one model with immutable provider defaults.
  const XaiEmbeddingModel(this._resource, this.modelId, this.options);

  final XaiEmbeddingsResource _resource;

  /// Immutable model defaults.
  final XaiEmbeddingOptions options;

  @override
  final String modelId;

  @override
  String get providerId => _providerId;

  @override
  EmbeddingCapabilities get capabilities => EmbeddingCapabilities({
    EmbeddingCapability.text: CapabilitySupport.supported,
    EmbeddingCapability.image: CapabilitySupport.unsupported,
    EmbeddingCapability.audio: CapabilitySupport.unsupported,
    EmbeddingCapability.video: CapabilitySupport.unsupported,
    EmbeddingCapability.document: CapabilitySupport.unsupported,
    EmbeddingCapability.batching: CapabilitySupport.supported,
    EmbeddingCapability.dimensions: CapabilitySupport.supported,
  });

  @override
  Effect<EmbeddingResult, AiError> embed(
    EmbeddingRequest request, {
    XaiEmbeddingOptions? options,
  }) {
    final unsupported = capabilities.validate(request);
    if (unsupported != null) return Effect.fail(unsupported);
    final text = <XaiEmbeddingInput>[];
    for (final item in request.items) {
      if (item.parts.length != 1 || item.parts.single is! TextInputPart) {
        return Effect.fail(
          const UnsupportedFeatureError(
            'Xai common embeddings require exactly one text part per input.',
          ),
        );
      }
      text.add(XaiTextEmbeddingInput((item.parts.single as TextInputPart).text));
    }
    final encoding = this.options.resolveEncodingFormat(options);
    if (encoding == XaiEmbeddingEncoding.base64) {
      return Effect.fail(
        const UnsupportedFeatureError(
          'Common embeddings require float vectors; use embeddings.create for base64.',
        ),
      );
    }
    final dimensions = request.dimensions ?? this.options.resolveDimensions(options);
    final extraBody = this.options.resolveExtraBody(options);
    final collision = extraBody.toDart().keys.where(_commonFields.contains).firstOrNull;
    if (collision != null) {
      return Effect.fail(
        InvalidRequestError('extraBody field $collision conflicts with common embeddings.'),
      );
    }
    final native = XaiEmbeddingRequest(
      model: modelId,
      input: text,
      dimensions: dimensions,
      encodingFormat: encoding,
      preview: this.options.resolvePreview(options),
      user: this.options.resolveUser(options),
      extraBody: extraBody,
    );
    return _resource
        .create(native)
        .flatMap(
          (response, _) => _normalize(
            response,
            inputCount: request.items.length,
            requestedDimensions: dimensions,
          ),
        );
  }

  Effect<EmbeddingResult, AiError> _normalize(
    NativeResponse<XaiEmbeddingResponse> response, {
    required int inputCount,
    required int? requestedDimensions,
  }) {
    try {
      return Effect.succeed(
        EmbeddingResult.fromIndexed(
          embeddings: response.value.data.map((item) {
            final value = item.embedding;
            if (value is! XaiFloatEmbedding) {
              throw const FormatException('Common embeddings received a base64 vector.');
            }
            return IndexedEmbedding(index: item.index, vector: value.vector);
          }),
          inputCount: inputCount,
          requestedDimensions: requestedDimensions,
          modelId: response.value.model,
          usage: switch (response.value.usage) {
            final usage? => Usage(inputTokens: usage.promptTokens, totalTokens: usage.totalTokens),
            null => null,
          },
          nativePayload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Effect.fail(ProtocolError(error.message));
    }
  }
}

const _commonFields = {
  'model',
  'input',
  'dimensions',
  'encoding_format',
  'preview',
  'user',
};

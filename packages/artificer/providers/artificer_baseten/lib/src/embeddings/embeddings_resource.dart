import 'package:artificer_baseten/src/embeddings/embedding_models.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'baseten';
const _api = 'embeddings';

/// Typed native Baseten embedding operations for a dedicated deployment.
final class BasetenEmbeddingsResource {
  /// Creates the resource over one provider-owned deployment client.
  const BasetenEmbeddingsResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one synchronous native text embedding batch.
  Effect<NativeResponse<BasetenEmbeddingResponse>, AiError> create(
    BasetenEmbeddingRequest request,
  ) => _client
      .sendJson(
        ProviderHttpRequest(
          method: 'POST',
          path: 'embeddings',
          body: request.toJson(),
        ),
        providerId: _providerId,
        api: _api,
        modelId: request.model,
      )
      .flatMap((response, _) => _decode(response));

  /// Normalizes an already-decoded batch without issuing I/O.
  Result<EmbeddingResult, AiError> normalize(
    NativeResponse<BasetenEmbeddingResponse> response, {
    required int inputCount,
    int? requestedDimensions,
  }) {
    try {
      return Success(
        EmbeddingResult.fromIndexed(
          embeddings: response.value.data.map(
            (item) => IndexedEmbedding(index: item.index, vector: item.vector),
          ),
          inputCount: inputCount,
          requestedDimensions: requestedDimensions,
          modelId: response.value.model,
          usage: switch (response.value.usage) {
            final usage? => Usage(
              inputTokens: usage.promptTokens,
              totalTokens: usage.totalTokens,
            ),
            null => null,
          },
          nativePayload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Failure(ProtocolError(error.message));
    }
  }

  Effect<NativeResponse<BasetenEmbeddingResponse>, AiError> _decode(
    NativeResponse<JsonObject> response,
  ) {
    try {
      return Effect.succeed(
        NativeResponse(
          value: BasetenEmbeddingResponse.fromJson(response.value),
          payload: response.payload,
          metadata: response.metadata,
        ),
      );
    } on FormatException catch (error) {
      return Effect.fail(ProtocolError(error.message));
    }
  }
}

/// A dedicated Baseten adapter for the common embedding contract.
final class BasetenEmbeddingModel implements EmbeddingModel {
  /// Creates a model with immutable provider defaults.
  const BasetenEmbeddingModel(this._resource, this.modelId, this.options);

  final BasetenEmbeddingsResource _resource;

  /// Immutable model defaults.
  final BasetenEmbeddingOptions options;

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
    EmbeddingCapability.dimensions: CapabilitySupport.unknown,
  });

  @override
  Effect<EmbeddingResult, AiError> embed(
    EmbeddingRequest request, {
    BasetenEmbeddingOptions? options,
  }) {
    final unsupported = capabilities.validate(request);
    if (unsupported != null) return Effect.fail(unsupported);
    final text = <String>[];
    for (final item in request.items) {
      if (item.parts.length != 1 || item.parts.single is! TextInputPart) {
        return Effect.fail(
          const UnsupportedFeatureError(
            'Baseten common embeddings require exactly one text part per input.',
            feature: 'embeddingInput',
          ),
        );
      }
      text.add((item.parts.single as TextInputPart).text);
    }
    final dimensions = request.dimensions ?? this.options.resolveDimensions(options);
    final extraBody = this.options.resolveExtraBody(options);
    final collision = extraBody.toDart().keys.where(_commonFields.contains).firstOrNull;
    if (collision != null) {
      return Effect.fail(
        InvalidRequestError('extraBody field $collision conflicts with common embeddings.'),
      );
    }
    final native = BasetenEmbeddingRequest(
      model: modelId,
      input: text,
      dimensions: dimensions,
      extraBody: extraBody,
    );
    return _resource
        .create(native)
        .flatMap(
          (response, _) => Effect.fromResult(
            _resource.normalize(
              response,
              inputCount: request.items.length,
              requestedDimensions: dimensions,
            ),
          ),
        );
  }
}

const _commonFields = {'model', 'input', 'dimensions'};

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/embeddings/embedding_models.dart';
import 'package:artificer_google/src/embeddings/model_name.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'google';
const _api = 'embeddings';
const _knownBatchLimit = 100;

/// Typed native Google embedding operations and common response normalization.
final class GoogleEmbeddingsResource {
  /// Creates the resource over one provider-owned core client.
  const GoogleEmbeddingsResource(this._client);

  final ProviderHttpClient _client;

  /// Runs one native `models.embedContent` inference attempt.
  Effect<NativeResponse<GoogleEmbedContentResponse>, AiError> embedContent(
    GoogleEmbedContentRequest request,
  ) {
    final modelId = googleEmbeddingModelId(request.model);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1beta/models/${Uri.encodeComponent(modelId)}:embedContent',
            body: request.toJson(),
          ),
          providerId: _providerId,
          api: _api,
          modelId: modelId,
        )
        .flatMap((response) => _decode(response, GoogleEmbedContentResponse.fromJson));
  }

  /// Runs one native synchronous `models.batchEmbedContents` attempt.
  Effect<NativeResponse<GoogleBatchEmbedContentsResponse>, AiError> batchEmbedContents(
    GoogleBatchEmbedContentsRequest request,
  ) {
    final modelId = googleEmbeddingModelId(request.model);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1beta/models/${Uri.encodeComponent(modelId)}:batchEmbedContents',
            body: request.toJson(),
          ),
          providerId: _providerId,
          api: _api,
          modelId: modelId,
        )
        .flatMap((response) => _decode(response, GoogleBatchEmbedContentsResponse.fromJson));
  }

  /// Normalizes an already-decoded single response without issuing another request.
  EmbeddingResult normalizeEmbedContent(
    NativeResponse<GoogleEmbedContentResponse> response, {
    int? requestedDimensions,
  }) {
    try {
      return EmbeddingResult.fromIndexed(
        embeddings: [IndexedEmbedding(index: 0, vector: response.value.embedding.values)],
        inputCount: 1,
        modelId: response.payload.modelId,
        requestedDimensions: requestedDimensions,
        usage: response.value.usageMetadata?.toCommon(),
        nativePayload: response.payload,
        metadata: response.metadata,
      );
    } on FormatException catch (error) {
      throw ProtocolError(error.message);
    }
  }

  /// Normalizes an already-decoded synchronous batch in request order.
  EmbeddingResult normalizeBatchEmbedContents(
    NativeResponse<GoogleBatchEmbedContentsResponse> response, {
    required int inputCount,
    int? requestedDimensions,
  }) {
    try {
      return EmbeddingResult.fromIndexed(
        embeddings: response.value.embeddings.indexed.map(
          (entry) => IndexedEmbedding(index: entry.$1, vector: entry.$2.values),
        ),
        inputCount: inputCount,
        modelId: response.payload.modelId,
        requestedDimensions: requestedDimensions,
        usage: response.value.usageMetadata?.toCommon(),
        nativePayload: response.payload,
        metadata: response.metadata,
      );
    } on FormatException catch (error) {
      throw ProtocolError(error.message);
    }
  }
}

/// Google adapter for the common synchronous embedding contract.
final class GoogleEmbeddingModel implements EmbeddingModel {
  /// Creates one model with immutable provider defaults.
  GoogleEmbeddingModel(
    this._resource,
    String modelId,
    this.options,
  ) : modelId = _bareModelId(modelId);

  final GoogleEmbeddingsResource _resource;

  /// Immutable model defaults.
  final GoogleEmbeddingOptions options;

  @override
  final String modelId;

  @override
  String get providerId => _providerId;

  @override
  EmbeddingCapabilities get capabilities => _modelCapabilities(modelId);

  @override
  Effect<EmbeddingResult, AiError> embed(
    EmbeddingRequest request, {
    GoogleEmbeddingOptions? options,
  }) {
    final encoded = _encode(request, options);
    return switch (encoded) {
      AiError() => Effect.fail(encoded),
      final List<GoogleEmbedContentRequest> requests when requests.length == 1 =>
        _resource
            .embedContent(requests.single)
            .flatMap(
              (response) => _normalize(
                () => _resource.normalizeEmbedContent(
                  response,
                  requestedDimensions: _requestedDimensions(request, options),
                ),
              ),
            ),
      final List<GoogleEmbedContentRequest> requests =>
        _resource
            .batchEmbedContents(
              GoogleBatchEmbedContentsRequest(
                model: 'models/$modelId',
                requests: requests,
              ),
            )
            .flatMap(
              (response) => _normalize(
                () => _resource.normalizeBatchEmbedContents(
                  response,
                  inputCount: request.items.length,
                  requestedDimensions: _requestedDimensions(request, options),
                ),
              ),
            ),
      _ => throw StateError('Unexpected Google embedding request encoding result.'),
    };
  }

  Object _encode(EmbeddingRequest request, GoogleEmbeddingOptions? callOptions) {
    final unsupported = capabilities.validate(request);
    if (unsupported != null) return unsupported;

    final profile = _profile(modelId);
    if (profile != null && request.items.length > _knownBatchLimit) {
      return const UnsupportedFeatureError(
        'Google synchronous embedding batches accept at most 100 inputs.',
        feature: 'batchSize',
      );
    }

    final taskType = options.resolveTaskType(callOptions);
    final title = options.resolveTitle(callOptions);
    final optionDimensions = options.resolveDimensions(callOptions);
    if (request.dimensions != null &&
        optionDimensions != null &&
        request.dimensions != optionDimensions) {
      return const InvalidRequestError(
        'EmbeddingRequest.dimensions conflicts with Google embedding options.',
      );
    }
    final dimensions = request.dimensions ?? optionDimensions;

    if (title != null && taskType != GoogleEmbeddingTaskType.retrievalDocument) {
      return const InvalidRequestError(
        'Google embedding titles require RETRIEVAL_DOCUMENT.',
      );
    }
    if (profile case final profile?) {
      if (!profile.supportsTasks && taskType != null) {
        return UnsupportedFeatureError(
          '$modelId does not support task type configuration.',
          feature: 'taskType',
        );
      }
      if (!profile.supportsDimensions && dimensions != null) {
        return UnsupportedFeatureError(
          '$modelId does not support output dimensions.',
          feature: 'dimensions',
        );
      }
      final dimensionError = profile.validateDimensions(dimensions);
      if (dimensionError != null) return dimensionError;
    }

    final config = taskType == null && title == null && dimensions == null
        ? null
        : GoogleEmbedContentConfig(
            taskType: taskType,
            title: title,
            outputDimensionality: dimensions,
          );
    final extraBody = options.resolveExtraBody(callOptions);
    final requests = <GoogleEmbedContentRequest>[];
    for (final item in request.items) {
      final content = _encodeInput(item, profile);
      if (content is AiError) return content;
      requests.add(
        GoogleEmbedContentRequest(
          model: 'models/$modelId',
          content: content as GoogleContent,
          config: config,
          extraBody: extraBody,
        ),
      );
    }
    return requests;
  }

  GoogleContent _content(List<GooglePart> parts) => GoogleContent(parts: parts);

  Object _encodeInput(EmbeddingInput input, _EmbeddingProfile? profile) {
    if (profile?.multimodal == true) {
      final images = input.parts.whereType<MediaInputPart>().where(
        (part) => part.kind == MediaKind.image,
      );
      final documents = input.parts.whereType<MediaInputPart>().where(
        (part) => part.kind == MediaKind.document,
      );
      if (images.length > 6) {
        return const UnsupportedFeatureError(
          'gemini-embedding-2 accepts at most six images per input.',
          feature: 'imageCount',
        );
      }
      if (documents.length > 1) {
        return const UnsupportedFeatureError(
          'gemini-embedding-2 accepts at most one PDF per input.',
          feature: 'documentCount',
        );
      }
    }

    final parts = <GooglePart>[];
    for (final part in input.parts) {
      switch (part) {
        case TextInputPart(:final text):
          parts.add(GooglePart.text(text));
        case MediaInputPart():
          final encoded = _encodeMedia(part, profile);
          if (encoded is AiError) return encoded;
          parts.add(encoded as GooglePart);
      }
    }
    return _content(parts);
  }

  Object _encodeMedia(MediaInputPart part, _EmbeddingProfile? profile) {
    if (profile?.multimodal == true && !_supportedMimeType(part)) {
      return UnsupportedFeatureError(
        '$modelId does not support ${part.mimeType} ${part.kind.name} embeddings.',
        feature: part.kind.name,
      );
    }
    return switch (part.source) {
      BytesMediaSource(:final bytes) => GooglePart.inlineData(
        GoogleInlineData(mimeType: part.mimeType, bytes: bytes),
      ),
      UrlMediaSource() => const UnsupportedFeatureError(
        'Google embeddings cannot forward an HTTP(S) media URL; use bytes or a Google file.',
        feature: 'mediaUrl',
      ),
      ProviderFileSource(
        :final providerId,
        :final api,
        :final reference,
        mimeType: final sourceMimeType,
      ) =>
        switch ((providerId, api, sourceMimeType == part.mimeType)) {
          ('google', 'files', true) => GooglePart.fileData(
            GoogleFileData(mimeType: part.mimeType, fileUri: reference),
          ),
          (_, _, false) => const InvalidRequestError(
            'The media and provider-file MIME types must match.',
          ),
          _ => const UnsupportedFeatureError(
            'Google embeddings require a file reference from the Google files API.',
            feature: 'providerFile',
          ),
        },
    };
  }

  int? _requestedDimensions(
    EmbeddingRequest request,
    GoogleEmbeddingOptions? callOptions,
  ) => request.dimensions ?? options.resolveDimensions(callOptions);

  Effect<EmbeddingResult, AiError> _normalize(EmbeddingResult Function() normalize) {
    try {
      return Effect.succeed(normalize());
    } on AiError catch (error) {
      return Effect.fail(error);
    }
  }
}

Effect<NativeResponse<T>, AiError> _decode<T>(
  NativeResponse<JsonObject> response,
  T Function(JsonObject) decode,
) {
  try {
    return Effect.succeed(
      NativeResponse(
        value: decode(response.value),
        payload: response.payload,
        metadata: response.metadata,
      ),
    );
  } on FormatException catch (error) {
    return Effect.fail(ProtocolError(error.message));
  }
}

EmbeddingCapabilities _modelCapabilities(String modelId) {
  final profile = _profile(modelId);
  if (profile == null) return EmbeddingCapabilities({});
  return EmbeddingCapabilities({
    EmbeddingCapability.text: CapabilitySupport.supported,
    EmbeddingCapability.image: profile.multimodal
        ? CapabilitySupport.supported
        : CapabilitySupport.unsupported,
    EmbeddingCapability.audio: profile.multimodal
        ? CapabilitySupport.supported
        : CapabilitySupport.unsupported,
    EmbeddingCapability.video: profile.multimodal
        ? CapabilitySupport.supported
        : CapabilitySupport.unsupported,
    EmbeddingCapability.document: profile.multimodal
        ? CapabilitySupport.supported
        : CapabilitySupport.unsupported,
    EmbeddingCapability.batching: CapabilitySupport.supported,
    EmbeddingCapability.dimensions: profile.supportsDimensions
        ? CapabilitySupport.supported
        : CapabilitySupport.unsupported,
  });
}

_EmbeddingProfile? _profile(String modelId) => switch (modelId) {
  'gemini-embedding-2' => const _EmbeddingProfile(
    multimodal: true,
    supportsTasks: false,
    supportsDimensions: true,
    minimumDimensions: 128,
    maximumDimensions: 3072,
  ),
  'gemini-embedding-001' || 'text-embedding-004' => const _EmbeddingProfile(
    multimodal: false,
    supportsTasks: true,
    supportsDimensions: true,
    minimumDimensions: 1,
    maximumDimensions: 3072,
  ),
  'embedding-001' => const _EmbeddingProfile(
    multimodal: false,
    supportsTasks: false,
    supportsDimensions: false,
  ),
  _ => null,
};

final class _EmbeddingProfile {
  const _EmbeddingProfile({
    required this.multimodal,
    required this.supportsTasks,
    required this.supportsDimensions,
    this.minimumDimensions,
    this.maximumDimensions,
  });

  final bool multimodal;
  final bool supportsTasks;
  final bool supportsDimensions;
  final int? minimumDimensions;
  final int? maximumDimensions;

  InvalidRequestError? validateDimensions(int? dimensions) {
    if (dimensions == null) return null;
    if (minimumDimensions case final minimum? when dimensions < minimum) {
      return InvalidRequestError(
        'The requested dimensions must be at least $minimum for this model.',
      );
    }
    if (maximumDimensions case final maximum? when dimensions > maximum) {
      return InvalidRequestError(
        'The requested dimensions must be at most $maximum for this model.',
      );
    }
    return null;
  }
}

bool _supportedMimeType(MediaInputPart part) => switch (part.kind) {
  MediaKind.image => const {'image/png', 'image/jpeg'}.contains(part.mimeType),
  MediaKind.audio => const {'audio/mpeg', 'audio/wav', 'audio/x-wav'}.contains(part.mimeType),
  MediaKind.video => const {'video/mp4', 'video/quicktime'}.contains(part.mimeType),
  MediaKind.document => part.mimeType == 'application/pdf',
};

String _bareModelId(String modelId) {
  if (modelId.isEmpty || modelId.startsWith('models/') || modelId.contains('/')) {
    throw ArgumentError.value(
      modelId,
      'modelId',
      'must be a nonempty bare provider model ID',
    );
  }
  return modelId;
}

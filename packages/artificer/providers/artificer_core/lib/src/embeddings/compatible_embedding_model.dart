import 'package:artificer_core/src/embeddings/embeddings.dart';
import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/models.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/text_request_policy.dart';
import 'package:artificer_core/src/settings.dart';
import 'package:artificer_core/src/transport/provider_http_client.dart';
import 'package:conflux/effect.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'compatible_embedding_model.mapper.dart';

/// Compatible native-only configuration, separate from common input/dimensions.
@MappableClass()
final class EmbeddingOptions with EmbeddingOptionsMappable {
  /// Creates inherited or per-call options.
  const EmbeddingOptions({
    this.user = const Setting.inherit(),
    this.extraBody = const Setting.inherit(),
  });

  /// Optional caller attribution accepted by compatible endpoints.
  final Setting<String> user;

  /// Neutral new native text fields; typed collisions and deferred scope fail.
  final Setting<Map<String, Object?>> extraBody;

  /// Decodes persisted option intent.
  static const fromMap = EmbeddingOptionsMapper.fromMap;

  /// Decodes persisted option intent from a JSON string.
  static const fromJson = EmbeddingOptionsMapper.fromJson;
}

/// Provider-support model for indexed synchronous text embedding endpoints.
/// Its provider owns [client]; creating or using a model never creates a Runtime.
final class CompatibleEmbeddingModel implements EmbeddingModel {
  /// Creates a borrowed model handle with an open provider-local model ID.
  CompatibleEmbeddingModel({
    required this.providerId,
    required this.modelId,
    required this.client,
    required this.endpoint,
    this.headers = const {},
    this.capabilities = const EmbeddingCapabilities(),
    this.defaults = const EmbeddingOptions(),
    this.maxBatchSize,
  }) {
    if (providerId.isEmpty || modelId.isEmpty) {
      throw ArgumentError('Provider and model IDs must be nonempty.');
    }
    if (maxBatchSize != null && maxBatchSize! <= 0) {
      throw ArgumentError.value(maxBatchSize, 'maxBatchSize');
    }
  }
  @override
  final String providerId;
  @override
  final String modelId;
  @override
  final EmbeddingCapabilities capabilities;

  /// Borrowed provider transport owner.
  final ProviderHttpClient client;

  /// Explicit absolute embedding endpoint.
  final Uri endpoint;

  /// Explicit authentication/routing headers, unchanged during a run.
  final Map<String, Object?> headers;

  /// Provider model defaults, read at execution.
  final EmbeddingOptions defaults;

  /// Known provider batch limit; oversized requests are never split.
  final int? maxBatchSize;
  static const _policy = TextRequestPolicy(
    typedFields: {'model', 'input', 'dimensions', 'encoding_format', 'user'},
  );

  /// Executes native inference once and normalizes the same response.
  @override
  Effect<EmbeddingResult, AiError> embed(EmbeddingRequest request, {EmbeddingOptions? options}) =>
      rawEmbed(request, options: options).flatMap(
        (response, _) => Effect.fromResult(
          response.value.normalize(request, response.raw, metadata: response.metadata),
        ),
      );

  /// Returns typed and complete raw views of one synchronous native response.
  Effect<NativeResponse<EmbeddingBatch>, AiError> rawEmbed(
    EmbeddingRequest request, {
    EmbeddingOptions? options,
  }) => Effect.build(($) async {
    if (request.items.isEmpty || (maxBatchSize != null && request.items.length > maxBatchSize!)) {
      return $(
        Effect.fail(
          const InvalidRequestError('Embedding batch is empty or exceeds the configured limit.'),
        ),
      );
    }
    if (request.dimensions != null && capabilities.dimensions == CapabilitySupport.unsupported) {
      return $(
        Effect.fail(
          const UnsupportedFeatureError('Requested embedding dimensions are unsupported.'),
        ),
      );
    }
    final resolved = options ?? const EmbeddingOptions();
    final user = resolved.user.resolve(defaults.user.resolve(null));
    final extras = resolved.extraBody.resolve(defaults.extraBody.resolve(const {})) ?? const {};
    final body = $.sync(
      _policy.prepare(
        native: {
          'model': modelId,
          'input': [for (final item in request.items) item.text],
          'encoding_format': 'float',
          if (request.dimensions != null) 'dimensions': request.dimensions,
          'user': ?user,
        },
        extraBody: extras,
      ),
    );
    final response = await $(client.requestJson(url: endpoint, headers: headers, body: body));
    final data = response.data;
    if (data is! Map<String, Object?>) {
      return $(Effect.fail(const ProtocolError('Embedding response must be an object.')));
    }
    if (data.containsKey('error')) {
      final details = data['error'];
      return $(
        Effect.fail(
          ProviderError(
            details is Map<String, Object?> && details['message'] is String
                ? details['message']! as String
                : 'Embedding provider returned an error.',
            code: details is Map<String, Object?> && details['code'] is String
                ? details['code']! as String
                : null,
            details: details,
            statusCode: response.metadata.statusCode,
            requestId: response.metadata.requestId,
          ),
        ),
      );
    }
    EmbeddingBatch batch;
    try {
      batch = EmbeddingBatch.fromMap(data);
    } on MapperException {
      return $(Effect.fail(ProtocolError('Malformed embedding response.', partialOutput: data)));
    }
    return NativeResponse(
      value: batch,
      raw: NativePayload(providerId: providerId, api: 'embeddings', modelId: modelId, data: data),
      metadata: response.metadata,
    );
  });
}

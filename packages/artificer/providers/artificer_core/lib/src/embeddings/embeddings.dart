import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/models.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/serialization.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'embeddings.mapper.dart';

/// One text value producing one embedding vector.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class EmbeddingInput with EmbeddingInputMappable {
  /// Creates one text input without tokenization or concatenation.
  const EmbeddingInput.text(this.text);

  /// The complete input text.
  final String text;

  /// Decodes a persisted map.
  static const fromMap = EmbeddingInputMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = EmbeddingInputMapper.fromJson;
}

/// An ordered, synchronous text embedding request.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class EmbeddingRequest with EmbeddingRequestMappable {
  /// Retains inputs for lazy execution; callers must not mutate during a run.
  EmbeddingRequest({required this.items, this.dimensions}) {
    if (items.isEmpty) throw ArgumentError.value(items, 'items', 'Must not be empty.');
    if (dimensions != null && dimensions! <= 0) throw ArgumentError.value(dimensions, 'dimensions');
  }

  /// One input per requested vector, in caller order.
  final List<EmbeddingInput> items;

  /// Optional requested vector dimensions.
  final int? dimensions;

  /// Decodes a persisted map.
  static const fromMap = EmbeddingRequestMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = EmbeddingRequestMapper.fromJson;
}

/// Known text embedding capabilities; an unknown model remains service-validated.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class EmbeddingCapabilities with EmbeddingCapabilitiesMappable {
  /// Creates the known capability description.
  const EmbeddingCapabilities({this.dimensions = CapabilitySupport.unknown});

  /// Whether explicit output dimensions are supported.
  final CapabilitySupport dimensions;

  /// Decodes a persisted map.
  static const fromMap = EmbeddingCapabilitiesMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = EmbeddingCapabilitiesMapper.fromJson;
}

/// Common embeddings with caller-owned execution and provider lifetime.
abstract interface class EmbeddingModel {
  /// Provider identity.
  String get providerId;

  /// Nonempty provider-local model identifier.
  String get modelId;

  /// Known capabilities for preflight.
  EmbeddingCapabilities get capabilities;

  /// One cold synchronous embedding request per execution.
  Effect<EmbeddingResult, AiError> embed(EmbeddingRequest request);
}

/// Factory capability implemented only by providers offering embeddings.
abstract interface class EmbeddingModelProvider {
  /// Creates a model handle without discovery or network requests.
  EmbeddingModel embeddingModel(String modelId);
}

/// One vector per input, in input order, with native data preserved.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class EmbeddingResult with EmbeddingResultMappable {
  /// Retains vectors and metadata without resizing or magnitude normalization.
  EmbeddingResult({
    required this.vectors,
    required this.modelId,
    required this.native,
    this.usage,
    this.metadata,
    this.schemaVersion = 1,
  }) {
    DomainSchema.check(schemaVersion);
  }

  /// Finite, nonempty vectors restored to input order.
  final List<List<double>> vectors;

  /// Actual model identity returned by the endpoint.
  final String modelId;

  /// Complete native response, including unknown fields.
  final NativePayload native;

  /// Available usage; omitted values remain null.
  final Usage? usage;

  /// Response metadata for explicit inspection.
  final ResponseMetadata? metadata;

  /// Domain persistence version.
  final int schemaVersion;

  /// Decodes a persisted map.
  static const fromMap = EmbeddingResultMapper.fromMap;

  /// Decodes a persisted JSON string.
  static const fromJson = EmbeddingResultMapper.fromJson;
}

/// One indexed vector from compatible synchronous embedding endpoints.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class IndexedEmbedding with IndexedEmbeddingMappable {
  /// Creates the typed native view; normalization validates result invariants.
  const IndexedEmbedding({required this.index, required this.embedding});

  /// Original input index.
  final int index;

  /// Unmodified vector elements.
  final List<double> embedding;

  /// Decodes native map fields.
  static const fromMap = IndexedEmbeddingMapper.fromMap;

  /// Decodes native JSON text.
  static const fromJson = IndexedEmbeddingMapper.fromJson;
}

/// Typed response view paired with full unknown JSON in a NativeResponse.
@MappableClass(generateMethods: GenerateMethods.encode | GenerateMethods.decode)
final class EmbeddingBatch with EmbeddingBatchMappable {
  /// Creates a synchronous batch response view.
  const EmbeddingBatch({required this.model, required this.data, this.usage});

  /// Actual model identity.
  final String model;

  /// Native result order; normalization restores input indices.
  final List<IndexedEmbedding> data;

  /// Native token accounting, retained without inventing missing values.
  final Map<String, Object?>? usage;

  /// Decodes native map fields.
  static const fromMap = EmbeddingBatchMapper.fromMap;

  /// Decodes native JSON text.
  static const fromJson = EmbeddingBatchMapper.fromJson;

  /// Validates and normalizes an already-decoded batch without another request.
  Result<EmbeddingResult, AiError> normalize(
    EmbeddingRequest request,
    NativePayload native, {
    ResponseMetadata? metadata,
  }) {
    ProtocolError invalid(String message) => ProtocolError(message, partialOutput: native.data);
    if (model.isEmpty || data.length != request.items.length || data.isEmpty) {
      return Failure(invalid('Embedding response count or model is invalid.'));
    }
    final ordered = List<List<double>?>.filled(request.items.length, null);
    int? dimensions;
    for (final item in data) {
      if (item.index < 0 || item.index >= ordered.length || ordered[item.index] != null) {
        return Failure(invalid('Embedding indices are missing, duplicated or out of range.'));
      }
      final vector = item.embedding;
      dimensions ??= vector.length;
      if (vector.isEmpty ||
          vector.any((value) => !value.isFinite) ||
          vector.length != dimensions ||
          (request.dimensions != null && vector.length != request.dimensions)) {
        return Failure(
          invalid('Embedding vectors must be finite and have consistent requested dimensions.'),
        );
      }
      ordered[item.index] = vector;
    }
    int? tokens(String key) {
      final value = usage?[key];
      if (value == null) return null;
      if (value is! int || value < 0) throw const FormatException('Invalid usage count.');
      return value;
    }

    Usage? normalizedUsage;
    try {
      if (usage != null) {
        normalizedUsage = Usage(
          inputTokens: tokens('prompt_tokens'),
          totalTokens: tokens('total_tokens'),
        );
      }
    } on FormatException {
      return Failure(invalid('Embedding usage must contain nonnegative integers.'));
    }
    return Success(
      EmbeddingResult(
        vectors: [for (final vector in ordered) vector!],
        modelId: model,
        native: native,
        metadata: metadata,
        usage: normalizedUsage,
      ),
    );
  }
}

import 'package:artificer_core/src/capabilities.dart';
import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';

/// One semantic embedding input; multiple parts remain one input.
final class EmbeddingInput {
  /// Creates an [EmbeddingInput].
  EmbeddingInput(Iterable<InputPart> parts) : parts = List.unmodifiable(parts) {
    if (this.parts.isEmpty) throw ArgumentError.value(parts, 'parts', 'must not be empty');
  }

  /// The text content.
  EmbeddingInput.text(String text) : this([TextInputPart(text)]);

  /// Creates a validated immutable value from Dart data.
  factory EmbeddingInput.fromDart(Object? value) {
    final map = _object(value, 'embedding input');
    return EmbeddingInput(_list(map, 'parts').map(InputPart.fromDart));
  }

  /// The ordered message parts.
  final List<InputPart> parts;

  /// Returns a detached Dart representation.
  Map<String, Object?> toDart() => {
    'parts': parts.map((part) => part.toDart()).toList(),
  };
}

/// One synchronous request containing independently embedded items.
final class EmbeddingRequest {
  /// Creates an [EmbeddingRequest].
  EmbeddingRequest({required Iterable<EmbeddingInput> items, this.dimensions})
    : items = List.unmodifiable(items) {
    if (this.items.isEmpty) throw ArgumentError.value(items, 'items', 'must not be empty');
    if (dimensions != null && dimensions! <= 0) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
  }

  /// Deserializes and validates a schema-versioned value.
  factory EmbeddingRequest.fromJson(JsonObject json) {
    final value = _versioned(json);
    return EmbeddingRequest(
      items: _list(value, 'items').map(EmbeddingInput.fromDart),
      dimensions: value['dimensions'] as int?,
    );
  }

  /// The immutable ordered items.
  final List<EmbeddingInput> items;

  /// The requested or returned embedding dimensions.
  final int? dimensions;

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'items': items.map((item) => item.toDart()).toList(),
    'dimensions': ?dimensions,
  });
}

/// A provider-returned vector with its native item index.
final class IndexedEmbedding {
  /// Creates an [IndexedEmbedding].
  IndexedEmbedding({required this.index, required Iterable<num> vector})
    : vector = List.unmodifiable(vector.map((value) => value.toDouble()));

  /// The provider or local order index.
  final int index;

  /// The finite embedding vector.
  final List<double> vector;
}

/// Ordered, validated embedding vectors and their retained native response.
final class EmbeddingResult {
  EmbeddingResult._({
    required this.vectors,
    required this.modelId,
    required this.nativePayload,
    required this.metadata,
    this.usage,
  });

  /// Restores provider-indexed vectors to request order and validates dimensions.
  factory EmbeddingResult.fromIndexed({
    required Iterable<IndexedEmbedding> embeddings,
    required int inputCount,
    required String modelId,
    required NativePayload nativePayload,
    required ResponseMetadata metadata,
    int? requestedDimensions,
    Usage? usage,
  }) {
    if (inputCount <= 0) {
      throw ArgumentError.value(inputCount, 'inputCount', 'must be positive');
    }
    if (modelId.isEmpty) throw ArgumentError.value(modelId, 'modelId', 'must not be empty');
    final ordered = List<List<double>?>.filled(inputCount, null);
    for (final embedding in embeddings) {
      if (embedding.index < 0 || embedding.index >= inputCount) {
        throw FormatException('Embedding index ${embedding.index} is out of range.');
      }
      if (ordered[embedding.index] != null) {
        throw FormatException('Duplicate embedding index ${embedding.index}.');
      }
      if (embedding.vector.isEmpty) {
        throw FormatException('Embedding ${embedding.index} is empty.');
      }
      if (embedding.vector.any((value) => !value.isFinite)) {
        throw FormatException('Embedding ${embedding.index} contains a nonfinite value.');
      }
      ordered[embedding.index] = List.unmodifiable(embedding.vector);
    }
    if (ordered.any((vector) => vector == null)) {
      throw const FormatException('The provider omitted an embedding item.');
    }
    final vectors = ordered.cast<List<double>>();
    final dimensions = vectors.first.length;
    if (vectors.any((vector) => vector.length != dimensions)) {
      throw const FormatException('Embedding dimensions are inconsistent.');
    }
    if (requestedDimensions != null && dimensions != requestedDimensions) {
      throw FormatException(
        'Expected $requestedDimensions embedding dimensions, received $dimensions.',
      );
    }
    return EmbeddingResult._(
      vectors: List.unmodifiable(vectors),
      modelId: modelId,
      nativePayload: nativePayload,
      metadata: metadata,
      usage: usage,
    );
  }

  /// Deserializes and validates a schema-versioned value.
  factory EmbeddingResult.fromJson(JsonObject json) {
    final value = _versioned(json);
    final vectors = _list(value, 'vectors');
    return EmbeddingResult.fromIndexed(
      embeddings: vectors.indexed.map((entry) {
        final vector = entry.$2;
        if (vector is! List<Object?> || vector.any((item) => item is! num)) {
          throw const FormatException('Embedding vector must contain numbers.');
        }
        return IndexedEmbedding(index: entry.$1, vector: vector.cast<num>());
      }),
      inputCount: vectors.length,
      modelId: _string(value, 'modelId'),
      usage: switch (value['usage']) {
        final Map<String, Object?> usage => Usage.fromDart(usage),
        _ => null,
      },
      nativePayload: NativePayload.fromJson(JsonObject.fromDart(value['nativePayload'])),
      metadata: ResponseMetadata.fromJson(JsonObject.fromDart(value['metadata'])),
    );
  }

  /// The embedding vectors restored to request order.
  final List<List<double>> vectors;

  /// The provider-local model identifier.
  final String modelId;

  /// The available token usage.
  final Usage? usage;

  /// The complete retained provider response payload.
  final NativePayload nativePayload;

  /// The HTTP response metadata.
  final ResponseMetadata metadata;

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'vectors': vectors,
    'modelId': modelId,
    if (usage case final usage?) 'usage': usage.toDart(),
    'nativePayload': nativePayload.toJson().toDart(),
    'metadata': metadata.toJson().toDart(),
  });
}

/// Shared embedding-model capabilities.
final class EmbeddingCapabilities {
  /// Creates an [EmbeddingCapabilities].
  EmbeddingCapabilities(Map<EmbeddingCapability, CapabilitySupport> values)
    : _values = Map.unmodifiable(values);

  final Map<EmbeddingCapability, CapabilitySupport> _values;

  /// Returns the declared support level, or [CapabilitySupport.unknown].
  CapabilitySupport operator [](EmbeddingCapability capability) =>
      _values[capability] ?? CapabilitySupport.unknown;

  /// Returns a typed preflight error when the request is unsupported.
  UnsupportedFeatureError? validate(EmbeddingRequest request) {
    final requested = <EmbeddingCapability>{
      if (request.items.length > 1) EmbeddingCapability.batching,
      if (request.dimensions != null) EmbeddingCapability.dimensions,
      for (final input in request.items)
        for (final media in input.parts.whereType<MediaInputPart>())
          switch (media.kind) {
            MediaKind.image => EmbeddingCapability.image,
            MediaKind.audio => EmbeddingCapability.audio,
            MediaKind.video => EmbeddingCapability.video,
            MediaKind.document => EmbeddingCapability.document,
          },
    };
    for (final capability in requested) {
      if (this[capability] == CapabilitySupport.unsupported) {
        return UnsupportedFeatureError(
          'The embedding model does not support ${capability.name}.',
          feature: capability.name,
        );
      }
    }
    return null;
  }
}

/// A common embedding-model feature.
enum EmbeddingCapability {
  /// Text input.
  text,

  /// Image input.
  image,

  /// Audio input.
  audio,

  /// Video input.
  video,

  /// Document input.
  document,

  /// Multiple embedding inputs in one request.
  batching,

  /// Caller-selected vector dimensions.
  dimensions,
}

Map<String, Object?> _versioned(JsonObject json) {
  final value = json.toDart();
  if (value['schemaVersion'] != 1) {
    throw FormatException('Unsupported schema version: ${value['schemaVersion']}');
  }
  return value;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return value;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

import '../capabilities.dart';
import '../errors.dart';
import '../generation/generation.dart';
import '../json/json_value.dart';
import '../messages/messages.dart';
import '../native.dart';

/// One semantic embedding input; multiple parts remain one input.
final class EmbeddingInput {
  EmbeddingInput(Iterable<InputPart> parts) : parts = List.unmodifiable(parts) {
    if (this.parts.isEmpty) throw ArgumentError.value(parts, 'parts', 'must not be empty');
  }

  EmbeddingInput.text(String text) : this([TextInputPart(text)]);

  final List<InputPart> parts;

  Map<String, Object?> toDart() => {
    'parts': parts.map((part) => part.toDart()).toList(),
  };

  static EmbeddingInput fromDart(Object? value) {
    final map = _object(value, 'embedding input');
    return EmbeddingInput(_list(map, 'parts').map(InputPart.fromDart));
  }
}

/// One synchronous request containing independently embedded items.
final class EmbeddingRequest {
  EmbeddingRequest({required Iterable<EmbeddingInput> items, this.dimensions})
    : items = List.unmodifiable(items) {
    if (this.items.isEmpty) throw ArgumentError.value(items, 'items', 'must not be empty');
    if (dimensions != null && dimensions! <= 0) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
  }

  final List<EmbeddingInput> items;
  final int? dimensions;

  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'items': items.map((item) => item.toDart()).toList(),
    if (dimensions case final dimensions?) 'dimensions': dimensions,
  });

  static EmbeddingRequest fromJson(JsonObject json) {
    final value = _versioned(json);
    return EmbeddingRequest(
      items: _list(value, 'items').map(EmbeddingInput.fromDart),
      dimensions: value['dimensions'] as int?,
    );
  }
}

/// A provider-returned vector with its native item index.
final class IndexedEmbedding {
  IndexedEmbedding({required this.index, required Iterable<num> vector})
    : vector = List.unmodifiable(vector.map((value) => value.toDouble()));

  final int index;
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

  factory EmbeddingResult.fromIndexed({
    required Iterable<IndexedEmbedding> embeddings,
    required int inputCount,
    int? requestedDimensions,
    required String modelId,
    Usage? usage,
    required NativePayload nativePayload,
    required ResponseMetadata metadata,
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

  final List<List<double>> vectors;
  final String modelId;
  final Usage? usage;
  final NativePayload nativePayload;
  final ResponseMetadata metadata;

  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'vectors': vectors,
    'modelId': modelId,
    if (usage case final usage?) 'usage': usage.toDart(),
    'nativePayload': nativePayload.toJson().toDart(),
    'metadata': metadata.toJson().toDart(),
  });

  static EmbeddingResult fromJson(JsonObject json) {
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
        Map<String, Object?> usage => Usage.fromDart(usage),
        _ => null,
      },
      nativePayload: NativePayload.fromJson(JsonObject.fromDart(value['nativePayload'])),
      metadata: ResponseMetadata.fromJson(JsonObject.fromDart(value['metadata'])),
    );
  }
}

/// Shared embedding-model capabilities.
final class EmbeddingCapabilities {
  EmbeddingCapabilities(Map<EmbeddingCapability, CapabilitySupport> values)
    : _values = Map.unmodifiable(values);

  final Map<EmbeddingCapability, CapabilitySupport> _values;

  CapabilitySupport operator [](EmbeddingCapability capability) =>
      _values[capability] ?? CapabilitySupport.unknown;

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
enum EmbeddingCapability { text, image, audio, video, document, batching, dimensions }

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

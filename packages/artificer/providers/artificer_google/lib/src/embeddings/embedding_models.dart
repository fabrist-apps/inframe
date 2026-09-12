import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/src/embeddings/model_name.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';

/// Native embedding task types in the Google API snapshot from 2026-09-12.
enum GoogleEmbeddingTaskType {
  /// Let the service select its default task.
  unspecified('TASK_TYPE_UNSPECIFIED'),

  /// A query used to retrieve relevant documents.
  retrievalQuery('RETRIEVAL_QUERY'),

  /// A document stored for later retrieval.
  retrievalDocument('RETRIEVAL_DOCUMENT'),

  /// Semantic similarity comparison.
  semanticSimilarity('SEMANTIC_SIMILARITY'),

  /// Text classification.
  classification('CLASSIFICATION'),

  /// Unsupervised clustering.
  clustering('CLUSTERING'),

  /// A question used to retrieve an answer-bearing document.
  questionAnswering('QUESTION_ANSWERING'),

  /// A claim used to retrieve supporting or contradicting evidence.
  factVerification('FACT_VERIFICATION'),

  /// Natural-language retrieval of code.
  codeRetrievalQuery('CODE_RETRIEVAL_QUERY');

  const GoogleEmbeddingTaskType(this.wireValue);

  /// The value sent to the Gemini Developer API.
  final String wireValue;
}

/// Native `EmbedContentConfig` pinned to the 2026-09-12 Google API snapshot.
final class GoogleEmbedContentConfig {
  /// Creates an embedding configuration.
  GoogleEmbedContentConfig({
    this.title,
    this.taskType,
    this.autoTruncate,
    this.outputDimensionality,
    this.documentOcr,
    this.audioTrackExtraction,
    JsonObject? extensions,
  }) : extensions = extensions ?? JsonObject({}) {
    if (title != null && title!.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    if (title != null && taskType != GoogleEmbeddingTaskType.retrievalDocument) {
      throw ArgumentError.value(
        title,
        'title',
        'is only valid for RETRIEVAL_DOCUMENT',
      );
    }
    if (outputDimensionality != null && outputDimensionality! <= 0) {
      throw ArgumentError.value(
        outputDimensionality,
        'outputDimensionality',
        'must be positive',
      );
    }
    _rejectCollisions(this.extensions, _configFields, 'extensions');
  }

  GoogleEmbedContentConfig._({
    required this.title,
    required this.taskType,
    required this.autoTruncate,
    required this.outputDimensionality,
    required this.documentOcr,
    required this.audioTrackExtraction,
    required this.extensions,
  });

  /// Decodes a configuration while retaining unknown fields and enum values.
  factory GoogleEmbedContentConfig.fromJson(JsonObject json) {
    final value = json.toDart();
    final taskWireValue = _optionalString(value, 'taskType');
    final taskType = _taskType(taskWireValue);
    final knownFields = <String>{
      'title',
      'autoTruncate',
      'outputDimensionality',
      'documentOcr',
      'audioTrackExtraction',
      if (taskType != null || taskWireValue == null) 'taskType',
    };
    final title = _optionalString(value, 'title');
    final outputDimensionality = _optionalInt(value, 'outputDimensionality');
    if (title != null && title.isEmpty) {
      throw const FormatException('embedContentConfig.title must not be empty.');
    }
    if (title != null &&
        (taskWireValue == null ||
            (taskType != null && taskType != GoogleEmbeddingTaskType.retrievalDocument))) {
      throw const FormatException(
        'embedContentConfig.title requires RETRIEVAL_DOCUMENT.',
      );
    }
    if (outputDimensionality != null && outputDimensionality <= 0) {
      throw const FormatException(
        'embedContentConfig.outputDimensionality must be positive.',
      );
    }
    return GoogleEmbedContentConfig._(
      title: title,
      taskType: taskType,
      autoTruncate: _optionalBool(value, 'autoTruncate'),
      outputDimensionality: outputDimensionality,
      documentOcr: _optionalBool(value, 'documentOcr'),
      audioTrackExtraction: _optionalBool(value, 'audioTrackExtraction'),
      extensions: JsonObject(_without(value, knownFields)),
    );
  }

  /// Optional title for a retrieval document.
  final String? title;

  /// The native text embedding task.
  final GoogleEmbeddingTaskType? taskType;

  /// Whether Google may truncate overlong input.
  final bool? autoTruncate;

  /// Requested output vector length.
  final int? outputDimensionality;

  /// Native document OCR selection where the API supports it.
  final bool? documentOcr;

  /// Whether the model extracts a video's audio track.
  final bool? audioTrackExtraction;

  /// Fields outside the typed 2026-09-12 snapshot.
  final JsonObject extensions;

  /// Encodes the complete native configuration.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    'title': ?title,
    if (taskType case final value?) 'taskType': value.wireValue,
    'autoTruncate': ?autoTruncate,
    'outputDimensionality': ?outputDimensionality,
    'documentOcr': ?documentOcr,
    'audioTrackExtraction': ?audioTrackExtraction,
  });
}

/// Immutable Google embedding defaults or per-call overrides.
final class GoogleEmbeddingOptions {
  /// Creates options with explicit inherit, set, and clear semantics.
  GoogleEmbeddingOptions({
    Setting<GoogleEmbeddingTaskType> taskType = const Setting<GoogleEmbeddingTaskType>.inherit(),
    Setting<String> title = const Setting<String>.inherit(),
    Setting<int> dimensions = const Setting<int>.inherit(),
    JsonObject? extraBody,
  }) : taskType = _normalizeSetting(taskType),
       title = _normalizeSetting(title),
       dimensions = _normalizeSetting(dimensions),
       extraBody = extraBody ?? JsonObject({}) {
    final configuredTitle = this.title.resolve(null);
    if (configuredTitle != null && configuredTitle.isEmpty) {
      throw ArgumentError.value(configuredTitle, 'title', 'must not be empty');
    }
    final configuredDimensions = this.dimensions.resolve(null);
    if (configuredDimensions != null && configuredDimensions <= 0) {
      throw ArgumentError.value(configuredDimensions, 'dimensions', 'must be positive');
    }
    _rejectCollisions(this.extraBody, _requestFields, 'extraBody');
  }

  /// Native task type for models that support it.
  final Setting<GoogleEmbeddingTaskType> taskType;

  /// Native retrieval-document title.
  final Setting<String> title;

  /// Requested output vector length.
  final Setting<int> dimensions;

  /// Forward-compatible request fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Resolves the task type against model defaults.
  GoogleEmbeddingTaskType? resolveTaskType(GoogleEmbeddingOptions? call) =>
      call == null ? taskType.resolve(null) : call.taskType.resolve(taskType.resolve(null));

  /// Resolves the title against model defaults.
  String? resolveTitle(GoogleEmbeddingOptions? call) =>
      call == null ? title.resolve(null) : call.title.resolve(title.resolve(null));

  /// Resolves dimensions against model defaults.
  int? resolveDimensions(GoogleEmbeddingOptions? call) =>
      call == null ? dimensions.resolve(null) : call.dimensions.resolve(dimensions.resolve(null));

  /// Merges extra fields, with per-call values replacing model defaults.
  JsonObject resolveExtraBody(GoogleEmbeddingOptions? call) => JsonObject({
    ...extraBody.toDart(),
    ...?call?.extraBody.toDart(),
  });
}

/// One typed native request for `models.embedContent`.
final class GoogleEmbedContentRequest {
  /// Creates a request for an authoritative `models/{id}` resource.
  GoogleEmbedContentRequest({
    required String model,
    required this.content,
    this.config,
    JsonObject? extraBody,
  }) : model = googleEmbeddingModelName(model),
       extraBody = extraBody ?? JsonObject({}) {
    _rejectCollisions(this.extraBody, _requestFields, 'extraBody');
  }

  /// Decodes a request body for the model carried in its resource path.
  factory GoogleEmbedContentRequest.fromJson({
    required String model,
    required JsonObject json,
  }) {
    final value = json.toDart();
    return GoogleEmbedContentRequest(
      model: model,
      content: GoogleContent.fromJson(JsonObject.fromDart(value['content'])),
      config: switch (value['embedContentConfig']) {
        null => null,
        final Object config => GoogleEmbedContentConfig.fromJson(JsonObject.fromDart(config)),
      },
      extraBody: JsonObject(_without(value, _requestFields)),
    );
  }

  /// Authoritative Google model resource name.
  final String model;

  /// One content value whose ordered parts produce one vector.
  final GoogleContent content;

  /// Typed native embedding configuration.
  final GoogleEmbedContentConfig? config;

  /// Forward-compatible request fields.
  final JsonObject extraBody;

  /// Encodes the request body; [model] remains in the resource path.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'content': content.toJson().toDart(),
    if (config case final value?) 'embedContentConfig': value.toJson().toDart(),
  });

  Map<String, Object?> _toBatchDart() => {
    'model': model,
    ...toJson().toDart(),
  };
}

/// One synchronous native `models.batchEmbedContents` request.
final class GoogleBatchEmbedContentsRequest {
  /// Creates a batch whose inner requests all target [model].
  GoogleBatchEmbedContentsRequest({
    required String model,
    required Iterable<GoogleEmbedContentRequest> requests,
    JsonObject? extraBody,
  }) : model = googleEmbeddingModelName(model),
       requests = List.unmodifiable(requests),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.requests.isEmpty) {
      throw ArgumentError.value(requests, 'requests', 'must not be empty');
    }
    if (this.requests.any((request) => request.model != this.model)) {
      throw ArgumentError.value(
        requests,
        'requests',
        'must all target the batch model',
      );
    }
    _rejectCollisions(this.extraBody, _batchRequestFields, 'extraBody');
  }

  /// Decodes a synchronous batch body for the model in its resource path.
  factory GoogleBatchEmbedContentsRequest.fromJson({
    required String model,
    required JsonObject json,
  }) {
    final value = json.toDart();
    return GoogleBatchEmbedContentsRequest(
      model: model,
      requests: _list(value, 'requests').map((item) {
        final request = _object(item, 'batch embed request');
        final requestModel = _string(request, 'model');
        return GoogleEmbedContentRequest.fromJson(
          model: requestModel,
          json: JsonObject(_without(request, {'model'})),
        );
      }),
      extraBody: JsonObject(_without(value, _batchRequestFields)),
    );
  }

  /// Authoritative Google model resource name.
  final String model;

  /// Ordered native embed requests.
  final List<GoogleEmbedContentRequest> requests;

  /// Forward-compatible batch fields.
  final JsonObject extraBody;

  /// Encodes one synchronous batch request.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'requests': requests.map((request) => request._toBatchDart()).toList(),
  });
}

/// A native Google embedding vector.
final class GoogleContentEmbedding {
  GoogleContentEmbedding._({
    required this.values,
    required this.shape,
    required this.raw,
    required this.extensions,
  });

  /// Decodes an embedding while retaining unknown fields.
  factory GoogleContentEmbedding.fromJson(JsonObject json) {
    final value = json.toDart();
    final values = _list(value, 'values');
    if (values.any((item) => item is! num)) {
      throw const FormatException('embedding.values must contain numbers.');
    }
    final shape = switch (value['shape']) {
      null => const <int>[],
      final List<Object?> items when items.every((item) => item is int) => items.cast<int>(),
      _ => throw const FormatException('embedding.shape must contain integers.'),
    };
    return GoogleContentEmbedding._(
      values: List.unmodifiable(values.cast<num>().map((value) => value.toDouble())),
      shape: List.unmodifiable(shape),
      raw: json,
      extensions: JsonObject(_without(value, {'values', 'shape'})),
    );
  }

  /// Numeric embedding values.
  final List<double> values;

  /// Native soft-token tensor shape, when returned.
  final List<int> shape;

  /// Complete native embedding object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// Native token accounting for an embedding request.
final class GoogleEmbeddingUsageMetadata {
  GoogleEmbeddingUsageMetadata._({
    required this.promptTokenCount,
    required this.promptTokenDetails,
    required this.raw,
    required this.extensions,
  });

  /// Decodes usage metadata while retaining modality details and unknown fields.
  factory GoogleEmbeddingUsageMetadata.fromJson(JsonObject json) {
    final value = json.toDart();
    final details = switch (value['promptTokenDetails']) {
      null => const <Object?>[],
      final List<Object?> values => values,
      _ => throw const FormatException('promptTokenDetails must be an array.'),
    };
    return GoogleEmbeddingUsageMetadata._(
      promptTokenCount: _optionalInt(value, 'promptTokenCount'),
      promptTokenDetails: List.unmodifiable(details.map(JsonObject.fromDart)),
      raw: json,
      extensions: JsonObject(_without(value, {'promptTokenCount', 'promptTokenDetails'})),
    );
  }

  /// Total prompt tokens counted by Google.
  final int? promptTokenCount;

  /// Native per-modality token accounting.
  final List<JsonObject> promptTokenDetails;

  /// Complete native usage object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Converts available native accounting to the common usage contract.
  Usage? toCommon() => switch (promptTokenCount) {
    final count? => Usage(inputTokens: count, totalTokens: count),
    null => null,
  };
}

/// One typed native `models.embedContent` response.
final class GoogleEmbedContentResponse {
  GoogleEmbedContentResponse._({
    required this.embedding,
    required this.usageMetadata,
    required this.raw,
    required this.extensions,
  });

  /// Decodes a response while retaining unknown fields.
  factory GoogleEmbedContentResponse.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleEmbedContentResponse._(
      embedding: GoogleContentEmbedding.fromJson(JsonObject.fromDart(value['embedding'])),
      usageMetadata: switch (value['usageMetadata']) {
        null => null,
        final Object usage => GoogleEmbeddingUsageMetadata.fromJson(JsonObject.fromDart(usage)),
      },
      raw: json,
      extensions: JsonObject(_without(value, {'embedding', 'usageMetadata'})),
    );
  }

  /// The returned embedding.
  final GoogleContentEmbedding embedding;

  /// Native token accounting, when returned.
  final GoogleEmbeddingUsageMetadata? usageMetadata;

  /// Complete native response.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One typed synchronous `models.batchEmbedContents` response.
final class GoogleBatchEmbedContentsResponse {
  GoogleBatchEmbedContentsResponse._({
    required this.embeddings,
    required this.usageMetadata,
    required this.raw,
    required this.extensions,
  });

  /// Decodes an ordered synchronous batch response.
  factory GoogleBatchEmbedContentsResponse.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleBatchEmbedContentsResponse._(
      embeddings: List.unmodifiable(
        _list(
          value,
          'embeddings',
        ).map((item) => GoogleContentEmbedding.fromJson(JsonObject.fromDart(item))),
      ),
      usageMetadata: switch (value['usageMetadata']) {
        null => null,
        final Object usage => GoogleEmbeddingUsageMetadata.fromJson(JsonObject.fromDart(usage)),
      },
      raw: json,
      extensions: JsonObject(_without(value, {'embeddings', 'usageMetadata'})),
    );
  }

  /// Embeddings in request order.
  final List<GoogleContentEmbedding> embeddings;

  /// Native token accounting, when returned.
  final GoogleEmbeddingUsageMetadata? usageMetadata;

  /// Complete native response.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

Setting<T> _normalizeSetting<T>(Setting<T> setting) => switch (setting) {
  InheritSetting() => Setting<T>.inherit(),
  ClearSetting() => Setting<T>.clear(),
  SetSetting(:final value) => Setting<T>.set(value),
};

GoogleEmbeddingTaskType? _taskType(String? value) {
  if (value == null) return null;
  for (final taskType in GoogleEmbeddingTaskType.values) {
    if (taskType.wireValue == value) return taskType;
  }
  return null;
}

void _rejectCollisions(JsonObject value, Set<String> fields, String name) {
  final collision = value.toDart().keys.where(fields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(collision, name, 'collides with a typed field');
  }
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object.');
  }
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null || field is String) return field as String?;
  throw FormatException('$key must be a string or null.');
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null || field is int) return field as int?;
  throw FormatException('$key must be an integer or null.');
}

bool? _optionalBool(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null || field is bool) return field as bool?;
  throw FormatException('$key must be a boolean or null.');
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) => {
  for (final entry in value.entries)
    if (!keys.contains(entry.key)) entry.key: entry.value,
};

const _configFields = {
  'title',
  'taskType',
  'autoTruncate',
  'outputDimensionality',
  'documentOcr',
  'audioTrackExtraction',
};
const _requestFields = {'content', 'embedContentConfig'};
const _batchRequestFields = {'requests'};

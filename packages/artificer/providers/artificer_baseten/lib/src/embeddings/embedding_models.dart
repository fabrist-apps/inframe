import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// Immutable Baseten embedding defaults or per-call overrides.
final class BasetenEmbeddingOptions {
  /// Creates typed dedicated embedding options.
  BasetenEmbeddingOptions({
    Setting<int> dimensions = const Setting<int>.inherit(),
    JsonObject? extraBody,
  }) : dimensions = _normalizeSetting(dimensions),
       extraBody = extraBody ?? JsonObject({}) {
    final value = this.dimensions.resolve(null);
    if (value != null && value <= 0) {
      throw ArgumentError.value(value, 'dimensions', 'must be positive');
    }
    _rejectCollisions(this.extraBody, _requestFields);
  }

  /// Requested vector dimensions.
  final Setting<int> dimensions;

  /// Forward-compatible fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Resolves dimensions against model defaults.
  int? resolveDimensions(BasetenEmbeddingOptions? call) =>
      call == null ? dimensions.resolve(null) : call.dimensions.resolve(dimensions.resolve(null));

  /// Merges forward-compatible fields with per-call fields taking precedence.
  JsonObject resolveExtraBody(BasetenEmbeddingOptions? call) => JsonObject({
    ...extraBody.toDart(),
    ...?call?.extraBody.toDart(),
  });
}

/// A typed native request for `POST /embeddings` on a compatible deployment.
final class BasetenEmbeddingRequest {
  /// Creates a native text embedding batch.
  BasetenEmbeddingRequest({
    required String model,
    required Iterable<String> input,
    this.dimensions,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       input = List.unmodifiable(input),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.input.isEmpty || this.input.any((value) => value.isEmpty)) {
      throw ArgumentError.value(input, 'input', 'must contain nonempty text');
    }
    if (dimensions != null && dimensions! <= 0) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
    _rejectCollisions(this.extraBody, _requestFields);
  }

  /// Served model name, kept separate from the deployment URL.
  final String model;

  /// Ordered text inputs.
  final List<String> input;

  /// Requested vector dimensions.
  final int? dimensions;

  /// Forward-compatible fields outside the typed snapshot.
  final JsonObject extraBody;

  /// Encodes this native request.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'input': input,
    'dimensions': ?dimensions,
  });
}

/// One native indexed embedding.
final class BasetenEmbeddingData {
  /// Decodes one indexed float embedding.
  factory BasetenEmbeddingData.fromDart(Object? input) {
    final value = _object(input, 'embedding item');
    final vector = value['embedding'];
    if (vector is! List<Object?> || vector.any((item) => item is! num)) {
      throw const FormatException('embedding must be a number array.');
    }
    return BasetenEmbeddingData._(
      index: _integer(value, 'index'),
      vector: vector.cast<num>().map((item) => item.toDouble()),
      raw: JsonObject(value),
      extensions: JsonObject(_without(value, {'object', 'index', 'embedding'})),
    );
  }

  BasetenEmbeddingData._({
    required this.index,
    required Iterable<double> vector,
    required this.raw,
    required this.extensions,
  }) : vector = List.unmodifiable(vector);

  /// Request-order index.
  final int index;

  /// Native vector values.
  final List<double> vector;

  /// Complete native item.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// Native embedding token accounting.
final class BasetenEmbeddingUsage {
  /// Decodes embedding usage.
  factory BasetenEmbeddingUsage.fromDart(Object? input) {
    final value = _object(input, 'embedding usage');
    return BasetenEmbeddingUsage._(
      promptTokens: _integer(value, 'prompt_tokens'),
      totalTokens: _integer(value, 'total_tokens'),
      raw: JsonObject(value),
    );
  }

  BasetenEmbeddingUsage._({
    required this.promptTokens,
    required this.totalTokens,
    required this.raw,
  });

  /// Input token count.
  final int promptTokens;

  /// Total token count.
  final int totalTokens;

  /// Complete native usage object.
  final JsonObject raw;
}

/// One typed native embedding response.
final class BasetenEmbeddingResponse {
  /// Decodes a native compatible embedding response.
  factory BasetenEmbeddingResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return BasetenEmbeddingResponse._(
      model: _string(value, 'model'),
      data: _list(value, 'data').map(BasetenEmbeddingData.fromDart),
      usage: value['usage'] == null ? null : BasetenEmbeddingUsage.fromDart(value['usage']),
      raw: raw,
      extensions: JsonObject(_without(value, {'object', 'model', 'data', 'usage'})),
    );
  }

  BasetenEmbeddingResponse._({
    required this.model,
    required Iterable<BasetenEmbeddingData> data,
    required this.usage,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Actual served model name.
  final String model;

  /// Provider-indexed embeddings.
  final List<BasetenEmbeddingData> data;

  /// Token usage when returned.
  final BasetenEmbeddingUsage? usage;

  /// Complete native response.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

Setting<T> _normalizeSetting<T>(Setting<T> setting) => switch (setting) {
  InheritSetting<T>() => Setting<T>.inherit(),
  SetSetting<T>(:final value) => Setting<T>.set(value),
  ClearSetting<T>() => Setting<T>.clear(),
};

const _requestFields = {'model', 'input', 'dimensions'};

void _rejectCollisions(JsonObject extraBody, Set<String> fields) {
  final collision = extraBody.toDart().keys.where(fields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(extraBody, 'extraBody', 'field "$collision" is typed');
  }
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
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
  if (field is! String || field.isEmpty) throw FormatException('$key must be a string.');
  return field;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

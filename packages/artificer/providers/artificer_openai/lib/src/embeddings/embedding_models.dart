import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// Native embedding representation.
enum OpenAIEmbeddingEncoding {
  /// Numeric floating-point arrays.
  float('float'),

  /// Base64-encoded binary vectors.
  base64('base64');

  const OpenAIEmbeddingEncoding(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Immutable OpenAI embedding defaults or per-call overrides.
final class OpenAIEmbeddingOptions {
  /// Creates typed embedding options.
  OpenAIEmbeddingOptions({
    Setting<int> dimensions = const Setting<int>.inherit(),
    Setting<OpenAIEmbeddingEncoding> encodingFormat =
        const Setting<OpenAIEmbeddingEncoding>.inherit(),
    Setting<String> user = const Setting<String>.inherit(),
    JsonObject? extraBody,
  }) : dimensions = _normalizeSetting(dimensions),
       encodingFormat = _normalizeSetting(encodingFormat),
       user = _normalizeSetting(user),
       extraBody = extraBody ?? JsonObject({}) {
    final value = this.dimensions.resolve(null);
    if (value != null && value <= 0) {
      throw ArgumentError.value(value, 'dimensions', 'must be positive');
    }
    _rejectCollisions(this.extraBody, _typedRequestFields);
  }

  /// Requested vector dimensions.
  final Setting<int> dimensions;

  /// Requested native vector encoding.
  final Setting<OpenAIEmbeddingEncoding> encodingFormat;

  /// Native end-user identifier.
  final Setting<String> user;

  /// Forward-compatible fields outside this typed snapshot.
  final JsonObject extraBody;

  /// Resolves dimensions against model defaults.
  int? resolveDimensions(OpenAIEmbeddingOptions? call) =>
      call == null ? dimensions.resolve(null) : call.dimensions.resolve(dimensions.resolve(null));

  /// Resolves encoding against model defaults.
  OpenAIEmbeddingEncoding? resolveEncodingFormat(OpenAIEmbeddingOptions? call) => call == null
      ? encodingFormat.resolve(null)
      : call.encodingFormat.resolve(encodingFormat.resolve(null));

  /// Resolves the user identifier against model defaults.
  String? resolveUser(OpenAIEmbeddingOptions? call) =>
      call == null ? user.resolve(null) : call.user.resolve(user.resolve(null));

  /// Merges forward-compatible fields with call fields taking precedence.
  JsonObject resolveExtraBody(OpenAIEmbeddingOptions? call) => JsonObject({
    ...extraBody.toDart(),
    ...?call?.extraBody.toDart(),
  });
}

/// One native text or token-ID input.
sealed class OpenAIEmbeddingInput {
  const OpenAIEmbeddingInput();

  /// Encodes the endpoint input value.
  Object toDart();
}

/// One native text input.
final class OpenAITextEmbeddingInput extends OpenAIEmbeddingInput {
  /// Creates a text input.
  OpenAITextEmbeddingInput(String text) : text = _nonEmpty(text, 'text');

  /// Input text.
  final String text;

  @override
  Object toDart() => text;
}

/// One native token-ID input. The SDK does not tokenize text locally.
final class OpenAITokenEmbeddingInput extends OpenAIEmbeddingInput {
  /// Creates a token input.
  OpenAITokenEmbeddingInput(Iterable<int> tokenIds) : tokenIds = List.unmodifiable(tokenIds) {
    if (this.tokenIds.isEmpty || this.tokenIds.any((token) => token < 0)) {
      throw ArgumentError.value(tokenIds, 'tokenIds', 'must contain nonnegative token IDs');
    }
  }

  /// Provider-tokenizer IDs.
  final List<int> tokenIds;

  @override
  Object toDart() => tokenIds;
}

/// A typed native request for `POST /embeddings`.
final class OpenAIEmbeddingRequest {
  /// Creates a native embedding request.
  OpenAIEmbeddingRequest({
    required String model,
    required Iterable<OpenAIEmbeddingInput> input,
    this.dimensions,
    this.encodingFormat,
    this.user,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       input = List.unmodifiable(input),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.input.isEmpty) throw ArgumentError.value(input, 'input', 'must not be empty');
    if (dimensions != null && dimensions! <= 0) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
    _rejectCollisions(this.extraBody, _typedRequestFields);
  }

  /// Provider-local model ID.
  final String model;

  /// Ordered text or token-ID inputs.
  final List<OpenAIEmbeddingInput> input;

  /// Requested vector dimensions.
  final int? dimensions;

  /// Requested native representation.
  final OpenAIEmbeddingEncoding? encodingFormat;

  /// Native end-user identifier.
  final String? user;

  /// Forward-compatible fields outside this typed snapshot.
  final JsonObject extraBody;

  /// Encodes this native request.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'input': input.map((value) => value.toDart()).toList(),
    'dimensions': ?dimensions,
    if (encodingFormat case final value?) 'encoding_format': value.wireValue,
    'user': ?user,
  });
}

/// One native indexed embedding.
final class OpenAIEmbeddingData {
  /// Decodes one indexed embedding.
  factory OpenAIEmbeddingData.fromDart(Object? input) {
    final value = _object(input, 'embedding item');
    final embedding = value['embedding'];
    final decoded = switch (embedding) {
      final String base64 when base64.isNotEmpty => OpenAIBase64Embedding(base64),
      final List<Object?> vector when vector.every((item) => item is num) => OpenAIFloatEmbedding(
        vector.cast<num>(),
      ),
      _ => throw const FormatException('embedding must be a number array or base64 string.'),
    };
    return OpenAIEmbeddingData._(
      index: _integer(value, 'index'),
      embedding: decoded,
      raw: JsonObject(value),
      extensions: JsonObject(_without(value, {'object', 'index', 'embedding'})),
    );
  }

  OpenAIEmbeddingData._({
    required this.index,
    required this.embedding,
    required this.raw,
    required this.extensions,
  });

  /// Request-order index.
  final int index;

  /// Native float or base64 value.
  final OpenAIEmbeddingValue embedding;

  /// Complete native item.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One native embedding value.
sealed class OpenAIEmbeddingValue {
  const OpenAIEmbeddingValue();
}

/// A numeric embedding vector.
final class OpenAIFloatEmbedding extends OpenAIEmbeddingValue {
  /// Creates an immutable numeric vector.
  OpenAIFloatEmbedding(Iterable<num> vector)
    : vector = List.unmodifiable(vector.map((value) => value.toDouble()));

  /// Numeric vector.
  final List<double> vector;
}

/// A base64-encoded native vector.
final class OpenAIBase64Embedding extends OpenAIEmbeddingValue {
  /// Creates an encoded vector.
  OpenAIBase64Embedding(String value) : value = _nonEmpty(value, 'value');

  /// Encoded vector data.
  final String value;
}

/// Native embedding token accounting.
final class OpenAIEmbeddingUsage {
  /// Decodes embedding usage.
  factory OpenAIEmbeddingUsage.fromDart(Object? input) {
    final value = _object(input, 'embedding usage');
    return OpenAIEmbeddingUsage._(
      promptTokens: _integer(value, 'prompt_tokens'),
      totalTokens: _integer(value, 'total_tokens'),
      raw: JsonObject(value),
    );
  }

  OpenAIEmbeddingUsage._({
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
final class OpenAIEmbeddingResponse {
  /// Decodes a native response.
  factory OpenAIEmbeddingResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIEmbeddingResponse._(
      model: _string(value, 'model'),
      data: _list(value, 'data').map(OpenAIEmbeddingData.fromDart),
      usage: value['usage'] == null ? null : OpenAIEmbeddingUsage.fromDart(value['usage']),
      raw: raw,
      extensions: JsonObject(_without(value, {'object', 'model', 'data', 'usage'})),
    );
  }

  OpenAIEmbeddingResponse._({
    required this.model,
    required Iterable<OpenAIEmbeddingData> data,
    required this.usage,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Actual provider model ID.
  final String model;

  /// Provider-indexed embeddings.
  final List<OpenAIEmbeddingData> data;

  /// Token usage when returned.
  final OpenAIEmbeddingUsage? usage;

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

const _typedRequestFields = {'model', 'input', 'dimensions', 'encoding_format', 'user'};

void _rejectCollisions(JsonObject extraBody, Set<String> typedFields) {
  final collision = extraBody.toDart().keys.where(typedFields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(collision, 'extraBody', 'collides with a typed field');
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
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

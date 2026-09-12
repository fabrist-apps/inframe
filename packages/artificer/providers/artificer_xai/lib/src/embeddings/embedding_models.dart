import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// Native embedding representation.
enum XaiEmbeddingEncoding {
  /// Numeric floating-point arrays.
  float('float'),

  /// Base64-encoded binary vectors.
  base64('base64');

  const XaiEmbeddingEncoding(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Immutable Xai embedding defaults or per-call overrides.
final class XaiEmbeddingOptions {
  /// Creates typed embedding options.
  XaiEmbeddingOptions({
    Setting<int> dimensions = const Setting<int>.inherit(),
    Setting<XaiEmbeddingEncoding> encodingFormat = const Setting<XaiEmbeddingEncoding>.inherit(),
    Setting<bool> preview = const Setting<bool>.inherit(),
    Setting<String> user = const Setting<String>.inherit(),
    JsonObject? extraBody,
  }) : dimensions = _normalizeSetting(dimensions),
       encodingFormat = _normalizeSetting(encodingFormat),
       preview = _normalizeSetting(preview),
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
  final Setting<XaiEmbeddingEncoding> encodingFormat;

  /// Whether to opt into a preview embedding model contract.
  final Setting<bool> preview;

  /// Native end-user identifier.
  final Setting<String> user;

  /// Forward-compatible fields outside this typed snapshot.
  final JsonObject extraBody;

  /// Resolves dimensions against model defaults.
  int? resolveDimensions(XaiEmbeddingOptions? call) =>
      call == null ? dimensions.resolve(null) : call.dimensions.resolve(dimensions.resolve(null));

  /// Resolves encoding against model defaults.
  XaiEmbeddingEncoding? resolveEncodingFormat(XaiEmbeddingOptions? call) => call == null
      ? encodingFormat.resolve(null)
      : call.encodingFormat.resolve(encodingFormat.resolve(null));

  /// Resolves preview opt-in against model defaults.
  bool? resolvePreview(XaiEmbeddingOptions? call) =>
      call == null ? preview.resolve(null) : call.preview.resolve(preview.resolve(null));

  /// Resolves the user identifier against model defaults.
  String? resolveUser(XaiEmbeddingOptions? call) =>
      call == null ? user.resolve(null) : call.user.resolve(user.resolve(null));

  /// Merges forward-compatible fields with call fields taking precedence.
  JsonObject resolveExtraBody(XaiEmbeddingOptions? call) => JsonObject({
    ...extraBody.toDart(),
    ...?call?.extraBody.toDart(),
  });
}

/// One native text input.
sealed class XaiEmbeddingInput {
  const XaiEmbeddingInput();

  /// Encodes the endpoint input value.
  Object toDart();
}

/// One native text input.
final class XaiTextEmbeddingInput extends XaiEmbeddingInput {
  /// Creates a text input.
  XaiTextEmbeddingInput(String text) : text = _nonEmpty(text, 'text');

  /// Input text.
  final String text;

  @override
  Object toDart() => text;
}

/// A typed native request for `POST /embeddings`.
final class XaiEmbeddingRequest {
  /// Creates a native embedding request.
  XaiEmbeddingRequest({
    required String model,
    required Iterable<XaiEmbeddingInput> input,
    this.dimensions,
    this.encodingFormat,
    this.preview,
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

  /// Ordered text inputs.
  final List<XaiEmbeddingInput> input;

  /// Requested vector dimensions.
  final int? dimensions;

  /// Requested native representation.
  final XaiEmbeddingEncoding? encodingFormat;

  /// Whether to opt into a preview embedding model contract.
  final bool? preview;

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
    'preview': ?preview,
    'user': ?user,
  });
}

/// One native indexed embedding.
final class XaiEmbeddingData {
  /// Decodes one indexed embedding.
  factory XaiEmbeddingData.fromDart(Object? input) {
    final value = _object(input, 'embedding item');
    final embedding = value['embedding'];
    final decoded = switch (embedding) {
      final String base64 when base64.isNotEmpty => XaiBase64Embedding(base64),
      final List<Object?> vector when vector.every((item) => item is num) => XaiFloatEmbedding(
        vector.cast<num>(),
      ),
      _ => throw const FormatException('embedding must be a number array or base64 string.'),
    };
    return XaiEmbeddingData._(
      index: _integer(value, 'index'),
      embedding: decoded,
      raw: JsonObject(value),
      extensions: JsonObject(_without(value, {'object', 'index', 'embedding'})),
    );
  }

  XaiEmbeddingData._({
    required this.index,
    required this.embedding,
    required this.raw,
    required this.extensions,
  });

  /// Request-order index.
  final int index;

  /// Native float or base64 value.
  final XaiEmbeddingValue embedding;

  /// Complete native item.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One native embedding value.
sealed class XaiEmbeddingValue {
  const XaiEmbeddingValue();
}

/// A numeric embedding vector.
final class XaiFloatEmbedding extends XaiEmbeddingValue {
  /// Creates an immutable numeric vector.
  XaiFloatEmbedding(Iterable<num> vector)
    : vector = List.unmodifiable(vector.map((value) => value.toDouble()));

  /// Numeric vector.
  final List<double> vector;
}

/// A base64-encoded native vector.
final class XaiBase64Embedding extends XaiEmbeddingValue {
  /// Creates an encoded vector.
  XaiBase64Embedding(String value) : value = _nonEmpty(value, 'value');

  /// Encoded vector data.
  final String value;
}

/// Native embedding token accounting.
final class XaiEmbeddingUsage {
  /// Decodes embedding usage.
  factory XaiEmbeddingUsage.fromDart(Object? input) {
    final value = _object(input, 'embedding usage');
    return XaiEmbeddingUsage._(
      promptTokens: _optionalInteger(value, 'prompt_tokens'),
      totalTokens: _optionalInteger(value, 'total_tokens'),
      raw: JsonObject(value),
    );
  }

  XaiEmbeddingUsage._({
    required this.promptTokens,
    required this.totalTokens,
    required this.raw,
  });

  /// Input token count.
  final int? promptTokens;

  /// Total token count.
  final int? totalTokens;

  /// Complete native usage object.
  final JsonObject raw;
}

/// One typed native embedding response.
final class XaiEmbeddingResponse {
  /// Decodes a native response.
  factory XaiEmbeddingResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiEmbeddingResponse._(
      model: _string(value, 'model'),
      data: _list(value, 'data').map(XaiEmbeddingData.fromDart),
      usage: value['usage'] == null ? null : XaiEmbeddingUsage.fromDart(value['usage']),
      raw: raw,
      extensions: JsonObject(_without(value, {'object', 'model', 'data', 'usage'})),
    );
  }

  XaiEmbeddingResponse._({
    required this.model,
    required Iterable<XaiEmbeddingData> data,
    required this.usage,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Actual provider model ID.
  final String model;

  /// Provider-indexed embeddings.
  final List<XaiEmbeddingData> data;

  /// Token usage when returned.
  final XaiEmbeddingUsage? usage;

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

const _typedRequestFields = {
  'model',
  'input',
  'dimensions',
  'encoding_format',
  'preview',
  'user',
};

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

int? _optionalInteger(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int) throw FormatException('$key must be an integer or null.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

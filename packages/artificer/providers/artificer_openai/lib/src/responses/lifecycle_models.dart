import 'package:artificer_core/json.dart';
import 'package:artificer_openai/src/responses/response_models.dart';

/// Sort order for one explicitly requested native page.
enum OpenAIListOrder {
  /// Oldest item first.
  ascending('asc'),

  /// Newest item first.
  descending('desc');

  const OpenAIListOrder(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// The acknowledgement returned after explicitly deleting a stored response.
final class OpenAIDeletedResponse {
  /// Decodes a deletion acknowledgement.
  factory OpenAIDeletedResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIDeletedResponse._(
      id: _string(value, 'id'),
      deleted: _boolean(value, 'deleted'),
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'object', 'deleted'})),
    );
  }

  OpenAIDeletedResponse._({
    required this.id,
    required this.deleted,
    required this.raw,
    required this.extensions,
  });

  /// Deleted response ID.
  final String id;

  /// Whether deletion succeeded.
  final bool deleted;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One explicitly fetched page of response input items.
final class OpenAIResponseInputItemPage {
  /// Decodes one page without following its cursor.
  factory OpenAIResponseInputItemPage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIResponseInputItemPage._(
      data: _list(value, 'data').map(OpenAIResponseOutputItem.fromDart),
      hasMore: _boolean(value, 'has_more'),
      firstId: _nullableString(value, 'first_id'),
      lastId: _nullableString(value, 'last_id'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'object', 'data', 'has_more', 'first_id', 'last_id'}),
      ),
    );
  }

  OpenAIResponseInputItemPage._({
    required Iterable<OpenAIResponseOutputItem> data,
    required this.hasMore,
    required this.firstId,
    required this.lastId,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Items in this page.
  final List<OpenAIResponseOutputItem> data;

  /// Whether another page can be requested.
  final bool hasMore;

  /// First native item ID, when present.
  final String? firstId;

  /// Last native item ID, when present.
  final String? lastId;

  /// Complete native page.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// A native request for input-token counting.
final class OpenAIResponseInputTokensRequest {
  /// Creates a token-count request.
  OpenAIResponseInputTokensRequest({
    required String model,
    required Iterable<OpenAIResponseInputItem> input,
    Object? previousResponseId = _omitted,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       input = List.unmodifiable(input),
       _previousResponseId = _nullableStringValue(previousResponseId, 'previousResponseId'),
       _hasPreviousResponseId = !identical(previousResponseId, _omitted),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.input.isEmpty) throw ArgumentError.value(input, 'input', 'must not be empty');
    _rejectCollisions(this.extraBody, {'model', 'input', 'previous_response_id'});
  }

  /// Provider-local model ID.
  final String model;

  /// Explicit input history.
  final List<OpenAIResponseInputItem> input;

  final String? _previousResponseId;
  final bool _hasPreviousResponseId;

  /// Forward-compatible fields outside this typed snapshot.
  final JsonObject extraBody;

  /// Encodes the native request, preserving omitted versus explicit null.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'input': input.map((item) => item.toDart()).toList(),
    if (_hasPreviousResponseId) 'previous_response_id': _previousResponseId,
  });
}

/// The result of an explicit input-token count.
final class OpenAIResponseInputTokens {
  /// Decodes token count data.
  factory OpenAIResponseInputTokens.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIResponseInputTokens._(
      inputTokens: _integer(value, 'input_tokens'),
      raw: raw,
      extensions: JsonObject(_without(value, {'object', 'input_tokens'})),
    );
  }

  OpenAIResponseInputTokens._({
    required this.inputTokens,
    required this.raw,
    required this.extensions,
  });

  /// Counted input tokens.
  final int inputTokens;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// A native request for explicit response compaction.
final class OpenAICompactResponseRequest {
  /// Creates a compaction request.
  OpenAICompactResponseRequest({
    required String model,
    required Iterable<OpenAIResponseInputItem> input,
    this.instructions,
    this.previousResponseId,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       input = List.unmodifiable(input),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.input.isEmpty) throw ArgumentError.value(input, 'input', 'must not be empty');
    _rejectCollisions(this.extraBody, {
      'model',
      'input',
      'instructions',
      'previous_response_id',
    });
  }

  /// Provider-local model ID.
  final String model;

  /// Explicit input to compact.
  final List<OpenAIResponseInputItem> input;

  /// Instructions used for this compaction only.
  final String? instructions;

  /// Stored response explicitly referenced by the caller.
  final String? previousResponseId;

  /// Forward-compatible fields outside this typed snapshot.
  final JsonObject extraBody;

  /// Encodes the native request.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'input': input.map((item) => item.toDart()).toList(),
    'instructions': ?instructions,
    'previous_response_id': ?previousResponseId,
  });
}

/// One explicitly created compacted response.
final class OpenAICompactResponse {
  /// Decodes compacted response data.
  factory OpenAICompactResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAICompactResponse._(
      id: _string(value, 'id'),
      createdAt: _integer(value, 'created_at'),
      output: _list(value, 'output').map(OpenAIResponseOutputItem.fromDart),
      usage: OpenAIResponseUsage.fromDart(value['usage']),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'id', 'object', 'created_at', 'output', 'usage'}),
      ),
    );
  }

  OpenAICompactResponse._({
    required this.id,
    required this.createdAt,
    required Iterable<OpenAIResponseOutputItem> output,
    required this.usage,
    required this.raw,
    required this.extensions,
  }) : output = List.unmodifiable(output);

  /// Compaction ID.
  final String id;

  /// Unix creation timestamp.
  final int createdAt;

  /// Ordered compacted output items.
  final List<OpenAIResponseOutputItem> output;

  /// Compaction token accounting.
  final OpenAIResponseUsage usage;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

const _omitted = Object();

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

String? _nullableStringValue(Object? value, String name) {
  if (identical(value, _omitted) || value == null) return null;
  if (value is! String || value.isEmpty) {
    throw ArgumentError.value(value, name, 'must be a nonempty string or null');
  }
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

String? _nullableString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string or null.');
  return field;
}

bool _boolean(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! bool) throw FormatException('$key must be a boolean.');
  return field;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

void _rejectCollisions(JsonObject extraBody, Set<String> typedFields) {
  final collision = extraBody.toDart().keys.where(typedFields.contains).firstOrNull;
  if (collision != null) {
    throw ArgumentError.value(collision, 'extraBody', 'collides with a typed field');
  }
}

import 'package:artificer_core/json.dart';
import 'package:artificer_xai/src/responses/response_models.dart';

/// Sort order for one explicitly requested native page.
enum XaiListOrder {
  /// Oldest item first.
  ascending('asc'),

  /// Newest item first.
  descending('desc');

  const XaiListOrder(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// The acknowledgement returned after explicitly deleting a stored response.
final class XaiDeletedResponse {
  /// Decodes a deletion acknowledgement.
  factory XaiDeletedResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiDeletedResponse._(
      id: _string(value, 'id'),
      deleted: _boolean(value, 'deleted'),
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'object', 'deleted'})),
    );
  }

  XaiDeletedResponse._({
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
final class XaiResponseInputItemPage {
  /// Decodes one page without following its cursor.
  factory XaiResponseInputItemPage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiResponseInputItemPage._(
      data: _list(value, 'data').map(XaiResponseOutputItem.fromDart),
      hasMore: _boolean(value, 'has_more'),
      firstId: _nullableString(value, 'first_id'),
      lastId: _nullableString(value, 'last_id'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'object', 'data', 'has_more', 'first_id', 'last_id'}),
      ),
    );
  }

  XaiResponseInputItemPage._({
    required Iterable<XaiResponseOutputItem> data,
    required this.hasMore,
    required this.firstId,
    required this.lastId,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Items in this page.
  final List<XaiResponseOutputItem> data;

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

/// A native request for explicit response compaction.
final class XaiCompactResponseRequest {
  /// Creates a compaction request.
  XaiCompactResponseRequest({
    required String model,
    required Iterable<XaiResponseInputItem> input,
    JsonObject? extraBody,
  }) : model = _nonEmpty(model, 'model'),
       input = List.unmodifiable(input),
       extraBody = extraBody ?? JsonObject({}) {
    if (this.input.isEmpty) throw ArgumentError.value(input, 'input', 'must not be empty');
    _rejectCollisions(this.extraBody, {'model', 'input'});
  }

  /// Provider-local model ID.
  final String model;

  /// Explicit input to compact.
  final List<XaiResponseInputItem> input;

  /// Forward-compatible fields outside this typed snapshot.
  final JsonObject extraBody;

  /// Encodes the native request.
  JsonObject toJson() => JsonObject({
    ...extraBody.toDart(),
    'model': model,
    'input': input.map((item) => item.toDart()).toList(),
  });
}

/// One explicitly created compacted response.
final class XaiCompactResponse {
  /// Decodes compacted response data.
  factory XaiCompactResponse.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiCompactResponse._(
      id: _string(value, 'id'),
      createdAt: _integer(value, 'created_at'),
      model: _string(value, 'model'),
      output: _list(value, 'output').map(XaiResponseOutputItem.fromDart),
      usage: value['usage'] == null ? null : XaiResponseUsage.fromDart(value['usage']),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'id', 'object', 'created_at', 'model', 'output', 'usage'}),
      ),
    );
  }

  XaiCompactResponse._({
    required this.id,
    required this.createdAt,
    required this.model,
    required Iterable<XaiResponseOutputItem> output,
    required this.usage,
    required this.raw,
    required this.extensions,
  }) : output = List.unmodifiable(output);

  /// Compaction ID.
  final String id;

  /// Unix creation timestamp.
  final int createdAt;

  /// Model used to compact the input.
  final String model;

  /// Ordered compacted output items.
  final List<XaiResponseOutputItem> output;

  /// Compaction token accounting.
  final XaiResponseUsage? usage;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
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

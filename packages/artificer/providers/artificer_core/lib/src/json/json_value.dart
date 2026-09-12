import 'dart:collection';
import 'dart:convert';

/// A validated, immutable JSON wire value.
sealed class JsonValue {
  const JsonValue();

  /// Copies and validates a Dart value at the JSON boundary.
  factory JsonValue.fromDart(Object? value) => _JsonConverter().convert(value);

  /// Parses and validates JSON source text.
  factory JsonValue.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source) as Object?;
    } on FormatException {
      rethrow;
    }
    return JsonValue.fromDart(decoded);
  }

  /// Returns an immutable Dart representation.
  Object? toDart();

  /// Encodes this value as JSON text.
  String encode() => jsonEncode(toDart());
}

/// JSON null.
final class JsonNull extends JsonValue {
  const JsonNull();

  @override
  Null toDart() => null;
}

/// A JSON boolean.
final class JsonBoolean extends JsonValue {
  const JsonBoolean(this.value);

  final bool value;

  @override
  bool toDart() => value;
}

/// A finite JSON number.
final class JsonNumber extends JsonValue {
  JsonNumber(this.value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
  }

  final num value;

  @override
  num toDart() => value;
}

/// A JSON string.
final class JsonString extends JsonValue {
  const JsonString(this.value);

  final String value;

  @override
  String toDart() => value;
}

/// An immutable JSON array.
final class JsonArray extends JsonValue {
  JsonArray(Iterable<Object?> values)
    : this._(_JsonConverter().convertArray(values.toList(growable: false)));

  JsonArray._(List<JsonValue> values) : values = List.unmodifiable(values);

  final List<JsonValue> values;

  @override
  List<Object?> toDart() => List.unmodifiable(values.map((value) => value.toDart()));
}

/// An immutable JSON object.
final class JsonObject extends JsonValue {
  factory JsonObject(Map<String, Object?> values) =>
      _JsonConverter().convertObject(values.cast<Object?, Object?>());

  JsonObject._(Map<String, JsonValue> values) : values = Map.unmodifiable(values);

  /// Converts [value], requiring an object at the root.
  factory JsonObject.fromDart(Object? value) {
    final converted = JsonValue.fromDart(value);
    if (converted is! JsonObject) {
      throw ArgumentError.value(value, 'value', 'must be a JSON object');
    }
    return converted;
  }

  /// Parses [source], requiring an object at the root.
  factory JsonObject.parse(String source) {
    final converted = JsonValue.parse(source);
    if (converted is! JsonObject) {
      throw const FormatException('JSON root must be an object.');
    }
    return converted;
  }

  final Map<String, JsonValue> values;

  JsonValue? operator [](String key) => values[key];

  @override
  Map<String, Object?> toDart() => Map.unmodifiable(
    values.map((key, value) => MapEntry(key, value.toDart())),
  );
}

final class _JsonConverter {
  final Set<Object> _visiting = HashSet<Object>.identity();

  JsonValue convert(Object? value) => switch (value) {
    null => const JsonNull(),
    bool() => JsonBoolean(value),
    num() => JsonNumber(value),
    String() => JsonString(value),
    List<Object?>() => JsonArray._(convertArray(value)),
    Map<Object?, Object?>() => convertObject(value),
    _ => throw ArgumentError.value(value, 'value', 'is not a JSON value'),
  };

  List<JsonValue> convertArray(List<Object?> values) => _within(values, () {
    return values.map(convert).toList(growable: false);
  });

  JsonObject convertObject(Map<Object?, Object?> values) => _within(values, () {
    final converted = <String, JsonValue>{};
    for (final entry in values.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, 'key', 'JSON object keys must be strings');
      }
      converted[key] = convert(entry.value);
    }
    return JsonObject._(converted);
  });

  T _within<T>(Object collection, T Function() body) {
    if (!_visiting.add(collection)) {
      throw ArgumentError.value(collection, 'value', 'contains a cycle');
    }
    try {
      return body();
    } finally {
      _visiting.remove(collection);
    }
  }
}

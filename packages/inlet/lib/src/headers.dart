/// An immutable, case-insensitive collection of HTTP header values.
final class Headers {
  /// Creates empty headers.
  const Headers.empty() : _values = const {};

  Headers._(this._values);

  /// Copies and validates [values].
  factory Headers.from(Map<String, Iterable<String>> values) {
    final normalized = <String, List<String>>{};
    for (final MapEntry(key: name, value: headerValues) in values.entries) {
      final normalizedName = _validateName(name);
      final copiedValues = <String>[];
      for (final value in headerValues) {
        _validateValue(value);
        copiedValues.add(value);
      }
      final existingValues = normalized[normalizedName] ?? const [];
      normalized[normalizedName] = List.unmodifiable([...existingValues, ...copiedValues]);
    }
    return Headers._(Map.unmodifiable(normalized));
  }

  final Map<String, List<String>> _values;

  /// Returns the first value for [name], or null when absent.
  String? operator [](String name) {
    final values = _values[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }

  /// Returns every value for [name] in insertion order.
  List<String> all(String name) => _values[name.toLowerCase()] ?? const [];

  /// Whether [name] is present, even when it has no values.
  bool contains(String name) => _values.containsKey(name.toLowerCase());

  /// Returns headers with [name] replaced by one [value].
  Headers set(String name, String value) {
    final normalizedName = _validateName(name);
    _validateValue(value);
    return _replace(normalizedName, [value]);
  }

  /// Returns headers with [value] appended to [name].
  Headers append(String name, String value) {
    final normalizedName = _validateName(name);
    _validateValue(value);
    return _replace(normalizedName, [...all(normalizedName), value]);
  }

  /// Returns headers without [name].
  Headers remove(String name) {
    final normalizedName = _validateName(name);
    if (!_values.containsKey(normalizedName)) {
      return this;
    }
    final copied = Map<String, List<String>>.of(_values)..remove(normalizedName);
    return Headers._(Map.unmodifiable(copied));
  }

  /// Returns an immutable snapshot of all header names and values.
  Map<String, List<String>> toMap() => _values;

  Headers _replace(String name, List<String> values) {
    final copied = Map<String, List<String>>.of(_values)..[name] = List.unmodifiable(values);
    return Headers._(Map.unmodifiable(copied));
  }
}

String _validateName(String name) {
  if (name.isEmpty || name.codeUnits.any((unit) => !_isTokenCodeUnit(unit))) {
    throw ArgumentError.value(name, 'name', 'must be a nonempty HTTP token');
  }
  return name.toLowerCase();
}

void _validateValue(String value) {
  for (final unit in value.codeUnits) {
    if (unit != 0x09 && (unit < 0x20 || unit > 0x7e)) {
      throw ArgumentError.value(value, 'value', 'must contain printable ASCII or horizontal tab');
    }
  }
}

bool _isTokenCodeUnit(int unit) {
  const separators = <int>{
    0x28,
    0x29,
    0x3c,
    0x3e,
    0x40,
    0x2c,
    0x3b,
    0x3a,
    0x5c,
    0x22,
    0x2f,
    0x5b,
    0x5d,
    0x3f,
    0x3d,
    0x7b,
    0x7d,
  };
  return unit > 0x20 && unit < 0x7f && !separators.contains(unit);
}

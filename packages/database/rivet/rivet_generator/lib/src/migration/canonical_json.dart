import 'dart:convert';

/// Encodes a JSON value with recursively sorted object keys.
///
/// This is the RFC 8785 boundary used by migration checksums. Numbers are
/// restricted to JSON's interoperable integer range by artifact validation.
String canonicalJson(Object? value) => _encode(value);

String _encode(Object? value) => switch (value) {
  null || bool() || String() => jsonEncode(value),
  int() => value.toString(),
  double()
      when value.isFinite && value.abs() <= 9007199254740991 && value == value.truncateToDouble() =>
    value.toInt().toString(),
  double() when value.isFinite => jsonEncode(value),
  List<Object?>() => '[${value.map(_encode).join(',')}]',
  Map<String, Object?>() => _encodeObject(value),
  _ => throw FormatException('Value ${value.runtimeType} is not canonical JSON.'),
};

String _encodeObject(Map<String, Object?> value) {
  final keys = value.keys.toList()..sort();
  return '{${keys.map((key) => '${jsonEncode(key)}:${_encode(value[key])}').join(',')}}';
}

// Runtime checksum implementation.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

String canonicalRivetJson(Object? value) => _encode(value);

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

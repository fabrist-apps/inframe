import 'dart:convert';
import 'dart:typed_data';

/// Encodes JSON with recursively sorted keys and compact UTF-8 framing.
Uint8List encodeCanonicalJson(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(_sortObject(value))));

Object? _sortObject(Object? value) => switch (value) {
  Map<Object?, Object?>() => <String, Object?>{
    for (final key in value.keys.cast<String>().toList()..sort()) key: _sortObject(value[key]),
  },
  List<Object?>() => value.map(_sortObject).toList(growable: false),
  _ => value,
};

/// Formats a UTC record timestamp with exactly six fractional digits.
String formatRecordTimestamp(DateTime value) {
  final utc = value.toUtc();
  final base = utc.toIso8601String();
  final separator = base.indexOf('.');
  final seconds = separator == -1
      ? base.substring(0, base.length - 1)
      : base.substring(0, separator);
  final micros = utc.millisecond * 1000 + utc.microsecond;
  return '$seconds.${micros.toString().padLeft(6, '0')}Z';
}

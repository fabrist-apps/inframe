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

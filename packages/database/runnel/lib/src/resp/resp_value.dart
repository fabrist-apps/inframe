import 'dart:convert';
import 'dart:typed_data';

/// A value decoded from RESP3.
sealed class RespValue {
  const RespValue();
}

/// A RESP simple string.
final class RespSimpleString extends RespValue {
  /// Creates a simple string.
  const RespSimpleString(this.value);

  /// Decoded UTF-8 text.
  final String value;
}

/// A binary-safe RESP blob string.
final class RespBlobString extends RespValue {
  /// Creates an owned blob string.
  RespBlobString(List<int> value) : value = Uint8List.fromList(value);

  /// Owned payload bytes.
  final Uint8List value;
}

/// A RESP3 verbatim string with its three-byte format marker.
final class RespVerbatimString extends RespValue {
  /// Creates an owned verbatim string.
  RespVerbatimString({required this.format, required List<int> value})
    : value = Uint8List.fromList(value);

  /// Three-byte format, such as `txt`.
  final String format;

  /// Owned payload after the format marker.
  final Uint8List value;
}

/// A RESP integer that fits in a Dart [int].
final class RespInteger extends RespValue {
  /// Creates an integer value.
  const RespInteger(this.value);

  /// Decoded integer.
  final int value;
}

/// A RESP3 floating-point value.
final class RespDouble extends RespValue {
  /// Creates a double value.
  const RespDouble(this.value);

  /// Decoded double, including infinities and NaN.
  final double value;
}

/// A RESP3 arbitrary-precision integer.
final class RespBigNumber extends RespValue {
  /// Creates a big-number value.
  const RespBigNumber(this.value);

  /// Decoded arbitrary-precision integer.
  final BigInt value;
}

/// A RESP3 boolean.
final class RespBoolean extends RespValue {
  /// Creates a boolean value.
  const RespBoolean({required this.value});

  /// Decoded boolean.
  final bool value;
}

/// A RESP null value.
final class RespNull extends RespValue {
  /// Creates the stateless null value.
  const RespNull();
}

/// A simple or blob Redis error preserved as a value.
final class RespError extends RespValue {
  /// Creates an error with its Redis code and message separated.
  const RespError({required this.code, required this.message, this.blob = false});

  /// Splits a Redis wire error at its first space.
  factory RespError.parse(String value, {bool blob = false}) {
    final separator = value.indexOf(' ');
    if (separator < 0) return RespError(code: value, message: '', blob: blob);
    return RespError(
      code: value.substring(0, separator),
      message: value.substring(separator + 1),
      blob: blob,
    );
  }

  /// Redis error prefix, such as `ERR`.
  final String code;

  /// Detail following [code].
  final String message;

  /// Whether the error used RESP3 blob-error framing.
  final bool blob;
}

/// An ordered RESP array.
final class RespArray extends RespValue {
  /// Creates an immutable array snapshot.
  RespArray(Iterable<RespValue> values) : values = List.unmodifiable(values);

  /// Ordered array elements, including nested errors.
  final List<RespValue> values;
}

/// An ordered RESP3 set representation.
final class RespSet extends RespValue {
  /// Creates an immutable set-element snapshot.
  RespSet(Iterable<RespValue> values) : values = List.unmodifiable(values);

  /// Wire-ordered set elements.
  final List<RespValue> values;
}

/// One ordered RESP3 map entry.
final class RespMapEntry {
  /// Creates a map entry without collapsing duplicate keys.
  const RespMapEntry(this.key, this.value);

  /// Entry key.
  final RespValue key;

  /// Entry value.
  final RespValue value;
}

/// A RESP3 map that preserves wire order and duplicate keys.
final class RespMap extends RespValue {
  /// Creates an immutable map-entry snapshot.
  RespMap(Iterable<RespMapEntry> entries) : entries = List.unmodifiable(entries);

  /// Wire-ordered entries.
  final List<RespMapEntry> entries;
}

/// A RESP3 push frame, kept separate from command replies.
final class RespPush extends RespValue {
  /// Creates an immutable push payload.
  RespPush(Iterable<RespValue> values) : values = List.unmodifiable(values);

  /// Ordered push elements.
  final List<RespValue> values;
}

/// A value and the RESP3 attributes attached immediately before it.
final class RespAttributed extends RespValue {
  /// Creates an attributed value without collapsing attribute keys.
  RespAttributed({required Iterable<RespMapEntry> attributes, required this.value})
    : attributes = List.unmodifiable(attributes);

  /// Wire-ordered attributes.
  final List<RespMapEntry> attributes;

  /// Value to which [attributes] apply.
  final RespValue value;
}

/// Decodes a simple or blob string as strict UTF-8.
String respText(RespValue value) => switch (value) {
  RespSimpleString(:final value) => value,
  RespBlobString(:final value) => utf8.decode(value),
  _ => throw FormatException('Expected a text reply, received ${value.runtimeType}.'),
};

part of '../json_patch.dart';

/// An immutable RFC 6901 JSON Pointer.
@immutable
final class JsonPointer {
  /// Parses a JSON Pointer string.
  ///
  /// URI fragment pointers are not accepted. Malformed escapes throw
  /// [FormatException].
  factory parse(String pointer) {
    if (pointer.isEmpty) return root;
    if (!pointer.startsWith('/')) {
      throw const FormatException('A JSON Pointer must be empty or start with "/".');
    }

    return JsonPointer._(
      List<String>.unmodifiable(pointer.substring(1).split('/').map(_decodePointerSegment)),
    );
  }

  /// Creates a pointer from decoded path [segments].
  factory fromSegments(Iterable<String> segments) =>
      JsonPointer._(List<String>.unmodifiable(segments));
  const new _(this.segments);

  /// The document root.
  static const root = JsonPointer._(<String>[]);

  /// The decoded path segments.
  final List<String> segments;

  /// Returns a pointer to [segment] below this pointer.
  JsonPointer child(String segment) => JsonPointer.fromSegments(<String>[...segments, segment]);

  @override
  String toString() => segments.map((segment) => '/${_encodePointerSegment(segment)}').join();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JsonPointer &&
          segments.length == other.segments.length &&
          _equalSegments(segments, other.segments);

  @override
  int get hashCode => Object.hashAll(segments);
}

bool _equalSegments(List<String> left, List<String> right) {
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _decodePointerSegment(String encoded) {
  final decoded = StringBuffer();
  for (var index = 0; index < encoded.length; index++) {
    final character = encoded[index];
    if (character != '~') {
      decoded.write(character);
      continue;
    }
    if (index + 1 >= encoded.length) {
      throw const FormatException('A JSON Pointer contains an incomplete escape.');
    }
    final escape = encoded[++index];
    switch (escape) {
      case '0':
        decoded.write('~');
      case '1':
        decoded.write('/');
      default:
        throw FormatException('A JSON Pointer contains the invalid escape ~$escape.');
    }
  }
  return decoded.toString();
}

String _encodePointerSegment(String segment) => segment.replaceAll('~', '~0').replaceAll('/', '~1');

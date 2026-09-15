import 'package:dart_mappable/dart_mappable.dart';

/// One structural step from the parse root.
sealed class PathSegment {
  const PathSegment();
}

/// An object field or map key, including the empty string.
final class FieldSegment extends PathSegment {
  /// Identifies [name] without using a schema's human-readable label.
  const FieldSegment(this.name);

  /// The original key.
  final String name;

  @override
  bool operator ==(Object other) => other is FieldSegment && other.name == name;

  @override
  int get hashCode => Object.hash(FieldSegment, name);

  @override
  String toString() => name;
}

/// A non-negative list position.
final class IndexSegment extends PathSegment {
  /// Throws [ArgumentError] for a negative index.
  IndexSegment(this.index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'Must be non-negative');
    }
  }

  /// The zero-based position.
  final int index;

  @override
  bool operator ==(Object other) => other is IndexSegment && other.index == index;

  @override
  int get hashCode => Object.hash(IndexSegment, index);

  @override
  String toString() => '[$index]';
}

/// Serializes structural paths as compact strings and non-negative integers.
final class PathSegmentMapper extends SimpleMapper<PathSegment> {
  /// Creates a structural path mapper.
  const PathSegmentMapper();

  @override
  PathSegment decode(Object value) => switch (value) {
    final String field => FieldSegment(field),
    final int index when index >= 0 => IndexSegment(index),
    _ => throw const FormatException('Path segments must be strings or non-negative integers'),
  };

  @override
  Object encode(PathSegment self) => switch (self) {
    FieldSegment(:final name) => name,
    IndexSegment(:final index) => index,
  };
}

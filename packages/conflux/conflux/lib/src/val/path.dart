// All structural path fields are immutable.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

/// One structural step from the parse root.
sealed class PathSegment {
  const PathSegment();
}

/// An object field or map key, including the empty string.
final class Field extends PathSegment {
  /// Identifies [name] without using a schema's human-readable label.
  const Field(this.name);

  /// The original key.
  final String name;

  @override
  bool operator ==(Object other) => other is Field && other.name == name;
  @override
  int get hashCode => Object.hash(Field, name);
  @override
  String toString() => name;
}

/// A non-negative list position.
final class Index extends PathSegment {
  /// Throws [ArgumentError] for a negative index.
  Index(this.index) {
    if (index < 0) throw ArgumentError.value(index, 'index', 'Must be non-negative');
  }

  /// The zero-based position.
  final int index;

  @override
  bool operator ==(Object other) => other is Index && other.index == index;
  @override
  int get hashCode => Object.hash(Index, index);
  @override
  String toString() => '[$index]';
}

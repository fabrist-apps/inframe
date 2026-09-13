import 'dart:collection';

/// An immutable ordered collection that always contains at least one value.
final class NonEmptyList<E> extends IterableBase<E> {
  /// Copies [first] and any [rest] into an immutable non-empty collection.
  factory NonEmptyList(E first, [Iterable<E> rest = const []]) {
    final copiedRest = List<E>.unmodifiable(rest);
    return NonEmptyList._(first, copiedRest, List<E>.unmodifiable([first, ...copiedRest]));
  }

  NonEmptyList._(this.first, this.rest, this.values);

  /// The required first value.
  @override
  final E first;

  /// The immutable values after [first].
  final List<E> rest;

  /// Every value in order as an immutable list.
  final List<E> values;

  @override
  Iterator<E> get iterator => values.iterator;
}

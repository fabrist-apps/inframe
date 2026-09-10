part of '../../effect.dart';

/// The complete outcome of running an [Effect].
sealed class Exit<A, E> {
  const Exit();
}

/// A successful [Exit].
final class Succeeded<A, E> extends Exit<A, E> {
  /// Creates a successful exit containing [value].
  const Succeeded(this.value);

  /// The successful value.
  final A value;
}

/// A failed [Exit] retaining its complete [Cause].
final class Failed<A, E> extends Exit<A, E> {
  /// Creates a failed exit containing [cause].
  const Failed(this.cause);

  /// The complete failure cause.
  final Cause<E> cause;
}

import 'package:conflux/src/effect/cause.dart';

/// The complete outcome of running an Effect.
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

/// Runtime-only cleanup composition for an [Exit].
extension ExitRuntimeOperations<A, E> on Exit<A, E> {
  /// Appends [cleanup] after the operation outcome when cleanup failed.
  Exit<A, E> appendCleanup(Cause<Never>? cleanup) {
    if (cleanup == null) return this;
    return switch (this) {
      Succeeded<A, E>() => Failed(cleanup),
      Failed<A, E>(:final cause) => Failed(Sequential([cause, cleanup])),
    };
  }
}

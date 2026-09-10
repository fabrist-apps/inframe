part of '../../effect.dart';

/// Explains why an [Effect] failed.
sealed class Cause<E> {
  const Cause();
}

/// A recoverable domain failure.
final class Expected<E> extends Cause<E> {
  /// Creates an expected failure containing [error].
  const Expected(this.error);

  /// The domain error.
  final E error;
}

/// An unexpected thrown object and its original stack trace.
final class Defect<E> extends Cause<E> {
  /// Creates a defect.
  const Defect(this.error, this.stackTrace);

  /// The unexpected thrown object.
  final Object error;

  /// The stack trace captured at the failure boundary.
  final StackTrace stackTrace;
}

/// Cooperative interruption of an execution.
final class Interrupted<E> extends Cause<E> {
  /// Creates an interruption with an identifiable [reason].
  const Interrupted(this.reason);

  /// Why interruption was requested.
  final Object? reason;
}

/// Failures that occurred one after another.
final class Sequential<E> extends Cause<E> {
  /// Creates an ordered sequential cause.
  Sequential(Iterable<Cause<E>> causes) : causes = List.unmodifiable(causes);

  /// Failures in execution order.
  final List<Cause<E>> causes;
}

/// Failures from concurrent branches in source order.
final class Parallel<E> extends Cause<E> {
  /// Creates an ordered parallel cause.
  Parallel(Iterable<Cause<E>> causes) : causes = List.unmodifiable(causes);

  /// Branch failures in source order.
  final List<Cause<E>> causes;
}

Cause<Never>? _defectsOnly<E>(Cause<E> cause) => switch (cause) {
  Expected<E>() || Interrupted<E>() => null,
  Defect<E>(:final error, :final stackTrace) => Defect(error, stackTrace),
  Sequential<E>(:final causes) => _combineCleanupCauses(
    causes.map((cause) => _defectsOnly<E>(cause)).whereType<Cause<Never>>(),
    sequential: true,
  ),
  Parallel<E>(:final causes) => _combineCleanupCauses(
    causes.map((cause) => _defectsOnly<E>(cause)).whereType<Cause<Never>>(),
    sequential: false,
  ),
};

Cause<Never>? _combineCleanupCauses(
  Iterable<Cause<Never>> causes, {
  required bool sequential,
}) {
  final values = List<Cause<Never>>.of(causes);
  return switch (values) {
    [] => null,
    [final only] => only,
    _ => sequential ? Sequential(values) : Parallel(values),
  };
}

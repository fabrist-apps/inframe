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
  /// Creates a non-empty ordered sequential cause.
  Sequential(Iterable<Cause<E>> causes) : causes = _nonEmptyCauses(causes, 'causes');

  /// Failures in execution order.
  final List<Cause<E>> causes;
}

/// Failures from concurrent branches in source order.
final class Parallel<E> extends Cause<E> {
  /// Creates a non-empty ordered parallel cause.
  Parallel(Iterable<Cause<E>> causes) : causes = _nonEmptyCauses(causes, 'causes');

  /// Branch failures in source order.
  final List<Cause<E>> causes;
}

List<Cause<E>> _nonEmptyCauses<E>(
  Iterable<Cause<E>> causes,
  String name,
) {
  final values = List<Cause<E>>.unmodifiable(causes);
  if (values.isEmpty) {
    throw ArgumentError.value(causes, name, 'Must not be empty.');
  }
  return values;
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

bool _containsFatal<E>(Cause<E> cause) => switch (cause) {
  Defect<E>() || Interrupted<E>() => true,
  Expected<E>() => false,
  Sequential<E>(:final causes) ||
  Parallel<E>(:final causes) => causes.any((cause) => _containsFatal<E>(cause)),
};

List<E> _expectedErrors<E>(Cause<E> cause) => switch (cause) {
  Expected<E>(:final error) => [error],
  Defect<E>() || Interrupted<E>() => const [],
  Sequential<E>(:final causes) || Parallel<E>(:final causes) => [
    for (final cause in causes) ..._expectedErrors<E>(cause),
  ],
};

Cause<F> _mapCause<E, F>(Cause<E> cause, F Function(E error) transform) => switch (cause) {
  Expected<E>(:final error) => Expected(transform(error)),
  Defect<E>(:final error, :final stackTrace) => Defect(error, stackTrace),
  Interrupted<E>(:final reason) => Interrupted(reason),
  Sequential<E>(:final causes) => Sequential(
    causes.map((cause) => _mapCause<E, F>(cause, transform)),
  ),
  Parallel<E>(:final causes) => Parallel(
    causes.map((cause) => _mapCause<E, F>(cause, transform)),
  ),
};

Option<E> _primaryError<E>(Cause<E> cause) {
  if (_containsFatal(cause)) return const None();
  final errors = _expectedErrors(cause);
  return errors.isEmpty ? const None() : Some(errors.first);
}

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

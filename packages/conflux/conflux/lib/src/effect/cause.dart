import 'package:conflux/option.dart';

/// Explains why an Effect failed.
sealed class Cause<E> {
  const Cause();

  /// Whether this cause contains a defect or interruption.
  bool get containsFatal => switch (this) {
    Defect<E>() || Interrupted<E>() => true,
    Expected<E>() => false,
    Sequential<E>(:final causes) ||
    Parallel<E>(:final causes) => causes.any((cause) => cause.containsFatal),
  };

  /// Whether this cause contains an interruption.
  bool get containsInterruption => switch (this) {
    Interrupted<E>() => true,
    Sequential<E>(:final causes) || Parallel<E>(:final causes) => causes.any(
      (cause) => cause.containsInterruption,
    ),
    Expected<E>() || Defect<E>() => false,
  };

  /// Expected errors in deterministic traversal order.
  List<E> get expectedErrors => switch (this) {
    Expected<E>(:final error) => [error],
    Defect<E>() || Interrupted<E>() => const [],
    Sequential<E>(:final causes) || Parallel<E>(:final causes) => [
      for (final cause in causes) ...cause.expectedErrors,
    ],
  };

  /// The first expected error when every leaf is expected.
  Option<E> get primaryError {
    if (containsFatal) return const None();
    // Every group is non-empty, so following its first child reaches a leaf.
    var first = this;
    while (true) {
      switch (first) {
        case Expected<E>(:final error):
          return Some(error);
        case Sequential<E>(:final causes) || Parallel<E>(:final causes):
          first = causes.first;
        case Defect<E>() || Interrupted<E>():
          return const None();
      }
    }
  }

  /// Transforms every expected error while preserving cause structure.
  Cause<F> mapExpected<F>(F Function(E error) transform) => switch (this) {
    Expected<E>(:final error) => Expected(transform(error)),
    Defect<E>(:final error, :final stackTrace) => Defect(error, stackTrace),
    Interrupted<E>(:final reason) => Interrupted(reason),
    Sequential<E>(:final causes) => Sequential(
      causes.map((cause) => cause.mapExpected(transform)),
    ),
    Parallel<E>(:final causes) => Parallel(
      causes.map((cause) => cause.mapExpected(transform)),
    ),
  };

  static List<Cause<T>> _nonEmpty<T>(Iterable<Cause<T>> causes) {
    final values = List<Cause<T>>.unmodifiable(causes);
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'causes', 'Must not be empty');
    }
    return values;
  }
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
  Sequential(Iterable<Cause<E>> causes) : causes = Cause._nonEmpty(causes);

  /// Failures in execution order.
  final List<Cause<E>> causes;
}

/// Failures from concurrent branches in source order.
final class Parallel<E> extends Cause<E> {
  /// Creates a non-empty ordered parallel cause.
  Parallel(Iterable<Cause<E>> causes) : causes = Cause._nonEmpty(causes);

  /// Branch failures in source order.
  final List<Cause<E>> causes;
}

/// Runtime-only cause reductions used while joining interrupted work.
extension CauseRuntimeOperations<E> on Cause<E> {
  /// Retains defects while discarding expected errors and interruptions.
  Cause<Never>? get defectsOnly => switch (this) {
    Expected<E>() || Interrupted<E>() => null,
    Defect<E>(:final error, :final stackTrace) => Defect(error, stackTrace),
    Sequential<E>(:final causes) => CauseGroup.sequential(
      causes.map((cause) => cause.defectsOnly).whereType<Cause<Never>>(),
    ),
    Parallel<E>(:final causes) => CauseGroup.parallel(
      causes.map((cause) => cause.defectsOnly).whereType<Cause<Never>>(),
    ),
  };
}

/// Builds optional cause groups without empty or singleton wrappers.
abstract final class CauseGroup {
  /// Combines [causes] in execution order, omitting unnecessary wrappers.
  static Cause<E>? sequential<E>(Iterable<Cause<E>> causes) => _combine(causes, Sequential.new);

  /// Combines concurrent [causes] in source order, omitting unnecessary wrappers.
  static Cause<E>? parallel<E>(Iterable<Cause<E>> causes) => _combine(causes, Parallel.new);

  static Cause<E>? _combine<E>(
    Iterable<Cause<E>> causes,
    Cause<E> Function(Iterable<Cause<E>>) group,
  ) {
    final values = List<Cause<E>>.of(causes);
    return switch (values) {
      [] => null,
      [final only] => only,
      _ => group(values),
    };
  }
}

import 'package:conflux/option.dart';

/// The outcome of a synchronous operation with an expected error type.
sealed class Result<A, E> {
  const Result();

  /// Converts an [Option] to a result, computing an error only for [None].
  static Result<A, E> fromOption<A, E>(Option<A> option, E Function() onNone) => switch (option) {
    Some<A>(:final value) => Success(value),
    None() => Failure(onNone()),
  };

  /// Moves a result outside an optional value without losing absence.
  static Result<Option<A>, E> transposeOption<A, E>(Option<Result<A, E>> option) =>
      switch (option) {
        None() => const Success(None()),
        Some<Result<A, E>>(value: Success<A, E>(:final value)) => Success(Some(value)),
        Some<Result<A, E>>(value: Failure<A, E>(:final error)) => Failure(error),
      };
}

/// A successful [Result] containing [value].
final class Success<A, E> extends Result<A, E> {
  /// Creates a successful result.
  const Success(this.value);

  /// The success value.
  final A value;
}

/// A failed [Result] containing an expected [error].
final class Failure<A, E> extends Result<A, E> {
  /// Creates a failed result.
  const Failure(this.error);

  /// The expected failure.
  final E error;
}

/// Inspection and extraction operations for [Result].
extension ResultInspection<A, E> on Result<A, E> {
  /// Whether this result succeeded.
  bool get isSuccess => switch (this) {
    Success<A, E>() => true,
    Failure<A, E>() => false,
  };

  /// Whether this result failed.
  bool get isFailure => !isSuccess;

  /// Handles the success and failure cases explicitly.
  R match<R>({required R Function(A value) onSuccess, required R Function(E error) onFailure}) =>
      switch (this) {
        Success<A, E>(:final value) => onSuccess(value),
        Failure<A, E>(:final error) => onFailure(error),
      };

  /// Returns the success as an [Option].
  Option<A> getSuccess() => switch (this) {
    Success<A, E>(:final value) => Some(value),
    Failure<A, E>() => const None(),
  };

  /// Returns the failure as an [Option].
  Option<E> getFailure() => switch (this) {
    Success<A, E>() => const None(),
    Failure<A, E>(:final error) => Some(error),
  };

  /// Returns the success or `null` for a failure.
  A? getOrNull() => switch (this) {
    Success<A, E>(:final value) => value,
    Failure<A, E>() => null,
  };

  /// Returns the success or throws the object produced from the failure.
  A getOrThrowWith(Object Function(E error) toException) => switch (this) {
    Success<A, E>(:final value) => value,
    Failure<A, E>(:final error) => _throwMapped(error, toException),
  };
}

A _throwMapped<A, E>(E error, Object Function(E error) toException) {
  // The public contract deliberately lets callers map failures to any object
  // accepted by Dart's throw expression, not only Exception or Error values.
  // ignore: only_throw_errors
  throw toException(error);
}

/// Transformations for [Result].
extension ResultTransformation<A, E> on Result<A, E> {
  /// Transforms a success and preserves a failure.
  Result<B, E> map<B>(B Function(A value) transform) => switch (this) {
    Success<A, E>(:final value) => Success(transform(value)),
    Failure<A, E>(:final error) => Failure(error),
  };

  /// Transforms a failure and preserves a success.
  Result<A, F> mapError<F>(F Function(E error) transform) => switch (this) {
    Success<A, E>(:final value) => Success(value),
    Failure<A, E>(:final error) => Failure(transform(error)),
  };

  /// Transforms either branch into a new result.
  Result<B, F> mapBoth<B, F>({
    required B Function(A value) onSuccess,
    required F Function(E error) onFailure,
  }) => switch (this) {
    Success<A, E>(:final value) => Success(onSuccess(value)),
    Failure<A, E>(:final error) => Failure(onFailure(error)),
  };

  /// Sequences a success transformation that returns another [Result].
  Result<B, E> flatMap<B>(Result<B, E> Function(A value) transform) => switch (this) {
    Success<A, E>(:final value) => transform(value),
    Failure<A, E>(:final error) => Failure(error),
  };

  /// Exchanges the success and failure variants and their types.
  Result<E, A> flip() => switch (this) {
    Success<A, E>(:final value) => Failure(value),
    Failure<A, E>(:final error) => Success(error),
  };
}

/// Recovery operations for [Result].
extension ResultRecovery<A, E> on Result<A, E> {
  /// Returns the success or lazily computes a fallback from the failure.
  A getOrElse(A Function(E error) fallback) => switch (this) {
    Success<A, E>(:final value) => value,
    Failure<A, E>(:final error) => fallback(error),
  };

  /// Returns this success or lazily replaces its failure.
  Result<A, F> orElse<F>(Result<A, F> Function(E error) fallback) => switch (this) {
    Success<A, E>(:final value) => Success(value),
    Failure<A, E>(:final error) => fallback(error),
  };
}

/// Selection and observation operations for [Result].
extension ResultSelection<A, E> on Result<A, E> {
  /// Keeps a success when accepted, or creates a failure when rejected.
  Result<A, E> filterOrFail(
    bool Function(A value) predicate,
    E Function(A value) onFailure,
  ) => switch (this) {
    Success<A, E>(:final value) when predicate(value) => this,
    Success<A, E>(:final value) => Failure(onFailure(value)),
    Failure<A, E>() => this,
  };

  /// Observes a success and returns this result.
  Result<A, E> tap(void Function(A value) observe) {
    if (this case Success<A, E>(:final value)) observe(value);
    return this;
  }

  /// Observes a failure and returns this result.
  Result<A, E> tapError(void Function(E error) observe) {
    if (this case Failure<A, E>(:final error)) observe(error);
    return this;
  }
}

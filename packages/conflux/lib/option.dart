/// An optional value that distinguishes absence from a present nullable value.
sealed class Option<T> {
  const Option();
}

/// A present [value], including `null` when [T] is nullable.
final class Some<T> extends Option<T> {
  /// Creates a present option containing exactly [value].
  const Some(this.value);

  /// The present value.
  final T value;
}

/// The absence of a value.
final class None extends Option<Never> {
  /// Creates an absent option.
  const None();
}

/// Inspection and extraction operations for [Option].
extension OptionInspection<T> on Option<T> {
  /// Whether this option contains a value.
  bool get isSome => switch (this) {
    Some<T>() => true,
    None() => false,
  };

  /// Whether this option is absent.
  bool get isNone => !isSome;

  /// Handles the present and absent cases explicitly.
  R match<R>({required R Function(T value) onSome, required R Function() onNone}) => switch (this) {
    Some<T>(:final value) => onSome(value),
    None() => onNone(),
  };

  /// Returns the present value or `null` when absent.
  T? getOrNull() => switch (this) {
    Some<T>(:final value) => value,
    None() => null,
  };

  /// Returns an immutable list containing zero or one value.
  List<T> toList() => switch (this) {
    Some<T>(:final value) => List<T>.unmodifiable([value]),
    None() => List<T>.unmodifiable(const []),
  };
}

/// Transformations for [Option].
extension OptionTransformation<T> on Option<T> {
  /// Transforms a present value and preserves absence.
  Option<R> map<R>(R Function(T value) transform) => switch (this) {
    Some<T>(:final value) => Some(transform(value)),
    None() => const None(),
  };

  /// Sequences a transformation that returns another [Option].
  Option<R> flatMap<R>(Option<R> Function(T value) transform) => switch (this) {
    Some<T>(:final value) => transform(value),
    None() => const None(),
  };

  /// Combines two present values and preserves absence from either side.
  Option<R> zipWith<U, R>(Option<U> other, R Function(T left, U right) combine) =>
      switch ((this, other)) {
        (Some<T>(value: final left), Some<U>(value: final right)) => Some(combine(left, right)),
        _ => const None(),
      };
}

/// Recovery operations for [Option].
extension OptionRecovery<T> on Option<T> {
  /// Returns the present value or lazily computes a fallback.
  T getOrElse(T Function() fallback) => switch (this) {
    Some<T>(:final value) => value,
    None() => fallback(),
  };

  /// Returns this option or lazily computes a replacement.
  Option<T> orElse(Option<T> Function() fallback) => switch (this) {
    Some<T>() => this,
    None() => fallback(),
  };
}

/// Selection operations for [Option].
extension OptionSelection<T> on Option<T> {
  /// Keeps a present value only when [predicate] accepts it.
  Option<T> filter(bool Function(T value) predicate) => switch (this) {
    Some<T>(:final value) when predicate(value) => this,
    _ => const None(),
  };

  /// Whether a present value satisfies [predicate].
  bool exists(bool Function(T value) predicate) => switch (this) {
    Some<T>(:final value) => predicate(value),
    None() => false,
  };

  /// Whether this option contains a value equal to [candidate].
  bool contains(Object? candidate) => switch (this) {
    Some<T>(:final value) => value == candidate,
    None() => false,
  };
}

/// Flattening for an [Option] containing another [Option].
extension FlattenOption<T> on Option<Option<T>> {
  /// Removes one level of optionality.
  Option<T> flatten() => switch (this) {
    Some<Option<T>>(:final value) => value,
    None() => const None(),
  };
}

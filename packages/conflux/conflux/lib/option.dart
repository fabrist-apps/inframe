import 'package:dart_mappable/dart_mappable.dart';

/// An optional value that distinguishes absence from a present nullable value.
sealed class Option<T> {
  const Option();

  /// Collects every present option or returns [None] at the first absence.
  static Option<List<T>> all<T>(Iterable<Option<T>> options) {
    final values = <T>[];
    for (final option in options) {
      switch (option) {
        case Some<T>(:final value):
          values.add(value);
        case None():
          return const None();
      }
    }
    return Some(List<T>.unmodifiable(values));
  }

  /// Returns the first present option, without inspecting later values.
  static Option<T> firstSome<T>(Iterable<Option<T>> options) {
    for (final option in options) {
      if (option case Some<T>()) return option;
    }
    return const None();
  }

  /// Returns the first iterable element or [None] when it is empty.
  static Option<T> fromIterable<T>(Iterable<T> values) {
    final iterator = values.iterator;
    return iterator.moveNext() ? Some(iterator.current) : const None();
  }
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

/// Serializes present values using the registered mapper for their contents.
///
/// None encodes to an internal marker removed by [OptionFieldsHook].
/// Unremoved markers remain in toValue/toMap output and are not JSON encodable.
/// dart_mappable handles raw null before invoking custom mappers; the class hook
/// preserves explicit null for decoding into Some(null).
final class OptionMapper extends SimpleMapper1<Option<dynamic>> {
  /// Creates a mapper for Conflux [Option] values.
  const OptionMapper();

  @override
  Function get typeFactory {
    // dart_mappable supplies a generic callback with a caller-specific return type.
    // ignore: avoid_dynamic_calls
    return <T>(Function f) => f<Option<T>>();
  }

  @override
  Option<T> decode<T>(Object value) =>
      Some(container.fromValue<T>(value is _PresentNull ? null : value));

  @override
  Object? encode<T>(Option<T> self) => switch (self) {
    Some<T>(value: None()) => throw const FormatException('Some(None()) cannot be serialized.'),
    Some<T>(:final value) => container.toValue<T>(value),
    None() => const _Absent(),
  };
}

/// Omits absent fields and preserves missing versus null during decoding.
///
/// Paths use serialized keys separated by dots, for example `profile.nickname`.
/// Traversal follows maps only; absent or non-map parents are left unchanged.
/// Literal dots in keys and array indexing are not supported.
/// Input maps are copied along each modified path.
final class OptionFieldsHook extends MappingHook {
  /// Creates a hook for the serialized Option field [keys].
  const OptionFieldsHook(this.keys);

  /// Serialized field paths whose absence represents [None].
  final List<String> keys;

  @override
  Object? beforeDecode(Object? value) => _transform(value, decoding: true);

  @override
  Object? afterEncode(Object? value) => _transform(value, decoding: false);

  Object? _transform(Object? value, {required bool decoding}) {
    if (value is! Map<String, dynamic>) {
      return value;
    }

    var result = value;
    for (final key in keys) {
      result = _transformPath(result, key.split('.'), decoding: decoding);
    }

    return result;
  }

  Map<String, dynamic> _transformPath(
    Map<String, dynamic> value,
    List<String> path, {
    required bool decoding,
  }) {
    final key = path.first;
    final result = Map<String, dynamic>.of(value);
    if (path.length > 1) {
      final child = value[key];
      if (child is Map<String, dynamic>) {
        result[key] = _transformPath(child, path.sublist(1), decoding: decoding);
      }
    } else if (decoding) {
      if (!value.containsKey(key)) {
        result[key] = const None();
      } else if (value[key] == null) {
        result[key] = const _PresentNull();
      }
    } else if (value[key] is _Absent) {
      result.remove(key);
    }

    return result;
  }
}

final class _Absent {
  const _Absent();
}

final class _PresentNull {
  const _PresentNull();
}

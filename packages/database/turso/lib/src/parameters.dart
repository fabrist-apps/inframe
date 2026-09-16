import 'dart:typed_data';

/// The largest integral value represented exactly on every Dart platform.
const int portableSafeInteger = 9007199254740991;
final BigInt _minimumInt64 = BigInt.parse('-9223372036854775808');
final BigInt _maximumInt64 = BigInt.parse('9223372036854775807');

/// Operation-time copies of normalized SQL values, retaining the binding mode.
sealed class SqlParameters {
  const SqlParameters();

  /// Copies mutable values before the operation enters either queue.
  factory SqlParameters.snapshot(
    List<Object?> positional,
    Map<String, Object?> named,
  ) {
    if (positional.isNotEmpty && named.isNotEmpty) {
      throw ArgumentError('Positional and named parameters cannot both be nonempty.');
    }
    if (named.isNotEmpty) {
      return NamedParameters(
        Map.unmodifiable({
          for (final entry in named.entries) entry.key: _normalize(entry.value),
        }),
      );
    }
    return PositionalParameters(List.unmodifiable(positional.map(_normalize)));
  }
}

/// Parameters bound in SQL placeholder order.
final class PositionalParameters extends SqlParameters {
  /// Wraps an already normalized positional snapshot.
  const PositionalParameters(this.values);

  /// Values in placeholder order.
  final List<Object?> values;
}

/// Parameters indexed by their full SQL placeholder spelling.
final class NamedParameters extends SqlParameters {
  /// Wraps an already normalized named snapshot.
  const NamedParameters(this.values);

  /// Values keyed by full placeholder spelling.
  final Map<String, Object?> values;
}

/// An empty positional parameter snapshot.
const emptySqlParameters = PositionalParameters([]);

/// Rejects SQL text that cannot cross the native C string boundary intact.
void validateSql(String sql) {
  if (sql.contains('\u0000')) {
    throw ArgumentError.value(sql, 'sql', 'Must not contain NUL characters.');
  }
}

Object? _normalize(Object? value) {
  if (value == null || value is String) return value;
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is BigInt) {
    if (value < _minimumInt64 || value > _maximumInt64) {
      throw ArgumentError.value(value, 'parameter', 'Outside the signed 64-bit range.');
    }
    return value;
  }
  if (value is int) {
    if (value < -portableSafeInteger || value > portableSafeInteger) {
      throw ArgumentError.value(
        value,
        'parameter',
        'Integral values outside the portable safe range must use BigInt.',
      );
    }
    return BigInt.from(value);
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'parameter', 'Must be finite.');
    }
    if (value == value.truncateToDouble()) {
      if (value < -portableSafeInteger || value > portableSafeInteger) {
        throw ArgumentError.value(
          value,
          'parameter',
          'Integral values outside the portable safe range must use BigInt.',
        );
      }
      return BigInt.from(value);
    }
    return value;
  }
  throw ArgumentError.value(value, 'parameter', 'Unsupported SQL parameter type.');
}

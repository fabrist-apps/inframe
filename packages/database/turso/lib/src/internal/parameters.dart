import 'dart:typed_data';

/// The largest integral value represented exactly on every Dart platform.
const int portableSafeInteger = 9007199254740991;
final BigInt _minimumInt64 = BigInt.parse('-9223372036854775808');
final BigInt _maximumInt64 = BigInt.parse('9223372036854775807');

/// Rejects SQL text that cannot cross the native C string boundary intact.
void validateSql(String sql) {
  if (sql.contains('\u0000')) {
    throw ArgumentError.value(sql, 'sql', 'Must not contain NUL characters.');
  }
}

/// Copies and normalizes arguments before an operation enters the queue.
List<Object?> snapshotParameters(
  List<Object?> parameters,
  Map<String, Object?> namedParameters,
) {
  if (parameters.isNotEmpty && namedParameters.isNotEmpty) {
    throw ArgumentError('Positional and named parameters cannot both be nonempty.');
  }

  if (namedParameters.isNotEmpty) {
    return [
      for (final entry in namedParameters.entries) [entry.key, _normalize(entry.value)],
    ];
  }
  return [for (final value in parameters) _normalize(value)];
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

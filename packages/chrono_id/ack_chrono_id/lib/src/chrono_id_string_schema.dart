import 'package:ack/ack.dart';
import 'package:chrono_id/chrono_id.dart';

/// Adds Chrono ID validation to Ack string schemas.
extension ChronoIDStringSchema on StringSchema {
  /// Returns a new schema that validates Chrono IDs.
  ///
  /// [size] is the ID body length and excludes [prefix] and its `_` separator.
  /// Invalid configuration throws an [ArgumentError] while this schema is
  /// constructed. [message] replaces the default refinement error.
  StringSchema chronoId({
    String? prefix,
    int size = 24,
    String? message,
  }) {
    ChronoID.isValid('', prefix: prefix, size: size);

    return refine(
      (value) => ChronoID.isValid(value, prefix: prefix, size: size),
      message: message ?? 'The value must be a valid Chrono ID.',
    );
  }
}

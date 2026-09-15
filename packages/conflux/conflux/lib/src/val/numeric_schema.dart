import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal finite numeric factory, preserving Dart's runtime type semantics.
Schema<T> numericSchema<T extends num>({
  required String type,
  String? name,
  String? code,
  String? message,
}) {
  final base = typeSchema<T>(type: type, name: name, code: code, message: message);

  return Schema.internal((input, context, path) {
    final parsed = base.evaluate(input, context, path);

    if (parsed case Success(:final value) when !value.isFinite) {
      return invalid(
        IssueTemplate(
          code ?? 'NOT_FINITE',
          (name) => message ?? '${name == null ? 'Must' : '$name must'} be a finite number',
        ).at(path, base.name),
      );
    }

    return parsed;
  }, name: base.name);
}

/// Numeric constraints retain the receiver's exact numeric output type.
extension NumericChecks<T extends num> on Schema<T> {
  /// Requires a value at least [bound].
  Schema<T> min(T bound, {String? code, String? message}) => withCheck(
    (value) => value >= bound,
    IssueTemplate(
      code ?? 'MIN',
      (name) => message ?? '${name == null ? 'Must' : '$name must'} be at least $bound',
    ),
  );

  /// Requires a value at most [bound].
  Schema<T> max(T bound, {String? code, String? message}) => withCheck(
    (value) => value <= bound,
    IssueTemplate(
      code ?? 'MAX',
      (name) => message ?? '${name == null ? 'Must' : '$name must'} be at most $bound',
    ),
  );

  /// Requires a value greater than [bound].
  Schema<T> greaterThan(T bound, {String? code, String? message}) => withCheck(
    (value) => value > bound,
    IssueTemplate(
      code ?? 'GREATER_THAN',
      (name) => message ?? '${name == null ? 'Must' : '$name must'} be greater than $bound',
    ),
  );

  /// Requires a value less than [bound].
  Schema<T> lessThan(T bound, {String? code, String? message}) => withCheck(
    (value) => value < bound,
    IssueTemplate(
      code ?? 'LESS_THAN',
      (name) => message ?? '${name == null ? 'Must' : '$name must'} be less than $bound',
    ),
  );

  /// Requires a strictly positive value; zero is rejected.
  Schema<T> positive({String? code, String? message}) => withCheck(
    (value) => value > 0,
    IssueTemplate(
      code ?? 'GREATER_THAN',
      (name) =>
          message ??
          '${name == null ? 'Must' : '$name must'} be greater than ${T == double ? 0.0 : 0}',
    ),
  );

  /// Requires a strictly negative value; zero is rejected.
  Schema<T> negative({String? code, String? message}) => withCheck(
    (value) => value < 0,
    IssueTemplate(
      code ?? 'LESS_THAN',
      (name) =>
          message ??
          '${name == null ? 'Must' : '$name must'} be less than ${T == double ? 0.0 : 0}',
    ),
  );
}

/// Exact integer-specific constraints.
extension IntegerChecks on Schema<int> {
  /// Requires exact divisibility by a positive [divisor].
  Schema<int> multipleOf(int divisor, {String? code, String? message}) {
    if (divisor <= 0) {
      throw ArgumentError.value(divisor, 'divisor', 'Must be positive');
    }

    return withCheck(
      (value) => value % divisor == 0,
      IssueTemplate(
        code ?? 'MULTIPLE_OF',
        (name) => message ?? '${name == null ? 'Must' : '$name must'} be a multiple of $divisor',
      ),
    );
  }

  /// Restricts values to JavaScript's inclusive exact integer range.
  Schema<int> safe({String? code, String? message}) => withCheck(
    (value) => value >= -9007199254740991 && value <= 9007199254740991,
    IssueTemplate(
      code ?? 'SAFE_INTEGER',
      (name) =>
          message ??
          '${name == null ? 'Must' : '$name must'} be between -9007199254740991 and 9007199254740991',
    ),
  );
}

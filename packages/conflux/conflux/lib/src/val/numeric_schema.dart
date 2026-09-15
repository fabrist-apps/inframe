import 'package:conflux/option.dart';
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
    if (parsed.value case Some(:final value) when !value.isFinite) {
      return Evaluation.invalid(
        IssueTemplate(
          'NOT_FINITE',
          IssueKind.notFinite,
          'Must be a finite number',
          customCode: code,
          customMessage: message,
        ).at(path, base.name),
      );
    }
    return parsed;
  }, name: base.name);
}

/// Numeric constraints retain the receiver's exact numeric output type.
extension NumericChecks<T extends num> on Schema<T> {
  /// Requires a value at least [bound]. Non-finite bounds throw ArgumentError.
  Schema<T> min(T bound, {String? code, String? message}) {
    if (!bound.isFinite) throw ArgumentError.value(bound, 'bound', 'Must be finite');
    return withCheck(
      (value) => value >= bound,
      IssueTemplate(
        'MIN',
        IssueKind.tooSmall,
        'Must be at least $bound',
        customCode: code,
        customMessage: message,
      ),
    );
  }

  /// Requires a value at most [bound]. Non-finite bounds throw ArgumentError.
  Schema<T> max(T bound, {String? code, String? message}) {
    if (!bound.isFinite) throw ArgumentError.value(bound, 'bound', 'Must be finite');
    return withCheck(
      (value) => value <= bound,
      IssueTemplate(
        'MAX',
        IssueKind.tooBig,
        'Must be at most $bound',
        customCode: code,
        customMessage: message,
      ),
    );
  }

  /// Requires a value greater than [bound]. Non-finite bounds throw ArgumentError.
  Schema<T> greaterThan(T bound, {String? code, String? message}) {
    if (!bound.isFinite) throw ArgumentError.value(bound, 'bound', 'Must be finite');
    return withCheck(
      (value) => value > bound,
      IssueTemplate(
        'GREATER_THAN',
        IssueKind.tooSmall,
        'Must be greater than $bound',
        customCode: code,
        customMessage: message,
      ),
    );
  }

  /// Requires a value less than [bound]. Non-finite bounds throw ArgumentError.
  Schema<T> lessThan(T bound, {String? code, String? message}) {
    if (!bound.isFinite) throw ArgumentError.value(bound, 'bound', 'Must be finite');
    return withCheck(
      (value) => value < bound,
      IssueTemplate(
        'LESS_THAN',
        IssueKind.tooBig,
        'Must be less than $bound',
        customCode: code,
        customMessage: message,
      ),
    );
  }

  /// Requires a strictly positive value; zero is rejected.
  Schema<T> positive({String? code, String? message}) => withCheck(
    (value) => value > 0,
    IssueTemplate(
      'GREATER_THAN',
      IssueKind.tooSmall,
      'Must be greater than ${T == double ? 0.0 : 0}',
      customCode: code,
      customMessage: message,
    ),
  );

  /// Requires a strictly negative value; zero is rejected.
  Schema<T> negative({String? code, String? message}) => withCheck(
    (value) => value < 0,
    IssueTemplate(
      'LESS_THAN',
      IssueKind.tooBig,
      'Must be less than ${T == double ? 0.0 : 0}',
      customCode: code,
      customMessage: message,
    ),
  );
}

/// Exact integer-specific constraints.
extension IntegerChecks on Schema<int> {
  /// Requires exact divisibility by a positive [divisor].
  Schema<int> multipleOf(int divisor, {String? code, String? message}) {
    if (divisor <= 0) throw ArgumentError.value(divisor, 'divisor', 'Must be positive');
    return withCheck(
      (value) => value % divisor == 0,
      IssueTemplate(
        'MULTIPLE_OF',
        IssueKind.notMultipleOf,
        'Must be a multiple of $divisor',
        customCode: code,
        customMessage: message,
      ),
    );
  }

  /// Restricts values to JavaScript's inclusive exact integer range.
  Schema<int> safe({String? code, String? message}) => withCheck(
    (value) => value >= -9007199254740991 && value <= 9007199254740991,
    IssueTemplate(
      'SAFE_INTEGER',
      IssueKind.unsafeInteger,
      'Must be between -9007199254740991 and 9007199254740991',
      customCode: code,
      customMessage: message,
    ),
  );
}

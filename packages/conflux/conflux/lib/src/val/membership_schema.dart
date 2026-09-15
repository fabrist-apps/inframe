import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// A primitive literal validator retaining its expected value for discriminators.
final class LiteralSchema<T extends Object> extends Schema<T> {
  /// Validates literal configuration immediately.
  factory LiteralSchema(T expected, {String? name, String? code, String? message}) {
    if (!(expected is String || expected is bool || expected is num && expected.isFinite)) {
      throw ArgumentError.value(
        expected,
        'expected',
        'Must be a string, boolean, or finite number',
      );
    }
    return LiteralSchema._(
      expected,
      membershipSchema<T>(
        (value) => value == expected,
        defaultCode: 'INVALID_LITERAL',
        defaultMessage: 'Must equal the expected value',
        name: name,
        code: code,
        message: message,
      ),
    );
  }
  LiteralSchema._(this.expected, Schema<T> schema)
    : super.internal(
        schema.evaluate,
        name: schema.name,
        isOptional: schema.isOptional,
        missingCode: schema.missingCode,
        missingMessage: schema.missingMessage,
      );

  /// The configured primitive value.
  final T expected;

  @override
  LiteralSchema<T> optional() => LiteralSchema._(expected, super.optional());
  @override
  LiteralSchema<T> required({String? code, String? message}) =>
      LiteralSchema._(expected, super.required(code: code, message: message));
}

/// Internal enum configuration validation and collection ownership.
Schema<T> enumSchema<T extends Object>(
  List<T> values, {
  String? name,
  String? code,
  String? message,
}) {
  if (values.isEmpty || values.toSet().length != values.length) {
    throw ArgumentError.value(values, 'values', 'Must be nonempty without duplicates');
  }
  final copied = List<T>.unmodifiable(values);
  return membershipSchema<T>(
    copied.contains,
    defaultCode: 'INVALID_ENUM',
    defaultMessage: 'Must be one of the allowed values',
    name: name,
    code: code,
    message: message,
  );
}

/// Internal membership validation combines the type and membership check.
Schema<T> membershipSchema<T extends Object>(
  bool Function(T) accepts, {
  required String defaultCode,
  required String defaultMessage,
  String? name,
  String? code,
  String? message,
}) {
  final label = name == null || name.trim().isEmpty ? null : name.trim();
  return Schema.internal((input, context, path) {
    if (input is T && accepts(input)) return Evaluation.valid(input);
    return Evaluation.invalid(
      IssueTemplate(
        input == null ? 'NOT_NULL' : defaultCode,
        input == null ? IssueKind.invalidType : IssueKind.invalidValue,
        input == null ? 'Must not be null' : defaultMessage,
        customCode: code,
        customMessage: message,
      ).at(path, label),
    );
  }, name: label);
}

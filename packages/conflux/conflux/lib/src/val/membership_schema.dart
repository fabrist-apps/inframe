import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal enum configuration and membership validation.
Schema<T> enumSchema<T extends Object>(
  List<T> values, {
  String? name,
  String? code,
  String? message,
}) {
  final copied = List<T>.unmodifiable(values);

  return membershipSchema<T>(
    copied.contains,
    defaultCode: 'INVALID_ENUM',
    defaultMessage: (name) =>
        '${name == null ? 'Must' : '$name must'} be one of the allowed values',
    name: name,
    code: code,
    message: message,
  );
}

/// Internal membership validation combines the type and membership check.
Schema<T> membershipSchema<T extends Object>(
  bool Function(T) accepts, {
  required String defaultCode,
  required String Function(String? name) defaultMessage,
  String? name,
  String? code,
  String? message,
}) {
  final label = normalizeSchemaName(name);

  return Schema.internal((input, context, path) {
    if (input is T && accepts(input)) {
      return Success(input);
    }

    if (input == null) {
      return invalid(
        invalidTypeIssue(
          input: input,
          expected: 'a value',
          path: path,
          name: label,
          code: code,
          message: message,
        ),
      );
    }

    return invalid(
      IssueTemplate(
        code ?? defaultCode,
        (name) => message ?? defaultMessage(name),
      ).at(path, label),
    );
  }, name: label);
}

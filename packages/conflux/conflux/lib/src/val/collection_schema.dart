import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal typed list parser; intrinsic child failures suppress list checks.
Schema<List<T>> listSchema<T>(Schema<T> items, {String? name, String? code, String? message}) {
  final label = normalizeSchemaName(name);

  return Schema.internal((input, context, path) {
    if (input is! List) {
      return invalid(
        invalidTypeIssue(
          input: input,
          expected: 'a list',
          path: path,
          name: label,
          code: code,
          message: message,
        ),
      );
    }

    final output = <T>[];
    final issues = <ValidationIssue>[];

    for (var index = 0; index < input.length; index++) {
      switch (items.evaluate(input[index], context, [...path, IndexSegment(index)])) {
        case Success(:final value):
          output.add(value);
        case Failure(:final error):
          issues.addAll(error);
      }
    }

    return issues.isEmpty ? Success(List<T>.unmodifiable(output)) : invalidAll(issues);
  }, name: label);
}

/// Internal homogeneous map parser; keys are validated before any values.
Schema<Map<String, T>> mapSchema<T>(
  Schema<T> values, {
  String? name,
  String? code,
  String? message,
}) {
  final label = normalizeSchemaName(name);

  return Schema.internal((input, context, path) {
    if (input is! Map || input.keys.any((key) => key is! String)) {
      return invalid(
        invalidTypeIssue(
          input: input,
          expected: 'an object with string keys',
          path: path,
          name: label,
          code: code,
          message: message,
        ),
      );
    }

    final output = <String, T>{};
    final issues = <ValidationIssue>[];

    for (final entry in input.entries) {
      final key = entry.key as String;

      switch (values.evaluate(entry.value, context, [...path, FieldSegment(key)])) {
        case Success(:final value):
          output[key] = value;
        case Failure(:final error):
          issues.addAll(error);
      }
    }

    return issues.isEmpty ? Success(Map<String, T>.unmodifiable(output)) : invalidAll(issues);
  }, name: label);
}

/// List constraints run only after every element has parsed successfully.
extension ListChecks<T> on Schema<List<T>> {
  /// Requires at least [minimum] elements.
  Schema<List<T>> minLength(int minimum, {String? code, String? message}) => _length(
    minimum,
    (length) => length >= minimum,
    'MIN_LENGTH',
    'at least',
    code,
    message,
  );

  /// Requires at most [maximum] elements.
  Schema<List<T>> maxLength(int maximum, {String? code, String? message}) => _length(
    maximum,
    (length) => length <= maximum,
    'MAX_LENGTH',
    'at most',
    code,
    message,
  );

  /// Requires exactly [length] elements.
  Schema<List<T>> length(int length, {String? code, String? message}) => _length(
    length,
    (actual) => actual == length,
    'LENGTH',
    'exactly',
    code,
    message,
  );

  /// Alias for minLength(1).
  Schema<List<T>> notEmpty({String? code, String? message}) =>
      minLength(1, code: code, message: message);

  /// Rejects duplicates using Dart == on parsed values, with one list-path issue.
  Schema<List<T>> unique({String? code, String? message}) => withCheck(
    (values) {
      for (var index = 0; index < values.length; index++) {
        for (var prior = 0; prior < index; prior++) {
          if (values[prior] == values[index]) {
            return false;
          }
        }
      }

      return true;
    },
    IssueTemplate(
      code ?? 'UNIQUE',
      (name) => message ?? '${name == null ? 'Must' : '$name must'} contain unique items',
    ),
  );

  Schema<List<T>> _length(
    int count,
    bool Function(int) accepts,
    String defaultCode,
    String comparison,
    String? code,
    String? message,
  ) => withCheck(
    (value) => accepts(value.length),
    IssueTemplate(
      code ?? defaultCode,
      (name) =>
          message ??
          '${name == null ? 'Must' : '$name must'} contain $comparison $count ${count == 1 ? 'item' : 'items'}',
    ),
  );
}

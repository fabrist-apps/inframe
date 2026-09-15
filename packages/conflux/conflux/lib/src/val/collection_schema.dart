import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal typed list parser; intrinsic child failures suppress list checks.
Schema<List<T>> listSchema<T>(Schema<T> items, {String? name, String? code, String? message}) {
  final label = name == null || name.trim().isEmpty ? null : name.trim();
  return Schema.internal((input, context, path) {
    if (input is! List) {
      return Evaluation.invalid(
        IssueTemplate(
          input == null ? 'NOT_NULL' : 'INVALID_TYPE',
          IssueKind.invalidType,
          input == null ? 'Must not be null' : 'Must be a list',
          customCode: code,
          customMessage: message,
        ).at(path, label),
      );
    }
    final values = <T>[];
    final issues = <ValidationIssue>[];
    for (var index = 0; index < input.length; index++) {
      switch (items.evaluate(input[index], context, [...path, Index(index)]).finish()) {
        case Success(:final value):
          values.add(value);
        case Failure(:final error):
          issues.addAll(error);
      }
    }
    if (issues.isNotEmpty) return Evaluation(const None(), issues);
    return Evaluation.valid(List<T>.unmodifiable(values));
  }, name: label);
}

/// Internal homogeneous map parser; keys are validated before any values.
Schema<Map<String, T>> mapSchema<T>(
  Schema<T> values, {
  String? name,
  String? code,
  String? message,
}) {
  final label = name == null || name.trim().isEmpty ? null : name.trim();
  return Schema.internal((input, context, path) {
    if (input is! Map || input.keys.any((key) => key is! String)) {
      return Evaluation.invalid(
        IssueTemplate(
          input == null ? 'NOT_NULL' : 'INVALID_TYPE',
          IssueKind.invalidType,
          input == null ? 'Must not be null' : 'Must be an object with string keys',
          customCode: code,
          customMessage: message,
        ).at(path, label),
      );
    }
    final output = <String, T>{};
    final issues = <ValidationIssue>[];
    for (final entry in input.entries) {
      final key = entry.key;
      if (key is! String) continue;
      switch (values.evaluate(entry.value, context, [...path, Field(key)]).finish()) {
        case Success(:final value):
          output[key] = value;
        case Failure(:final error):
          issues.addAll(error);
      }
    }
    if (issues.isNotEmpty) return Evaluation(const None(), issues);
    return Evaluation.valid(Map<String, T>.unmodifiable(output));
  }, name: label);
}

/// List constraints run only after every element has parsed successfully.
extension ListChecks<T> on Schema<List<T>> {
  /// Requires at least [minimum] elements.
  Schema<List<T>> minLength(int minimum, {String? code, String? message}) => _length(
    minimum,
    (length) => length >= minimum,
    'MIN_LENGTH',
    IssueKind.tooSmall,
    'at least',
    code,
    message,
  );

  /// Requires at most [maximum] elements.
  Schema<List<T>> maxLength(int maximum, {String? code, String? message}) => _length(
    maximum,
    (length) => length <= maximum,
    'MAX_LENGTH',
    IssueKind.tooBig,
    'at most',
    code,
    message,
  );

  /// Requires exactly [length] elements.
  Schema<List<T>> length(int length, {String? code, String? message}) => _length(
    length,
    (actual) => actual == length,
    'LENGTH',
    IssueKind.invalidLength,
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
          if (values[prior] == values[index]) return false;
        }
      }
      return true;
    },
    IssueTemplate(
      'UNIQUE',
      IssueKind.notUnique,
      'Must contain unique items',
      customCode: code,
      customMessage: message,
    ),
  );

  Schema<List<T>> _length(
    int count,
    bool Function(int) accepts,
    String defaultCode,
    IssueKind kind,
    String comparison,
    String? code,
    String? message,
  ) {
    if (count < 0) throw ArgumentError.value(count, 'length', 'Must be non-negative');
    return withCheck(
      (value) => accepts(value.length),
      IssueTemplate(
        defaultCode,
        kind,
        'Must contain $comparison $count ${count == 1 ? 'item' : 'items'}',
        customCode: code,
        customMessage: message,
      ),
    );
  }
}

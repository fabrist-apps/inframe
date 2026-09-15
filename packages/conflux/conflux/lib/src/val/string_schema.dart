import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// A schema with a non-nullable string output.
typedef StringSchema = Schema<String>;

/// String constraints preserve access to other string constraints.
extension StringChecks on Schema<String> {
  /// Requires at least [minimum] UTF-16 code units.
  StringSchema minLength(int minimum, {String? code, String? message}) => _length(
    minimum,
    (length) => length >= minimum,
    'MIN_LENGTH',
    IssueKind.tooSmall,
    'at least',
    code,
    message,
  );

  /// Requires at most [maximum] UTF-16 code units.
  StringSchema maxLength(int maximum, {String? code, String? message}) => _length(
    maximum,
    (length) => length <= maximum,
    'MAX_LENGTH',
    IssueKind.tooBig,
    'at most',
    code,
    message,
  );

  /// Requires exactly [length] UTF-16 code units.
  StringSchema length(int length, {String? code, String? message}) => _length(
    length,
    (actual) => actual == length,
    'LENGTH',
    IssueKind.invalidLength,
    'exactly',
    code,
    message,
  );

  /// Alias for minLength(1).
  StringSchema notEmpty({String? code, String? message}) =>
      minLength(1, code: code, message: message);

  StringSchema _length(
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
        'Must contain $comparison $count ${count == 1 ? 'character' : 'characters'}',
        customCode: code,
        customMessage: message,
      ),
    );
  }
}

import 'package:conflux/moment.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// A schema whose parsed output is a non-null Moment.
typedef MomentSchema = Schema<Moment>;

/// Instant bounds work for UTC and zoned values without normalizing them.
extension MomentChecks<T extends Moment?> on Schema<T> {
  /// Requires an instant at or after [minimum], inclusively. Nullable null skips it.
  Schema<T> min(Moment minimum, {String? code, String? message}) => withCheck(
    (value) => value == null || value.compareTo(minimum) >= 0,
    IssueTemplate(
      'MIN_MOMENT',
      IssueKind.tooSmall,
      'Must be at or after ${minimum.formatIso()}',
      customCode: code,
      customMessage: message,
    ),
  );

  /// Requires an instant at or before [maximum], inclusively. Nullable null skips it.
  Schema<T> max(Moment maximum, {String? code, String? message}) => withCheck(
    (value) => value == null || value.compareTo(maximum) <= 0,
    IssueTemplate(
      'MAX_MOMENT',
      IssueKind.tooBig,
      'Must be at or before ${maximum.formatIso()}',
      customCode: code,
      customMessage: message,
    ),
  );
}

/// Timestamp validation and conversion sit above both Val core and Moment.
extension StringMomentChecks on Schema<String> {
  /// Validates through Moment.parse and retains the original string.
  Schema<String> datetime({String? code, String? message}) =>
      withCheck((value) => Moment.parse(value).isSuccess, _timestampIssue(code, message));

  /// Converts only after preceding string checks pass. Later checks receive Moment.
  MomentSchema moment({String? code, String? message}) => Schema.internal(
    (input, context, path) {
      switch (evaluate(input, context, path).finish()) {
        case Failure(:final error):
          return Evaluation(const None(), error);
        case Success(:final value):
          return _parseMoment(value, path, name, code, message);
      }
    },
    name: name,
    isOptional: isOptional,
    missingCode: missingCode,
    missingMessage: missingMessage,
    isNullable: isNullable,
  );
}

/// Nullable string conversion preserves the source stage's treatment of null.
extension NullableStringMomentChecks on Schema<String?> {
  /// Converts present strings while retaining nullable output and source checks.
  Schema<Moment?> moment({String? code, String? message}) => Schema.internal(
    (input, context, path) {
      switch (evaluate(input, context, path).finish()) {
        case Failure(:final error):
          return Evaluation(const None(), error);
        case Success(:final value):
          return value == null
              ? Evaluation.valid(null)
              : _parseMoment(value, path, name, code, message);
      }
    },
    name: name,
    isOptional: isOptional,
    missingCode: missingCode,
    missingMessage: missingMessage,
    isNullable: isNullable,
  );
}

IssueTemplate _timestampIssue(String? code, String? message) => IssueTemplate(
  'INVALID_MOMENT',
  IssueKind.invalidFormat,
  'Must be a valid timestamp',
  customCode: code,
  customMessage: message,
);

Evaluation<Moment> _parseMoment(
  String value,
  List<PathSegment> path,
  String? name,
  String? code,
  String? message,
) => switch (Moment.parse(value)) {
  Success(:final value) => Evaluation.valid(value),
  Failure() => Evaluation.invalid(_timestampIssue(code, message).at(path, name)),
};

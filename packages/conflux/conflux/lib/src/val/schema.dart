import 'package:conflux/non_empty_list.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';

/// Internal traversal state owned by one public parse, never by a schema.
final class ParseContext {
  /// Active lazy entries for this traversal.
  final Map<Object, int> lazyDepth = Map.identity();
}

/// Internal stage output: predicates retain a typed candidate to accumulate
/// subsequent predicate failures. A conversion or container consumes [finish].
final class Evaluation<T> {
  /// Retains a typed candidate and copies the accumulated failures.
  Evaluation(this.value, [Iterable<ValidationIssue> issues = const []])
    : issues = List.unmodifiable(issues);

  /// A successful intrinsic parse.
  Evaluation.valid(T value) : this(Some(value));

  /// A failure with no candidate for subsequent checks.
  Evaluation.invalid(ValidationIssue issue) : this(const None(), [issue]);

  /// Candidate available to compatible predicates, including nullable null.
  final Option<T> value;

  /// Immutable failures in declaration order.
  final List<ValidationIssue> issues;

  /// Consumes a completed stage, discarding candidates when any check failed.
  Result<T, NonEmptyList<ValidationIssue>> finish() {
    if (issues.isNotEmpty) return Failure(NonEmptyList(issues.first, issues.skip(1)));
    return switch (value) {
      Some(:final value) => Success(value),
      None() => throw StateError('Validation produced neither a value nor an issue'),
    };
  }
}

/// Internal parser function; nested parsing shares its context and path.
typedef ParseValue<T> = Evaluation<T> Function(
  Object? input,
  ParseContext context,
  List<PathSegment> path,
);

/// An immutable synchronous validator producing exactly [T].
///
/// Optionality controls object membership, not nullability. Callback exceptions
/// propagate unchanged; callbacks may run again on repeated or union parses.
class Schema<T> {
  /// Internal construction for schema implementations.
  Schema.internal(
    this.evaluate, {
    String? name,
    this.isOptional = false,
    this.missingCode,
    this.missingMessage,
    this.isNullable = false,
  }) : name = name == null || name.trim().isEmpty ? null : name.trim();

  /// Internal typed stage evaluator.
  final ParseValue<T> evaluate;

  /// Human-readable name used only by generated messages.
  final String? name;

  /// Whether an absent object field is omitted.
  final bool isOptional;

  /// Internal missing-field overrides.
  final String? missingCode;

  /// Internal missing-field override text.
  final String? missingMessage;

  /// Whether an explicit nullable wrapper has been added.
  final bool isNullable;

  /// Validates a present input, including a present null.
  Result<T, NonEmptyList<ValidationIssue>> safeParse(Object? input) =>
      evaluate(input, ParseContext(), const []).finish();

  /// Returns the parsed value or throws [ValidationException].
  T parse(Object? input) => safeParse(input).getOrThrowWith(ValidationException.new);

  /// Allows an absent object field; does not change the output type.
  Schema<T> optional() => copyPresence(optional: true);

  /// Requires object membership, replacing prior missing-field overrides.
  Schema<T> required({String? code, String? message}) =>
      copyPresence(optional: false, code: code, message: message);

  /// Accepts null before the current stage, skipping its checks for null.
  Schema<T?> nullable() => Schema<T?>.internal(
    (input, context, path) =>
        input == null ? Evaluation.valid(null) : evaluate(input, context, path),
    name: name,
    isOptional: isOptional,
    missingCode: missingCode,
    missingMessage: missingMessage,
    isNullable: true,
  );

  /// Internal presence derivation, also used by specialized schemas.
  Schema<T> copyPresence({required bool optional, String? code, String? message}) =>
      Schema.internal(
        evaluate,
        name: name,
        isOptional: optional,
        missingCode: code,
        missingMessage: message,
        isNullable: isNullable,
      );

  /// Internal missing-field evaluation using Conflux Option presence.
  Evaluation<T>? field(Option<Object?> input, ParseContext context, List<PathSegment> path) =>
      switch (input) {
        Some(:final value) => evaluate(value, context, path),
        None() when isOptional => null,
        None() => Evaluation.invalid(
          IssueTemplate(
            'REQUIRED',
            IssueKind.missing,
            'Value is required',
            customCode: missingCode,
            customMessage: missingMessage,
          ).at(path, name),
        ),
      };
}

/// Typed predicate derivation lives in an extension to allow sound widening.
extension SchemaRefinement<T> on Schema<T> {
  /// Adds a synchronous predicate; its path is relative to this schema.
  Schema<T> refine(
    bool Function(T value) predicate, {
    List<PathSegment> path = const [],
    String? code,
    String? message,
  }) => withCheck(
    predicate,
    IssueTemplate(
      'CUSTOM',
      IssueKind.custom,
      'Invalid value',
      customCode: code,
      customMessage: message,
    ),
    path: path,
  );
}

/// Internal typed stage composition, excluded from the public barrel.
extension SchemaChecksInternal<T> on Schema<T> {
  /// Internal predicate stage that accumulates failures without losing [T].
  Schema<T> withCheck(
    bool Function(T value) predicate,
    IssueTemplate issue, {
    List<PathSegment> path = const [],
  }) {
    final relativePath = List<PathSegment>.unmodifiable(path);
    return Schema.internal(
      (input, context, currentPath) {
        final parsed = evaluate(input, context, currentPath);
        if (parsed.value case Some(:final value)) {
          if (!predicate(value)) {
            return Evaluation(parsed.value, [
              ...parsed.issues,
              issue.at([...currentPath, ...relativePath], name),
            ]);
          }
        }
        return parsed;
      },
      name: name,
      isOptional: isOptional,
      missingCode: missingCode,
      missingMessage: missingMessage,
      isNullable: isNullable,
    );
  }
}

/// Internal construction of non-coercing primitive schemas.
Schema<T> typeSchema<T>({required String type, String? name, String? code, String? message}) {
  final label = name == null || name.trim().isEmpty ? null : name.trim();
  return Schema.internal((input, context, path) {
    if (input is T) return Evaluation.valid(input);
    return Evaluation.invalid(
      IssueTemplate(
        input == null ? 'NOT_NULL' : 'INVALID_TYPE',
        IssueKind.invalidType,
        input == null ? 'Must not be null' : 'Must be $type',
        customCode: code,
        customMessage: message,
      ).at(path, label),
    );
  }, name: label);
}

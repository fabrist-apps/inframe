import 'package:conflux/non_empty_list.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';

/// Internal traversal state owned by one public parse, never by a schema.
final class ParseContext {
  /// Active lazy entries for this traversal.
  final Map<Object, int> lazyDepth = Map.identity();
}

/// Internal parser result.
typedef ParseResult<T> = Result<T, NonEmptyList<ValidationIssue>>;

/// Internal parser function; nested parsing shares its context and path.
typedef ParseValue<T> = ParseResult<T> Function(
  Object? input,
  ParseContext context,
  List<PathSegment> path,
);

/// Normalizes the optional label used in generated issue messages.
String? normalizeSchemaName(String? name) {
  final trimmed = name?.trim();

  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Creates an internal parser failure containing one issue.
ParseResult<T> invalid<T>(ValidationIssue issue) => Failure(NonEmptyList(issue));

/// Creates an internal parser failure from a known non-empty issue list.
ParseResult<T> invalidAll<T>(List<ValidationIssue> issues) =>
    Failure(NonEmptyList(issues.first, issues.skip(1)));

/// Creates the standard null or runtime-type issue.
ValidationIssue invalidTypeIssue({
  required Object? input,
  required String expected,
  required List<PathSegment> path,
  String? name,
  String? code,
  String? message,
}) => IssueTemplate(
  code ?? (input == null ? 'NOT_NULL' : 'INVALID_TYPE'),
  (name) =>
      message ??
      (input == null
          ? '${name == null ? 'Must' : '$name must'} not be null'
          : '${name == null ? 'Must' : '$name must'} be $expected'),
).at(path, name);

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
  }) : name = normalizeSchemaName(name);

  /// Internal parser.
  final ParseValue<T> evaluate;

  /// Human-readable name used only by generated messages.
  final String? name;

  /// Whether an absent object field is omitted.
  final bool isOptional;

  /// Internal missing-field overrides.
  final String? missingCode;

  /// Internal missing-field override text.
  final String? missingMessage;

  /// Validates a present input, including a present null.
  ParseResult<T> safeParse(Object? input) => evaluate(input, ParseContext(), const []);

  /// Returns the parsed value or throws [ValidationException].
  T parse(Object? input) => safeParse(input).getOrThrowWith(ValidationException.new);

  /// Allows an absent object field; does not change the output type.
  Schema<T> optional() => copyPresence(optional: true);

  /// Requires object membership, replacing prior missing-field overrides.
  Schema<T> required({String? code, String? message}) =>
      copyPresence(optional: false, code: code, message: message);

  /// Accepts null before the current stage, skipping its checks for null.
  Schema<T?> nullable() => Schema<T?>.internal(
    (input, context, path) => input == null ? const Success(null) : evaluate(input, context, path),
    name: name,
    isOptional: isOptional,
    missingCode: missingCode,
    missingMessage: missingMessage,
  );

  /// Internal presence derivation.
  Schema<T> copyPresence({required bool optional, String? code, String? message}) =>
      Schema.internal(
        evaluate,
        name: name,
        isOptional: optional,
        missingCode: code,
        missingMessage: message,
      );

  /// Evaluates one object field, returning null when an optional field is absent.
  ParseResult<T>? field({
    required bool isPresent,
    required Object? input,
    required ParseContext context,
    required List<PathSegment> path,
  }) {
    if (isPresent) {
      return evaluate(input, context, path);
    }

    if (isOptional) {
      return null;
    }

    return invalid(
      IssueTemplate(
        missingCode ?? 'REQUIRED',
        (name) => missingMessage ?? '${name ?? 'Value'} is required',
      ).at(path, name),
    );
  }
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
      code ?? 'CUSTOM',
      (name) => message ?? (name == null ? 'Invalid value' : '$name is invalid'),
    ),
    path: path,
  );
}

/// Internal typed stage composition, excluded from the public barrel.
extension SchemaChecksInternal<T> on Schema<T> {
  /// Adds a predicate that runs only when every preceding stage succeeded.
  Schema<T> withCheck(
    bool Function(T value) predicate,
    IssueTemplate issue, {
    List<PathSegment> path = const [],
  }) {
    final relativePath = List<PathSegment>.unmodifiable(path);

    return Schema.internal(
      (input, context, currentPath) => switch (evaluate(input, context, currentPath)) {
        Success(:final value) when predicate(value) => Success(value),
        Success() => invalid(issue.at([...currentPath, ...relativePath], name)),
        Failure(:final error) => Failure(error),
      },
      name: name,
      isOptional: isOptional,
      missingCode: missingCode,
      missingMessage: missingMessage,
    );
  }
}

/// Internal construction of non-coercing primitive schemas.
Schema<T> typeSchema<T>({
  required String type,
  String? name,
  String? code,
  String? message,
}) {
  final label = normalizeSchemaName(name);

  return Schema.internal(
    (input, context, path) => input is T
        ? Success(input)
        : invalid(
            invalidTypeIssue(
              input: input,
              expected: type,
              path: path,
              name: label,
              code: code,
              message: message,
            ),
          ),
    name: label,
  );
}

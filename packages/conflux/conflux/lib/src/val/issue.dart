// Path values are immutable without an annotation-only dependency.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:conflux/non_empty_list.dart';

/// The category of a validation failure, independent of its application code.
enum IssueKind {
  /// An absent required field.
  missing,

  /// An incompatible input type or rejected null.
  invalidType,

  /// A value outside a literal or enum's membership.
  invalidValue,

  /// A malformed string.
  invalidFormat,

  /// A value below a lower bound.
  tooSmall,

  /// A value above an upper bound.
  tooBig,

  /// An incorrect exact length.
  invalidLength,

  /// An integer not divisible by the configured divisor.
  notMultipleOf,

  /// An integer outside JavaScript's exact range.
  unsafeInteger,

  /// NaN or infinity.
  notFinite,

  /// Duplicate list elements.
  notUnique,

  /// An unknown object key.
  unrecognizedKey,

  /// No alternative accepted the input.
  invalidUnion,

  /// A discriminator could not select a branch.
  invalidDiscriminator,

  /// A recursive traversal exceeded its bound.
  maxDepth,

  /// A caller predicate rejected a value.
  custom,
}

/// One structural step from the parse root.
sealed class PathSegment {
  const PathSegment();
}

/// An object field or map key, including the empty string.
final class Field extends PathSegment {
  /// Identifies [name] without using a schema's human-readable label.
  const Field(this.name);

  /// The original key.
  final String name;

  @override
  bool operator ==(Object other) => other is Field && other.name == name;
  @override
  int get hashCode => Object.hash(Field, name);
  @override
  String toString() => name;
}

/// A non-negative list position.
final class Index extends PathSegment {
  /// Throws [ArgumentError] for a negative index.
  Index(this.index) {
    if (index < 0) throw ArgumentError.value(index, 'index', 'Must be non-negative');
  }

  /// The zero-based position.
  final int index;

  @override
  bool operator ==(Object other) => other is Index && other.index == index;
  @override
  int get hashCode => Object.hash(Index, index);
  @override
  String toString() => '[$index]';
}

/// A validation failure with an immutable structural location.
final class ValidationIssue {
  /// Copies [path]; codes and messages are retained verbatim.
  ValidationIssue({
    required this.code,
    required this.message,
    required this.kind,
    required List<PathSegment> path,
  }) : path = List.unmodifiable(path);

  /// The default or application-provided string code.
  final String code;

  /// Human-readable default or verbatim custom text.
  final String message;

  /// Library-owned failure category.
  final IssueKind kind;

  /// Location relative to the parse root; empty for a root failure.
  final List<PathSegment> path;
}

/// Thrown by Schema.parse for expected validation failures.
final class ValidationException implements Exception {
  /// Retains the same nonempty issues exposed by safeParse.
  const ValidationException(this.issues);

  /// All expected failures in validation order.
  final NonEmptyList<ValidationIssue> issues;

  @override
  String toString() => 'ValidationException: ${issues.map((issue) => issue.message).join('; ')}';
}

/// Internal immutable message configuration shared by schemas and checks.
final class IssueTemplate {
  /// Null overrides select defaults; empty strings are explicit overrides.
  const IssueTemplate(this.code, this.kind, this.message, {this.customCode, this.customMessage});

  /// Default stable code.
  final String code;

  /// Library-owned category.
  final IssueKind kind;

  /// Unnamed default message.
  final String message;

  /// Verbatim code override.
  final String? customCode;

  /// Verbatim message override.
  final String? customMessage;

  /// Creates one issue with a copied path and a local schema label.
  ValidationIssue at(List<PathSegment> path, String? name) {
    final named = name == null
        ? message
        : switch (message) {
            'Value is required' => '$name is required',
            'Invalid value' => '$name is invalid',
            'Property is not allowed' => 'Property is not allowed in $name',
            _ when message.startsWith('Must') => '$name must${message.substring(4)}',
            _ => message,
          };
    return ValidationIssue(
      code: customCode ?? code,
      message: customMessage ?? named,
      kind: kind,
      path: path,
    );
  }
}

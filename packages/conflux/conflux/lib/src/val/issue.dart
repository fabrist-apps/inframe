import 'package:conflux/non_empty_list.dart';
import 'package:conflux/src/val/path.dart';
import 'package:dart_mappable/dart_mappable.dart';

export 'package:conflux/src/val/path.dart';

part 'issue.mapper.dart';

/// A validation failure with an immutable structural location.
@MappableClass()
final class ValidationIssue with ValidationIssueMappable {
  /// Copies [path]; codes and messages are retained verbatim.
  ValidationIssue({
    required this.code,
    required this.message,
    required List<PathSegment> path,
  }) : path = List.unmodifiable(path);

  /// The default or application-provided string code.
  final String code;

  /// Human-readable default or verbatim custom text.
  final String message;

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
  /// Retains the resolved code and a message builder receiving the schema name.
  const IssueTemplate(this.code, this.message);

  /// Resolved stable code.
  final String code;

  /// Builds default or custom text for the local schema name.
  final String Function(String? name) message;

  /// Creates one issue with a copied path and a local schema label.
  ValidationIssue at(List<PathSegment> path, String? name) =>
      ValidationIssue(code: code, message: message(name), path: path);
}

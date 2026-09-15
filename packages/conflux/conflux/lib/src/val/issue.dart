import 'package:conflux/non_empty_list.dart';
import 'package:conflux/src/val/path.dart' hide Field;
import 'package:conflux/src/val/path.dart' as structural show Field;
import 'package:dart_mappable/dart_mappable.dart';

export 'package:conflux/src/val/path.dart';

part 'issue.mapper.dart';

/// The category of a validation failure, independent of its application code.
@MappableEnum()
enum IssueKind {
  /// An absent required field.
  @MappableValue('missing')
  missing,

  /// An incompatible input type or rejected null.
  @MappableValue('invalidType')
  invalidType,

  /// A value outside a literal or enum's membership.
  @MappableValue('invalidValue')
  invalidValue,

  /// A malformed string.
  @MappableValue('invalidFormat')
  invalidFormat,

  /// A value below a lower bound.
  @MappableValue('tooSmall')
  tooSmall,

  /// A value above an upper bound.
  @MappableValue('tooBig')
  tooBig,

  /// An incorrect exact length.
  @MappableValue('invalidLength')
  invalidLength,

  /// An integer not divisible by the configured divisor.
  @MappableValue('notMultipleOf')
  notMultipleOf,

  /// An integer outside JavaScript's exact range.
  @MappableValue('unsafeInteger')
  unsafeInteger,

  /// NaN or infinity.
  @MappableValue('notFinite')
  notFinite,

  /// Duplicate list elements.
  @MappableValue('notUnique')
  notUnique,

  /// An unknown object key.
  @MappableValue('unrecognizedKey')
  unrecognizedKey,

  /// No alternative accepted the input.
  @MappableValue('invalidUnion')
  invalidUnion,

  /// A discriminator could not select a branch.
  @MappableValue('invalidDiscriminator')
  invalidDiscriminator,

  /// A recursive traversal exceeded its bound.
  @MappableValue('maxDepth')
  maxDepth,

  /// A caller predicate rejected a value.
  @MappableValue('custom')
  custom,
}

/// A validation failure with an immutable structural location.
@MappableClass(includeCustomMappers: [_PathSegmentMapper()], hook: _IssueWireHook())
final class ValidationIssue with ValidationIssueMappable {
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

// Compact paths are a wire contract, independent of Dart class discriminators.
final class _PathSegmentMapper extends SimpleMapper<PathSegment> {
  const _PathSegmentMapper();
  @override
  PathSegment decode(Object value) => switch (value) {
    final String field => structural.Field(field),
    final int index when index >= 0 => Index(index),
    _ => throw const FormatException('Path segments must be strings or non-negative integers'),
  };
  @override
  Object encode(PathSegment self) => switch (self) {
    structural.Field(:final name) => name,
    Index(:final index) => index,
  };
}

// dart_mappable normally coerces primitive strings. Reject malformed wire
// fields before decoding so numeric application codes cannot silently change.
final class _IssueWireHook extends MappingHook {
  const _IssueWireHook();
  @override
  Object? beforeDecode(Object? value) {
    if (value is ValidationIssue) return value;
    if (value is! Map ||
        value['code'] is! String ||
        value['message'] is! String ||
        value['kind'] is! String ||
        value['path'] is! List) {
      throw const FormatException(
        'Validation issues require string code, message, kind, and a list path',
      );
    }
    final path = value['path'];
    if (path is List) {
      for (final segment in path) {
        if (segment is! String && !(segment is int && segment >= 0)) {
          throw const FormatException('Path segments must be strings or non-negative integers');
        }
      }
    }
    return value;
  }
}

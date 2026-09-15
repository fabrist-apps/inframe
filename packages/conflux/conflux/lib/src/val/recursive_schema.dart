import 'package:conflux/option.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal lazy schema owner. Only successful resolution is retained;
/// traversal depth belongs to each ParseContext, including on thrown callbacks.
final class LazyResolver<T> {
  /// Rejects invalid depth bounds before any builder can run.
  LazyResolver(this.build, {this.maxDepth = 64, String? name, this.code, this.message})
    : name = name == null || name.trim().isEmpty ? null : name.trim() {
    if (maxDepth <= 0) throw ArgumentError.value(maxDepth, 'maxDepth', 'Must be positive');
  }

  /// Synchronous caller-owned builder.
  final Schema<T> Function() build;

  /// Inclusive active-entry bound.
  final int maxDepth;

  /// Local depth-issue label.
  final String? name;

  /// Depth-issue code override.
  final String? code;

  /// Depth-issue message override.
  final String? message;
  Schema<T>? _resolved;
  bool _resolving = false;

  /// Creates the public schema while retaining this resolver's identity.
  Schema<T> schema() => Schema.internal(_evaluate, name: name);

  Schema<T> _resolve() {
    if (_resolving) throw StateError('Lazy schema builder re-entry');
    final resolved = _resolved;
    if (resolved != null) return resolved;
    _resolving = true;
    try {
      return _resolved = build();
    } finally {
      _resolving = false;
    }
  }

  Evaluation<T> _evaluate(Object? input, ParseContext context, List<PathSegment> path) {
    final previous = context.lazyDepth[this] ?? 0;
    if (previous >= maxDepth) {
      return Evaluation.invalid(
        IssueTemplate(
          'MAX_DEPTH',
          IssueKind.maxDepth,
          'Must not exceed the maximum nesting depth',
          customCode: code,
          customMessage: message,
        ).at(path, name),
      );
    }
    context.lazyDepth[this] = previous + 1;
    try {
      return _resolve().evaluate(input, context, path);
    } finally {
      if (previous == 0) {
        context.lazyDepth.remove(this);
      } else {
        context.lazyDepth[this] = previous;
      }
    }
  }
}

/// Internal arbitrary JSON traversal with identity-based active-container checks.
final class JsonSchema {
  /// Rejects invalid depth bounds at schema construction.
  JsonSchema({this.maxDepth = 64, String? name, this.code, this.message})
    : name = name == null || name.trim().isEmpty ? null : name.trim() {
    if (maxDepth <= 0) throw ArgumentError.value(maxDepth, 'maxDepth', 'Must be positive');
  }

  /// Maximum nested container count, including a root container at depth one.
  final int maxDepth;

  /// Local label for intrinsic JSON issues.
  final String? name;

  /// Intrinsic type/depth code override.
  final String? code;

  /// Intrinsic type/depth message override.
  final String? message;

  /// A non-null JSON-compatible root. Nested null remains valid.
  Schema<Object> schema() => Schema.internal((input, context, path) {
    if (input == null) return Evaluation.invalid(_issue(path, nullRoot: true));
    final result = _visit(input, path, 0, Set.identity());
    return switch (result.value) {
      Some(:final Object value) => Evaluation(Some(value), result.issues),
      _ => Evaluation(const None(), result.issues),
    };
  }, name: name);

  ValidationIssue _issue(List<PathSegment> path, {bool depth = false, bool nullRoot = false}) =>
      IssueTemplate(
        depth
            ? 'MAX_DEPTH'
            : nullRoot
            ? 'NOT_NULL'
            : 'INVALID_TYPE',
        depth ? IssueKind.maxDepth : IssueKind.invalidType,
        depth
            ? 'Must not exceed the maximum nesting depth'
            : nullRoot
            ? 'Must not be null'
            : 'Must be a JSON value',
        customCode: code,
        customMessage: message,
      ).at(path, name);

  Evaluation<Object?> _visit(Object? input, List<PathSegment> path, int depth, Set<Object> active) {
    if (input == null || input is String || input is bool || input is num && input.isFinite) {
      return Evaluation.valid(input);
    }
    if (input is! List && input is! Map) return Evaluation.invalid(_issue(path));
    if (input is Map && input.keys.any((key) => key is! String)) {
      return Evaluation.invalid(_issue(path));
    }
    if (depth >= maxDepth || !active.add(input)) {
      return Evaluation.invalid(_issue(path, depth: true));
    }
    try {
      final issues = <ValidationIssue>[];
      if (input is List) {
        final values = <Object?>[];
        for (var index = 0; index < input.length; index++) {
          final parsed = _visit(input[index], [...path, Index(index)], depth + 1, active);
          issues.addAll(parsed.issues);
          if (parsed.value case Some(:final value)) values.add(value);
        }
        return issues.isEmpty
            ? Evaluation.valid(List<Object?>.unmodifiable(values))
            : Evaluation(const None(), issues);
      }
      if (input is Map) {
        final values = <String, Object?>{};
        for (final entry in input.entries) {
          final key = entry.key;
          if (key is! String) continue;
          final parsed = _visit(entry.value, [...path, Field(key)], depth + 1, active);
          issues.addAll(parsed.issues);
          if (parsed.value case Some(:final value)) values[key] = value;
        }
        return issues.isEmpty
            ? Evaluation.valid(Map<String, Object?>.unmodifiable(values))
            : Evaluation(const None(), issues);
      }
      throw StateError('JSON container type changed during validation');
    } finally {
      active.remove(input);
    }
  }
}

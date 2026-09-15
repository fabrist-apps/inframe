import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal lazy schema owner. Only successful resolution is retained;
/// traversal depth belongs to each ParseContext, including on thrown callbacks.
final class LazyResolver<T> {
  /// Rejects invalid depth bounds before any builder can run.
  LazyResolver(this.build, {this.maxDepth = 64, String? name, this.code, this.message})
    : name = normalizeSchemaName(name) {
    if (maxDepth <= 0) {
      throw ArgumentError.value(maxDepth, 'maxDepth', 'Must be positive');
    }
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
    if (_resolving) {
      throw StateError('Lazy schema builder re-entry');
    }

    final resolved = _resolved;

    if (resolved != null) {
      return resolved;
    }

    _resolving = true;

    try {
      return _resolved = build();
    } finally {
      _resolving = false;
    }
  }

  ParseResult<T> _evaluate(Object? input, ParseContext context, List<PathSegment> path) {
    final previous = context.lazyDepth[this] ?? 0;

    if (previous >= maxDepth) {
      return invalid(
        IssueTemplate(
          code ?? 'MAX_DEPTH',
          (name) =>
              message ??
              '${name == null ? 'Must' : '$name must'} not exceed the maximum nesting depth',
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
    : name = normalizeSchemaName(name) {
    if (maxDepth <= 0) {
      throw ArgumentError.value(maxDepth, 'maxDepth', 'Must be positive');
    }
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
    if (input == null) {
      return invalid(_issue(path, nullRoot: true));
    }

    final result = _visit(input, path, 0, Set.identity());

    return switch (result) {
      Success(:final value) => Success(value!),
      Failure(:final error) => Failure(error),
    };
  }, name: name);

  ValidationIssue _issue(List<PathSegment> path, {bool depth = false, bool nullRoot = false}) =>
      IssueTemplate(
        code ??
            (depth
                ? 'MAX_DEPTH'
                : nullRoot
                ? 'NOT_NULL'
                : 'INVALID_TYPE'),
        (name) =>
            message ??
            (depth
                ? '${name == null ? 'Must' : '$name must'} not exceed the maximum nesting depth'
                : nullRoot
                ? '${name == null ? 'Must' : '$name must'} not be null'
                : '${name == null ? 'Must' : '$name must'} be a JSON value'),
      ).at(path, name);

  ParseResult<Object?> _visit(
    Object? input,
    List<PathSegment> path,
    int depth,
    Set<Object> active,
  ) {
    if (input == null || input is String || input is bool || input is num && input.isFinite) {
      return Success(input);
    }

    if (input is! List && input is! Map) {
      return invalid(_issue(path));
    }

    if (input is Map && input.keys.any((key) => key is! String)) {
      return invalid(_issue(path));
    }

    if (depth >= maxDepth || !active.add(input)) {
      return invalid(_issue(path, depth: true));
    }

    try {
      final issues = <ValidationIssue>[];

      if (input is List) {
        final values = <Object?>[];

        for (var index = 0; index < input.length; index++) {
          final parsed = _visit(input[index], [...path, IndexSegment(index)], depth + 1, active);
          switch (parsed) {
            case Success(:final value):
              values.add(value);
            case Failure(:final error):
              issues.addAll(error);
          }
        }

        return issues.isEmpty ? Success(List<Object?>.unmodifiable(values)) : invalidAll(issues);
      }

      final values = <String, Object?>{};

      for (final entry in (input as Map).entries) {
        final key = entry.key as String;

        final parsed = _visit(entry.value, [...path, FieldSegment(key)], depth + 1, active);
        switch (parsed) {
          case Success(:final value):
            values[key] = value;
          case Failure(:final error):
            issues.addAll(error);
        }
      }

      return issues.isEmpty
          ? Success(Map<String, Object?>.unmodifiable(values))
          : invalidAll(issues);
    } finally {
      active.remove(input);
    }
  }
}

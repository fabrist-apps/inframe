import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal ordered alternatives; failures are summarized only after all fail.
Schema<T> unionSchema<T>(List<Schema<T>> schemas, {String? name, String? code, String? message}) {
  final branches = List<Schema<T>>.unmodifiable(schemas);
  final label = normalizeSchemaName(name);

  return Schema.internal(
    (input, context, path) {
      for (final schema in branches) {
        switch (schema.evaluate(input, context, path)) {
          case Success(:final value):
            return Success(value);
          case Failure():
            continue;
        }
      }

      return invalid(
        IssueTemplate(
          code ?? 'INVALID_UNION',
          (name) =>
              message ?? '${name == null ? 'Must' : '$name must'} match one of the allowed schemas',
        ).at(path, label),
      );
    },
    name: label,
  );
}

/// Internal discriminator selection; validates only the selected branch.
Schema<Map<String, Object?>> discriminatedSchema({
  required String discriminatorKey,
  required Map<String, Schema<Map<String, Object?>?>> schemas,
  String? name,
  String? code,
  String? message,
}) {
  final branches = Map<String, Schema<Map<String, Object?>?>>.unmodifiable(schemas);
  final label = normalizeSchemaName(name);

  return Schema.internal((input, context, path) {
    if (input is! Map || input.keys.any((key) => key is! String)) {
      return invalid(
        invalidTypeIssue(
          input: input,
          expected: 'an object with string keys',
          path: path,
          name: label,
        ),
      );
    }

    final branch = branches[input[discriminatorKey]];

    if (branch == null) {
      return invalid(
        IssueTemplate(
          code ?? 'INVALID_DISCRIMINATOR',
          (name) =>
              message ??
              '${name == null ? 'Must' : '$name must'} contain a recognized discriminator',
        ).at([...path, FieldSegment(discriminatorKey)], label),
      );
    }

    return switch (branch.evaluate(input, context, path)) {
      Success(:final value) => Success(value!),
      Failure(:final error) => Failure(error),
    };
  }, name: label);
}

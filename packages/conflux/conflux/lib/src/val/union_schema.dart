import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/membership_schema.dart';
import 'package:conflux/src/val/object_schema.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal ordered alternatives; failures are summarized only after all fail.
Schema<T> unionSchema<T>(List<Schema<T>> schemas, {String? name, String? code, String? message}) {
  if (schemas.isEmpty) throw ArgumentError.value(schemas, 'schemas', 'Must not be empty');
  final branches = List<Schema<T>>.unmodifiable(schemas);
  final label = name == null || name.trim().isEmpty ? null : name.trim();
  return Schema.internal((input, context, path) {
    for (final schema in branches) {
      switch (schema.evaluate(input, context, path).finish()) {
        case Success(:final value):
          return Evaluation.valid(value);
        case Failure():
          continue;
      }
    }
    return Evaluation.invalid(
      IssueTemplate(
        'INVALID_UNION',
        IssueKind.invalidUnion,
        'Must match one of the allowed schemas',
        customCode: code,
        customMessage: message,
      ).at(path, label),
    );
  }, name: label);
}

/// Internal discriminator selection; validates only the selected object branch.
Schema<Map<String, Object?>> discriminatedSchema({
  required String discriminatorKey,
  required Map<String, ObjectSchema<Map<String, Object?>?>> schemas,
  String? name,
  String? code,
  String? message,
}) {
  if (schemas.isEmpty) throw ArgumentError.value(schemas, 'schemas', 'Must not be empty');
  for (final entry in schemas.entries) {
    final branch = entry.value;
    final field = branch.fields[discriminatorKey];
    if (branch.isOptional ||
        branch.isNullable ||
        field is! LiteralSchema ||
        field.isOptional ||
        field.isNullable ||
        field.expected is! String ||
        field.expected != entry.key) {
      throw ArgumentError(
        'Each branch must declare its registration key as a required non-nullable string literal',
      );
    }
  }
  final branches = Map<String, ObjectSchema<Map<String, Object?>?>>.unmodifiable(schemas);
  final label = name == null || name.trim().isEmpty ? null : name.trim();
  return Schema.internal((input, context, path) {
    if (input is! Map || input.keys.any((key) => key is! String)) {
      return Evaluation.invalid(
        IssueTemplate(
          input == null ? 'NOT_NULL' : 'INVALID_TYPE',
          IssueKind.invalidType,
          input == null ? 'Must not be null' : 'Must be an object with string keys',
        ).at(path, label),
      );
    }
    final discriminator = input[discriminatorKey];
    final branch = discriminator is String ? branches[discriminator] : null;
    if (branch == null) {
      return Evaluation.invalid(
        IssueTemplate(
          'INVALID_DISCRIMINATOR',
          IssueKind.invalidDiscriminator,
          'Must contain a recognized discriminator',
          customCode: code,
          customMessage: message,
        ).at([...path, Field(discriminatorKey)], label),
      );
    }
    switch (branch.evaluate(input, context, path).finish()) {
      case Success(:final value):
        if (value != null) return Evaluation.valid(value);
        throw StateError('Non-nullable discriminator branch returned null');
      case Failure(:final error):
        return Evaluation(const None(), error);
    }
  }, name: label);
}

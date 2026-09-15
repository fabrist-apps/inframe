import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

/// Internal unknown-key behavior.
enum UnknownKeys {
  /// Reject every extra key.
  strict,

  /// Omit extra keys.
  strip,

  /// Borrow extra values.
  passthrough,
}

/// Internal immutable shape and root-error configuration.
final class ObjectShape {
  /// Copies field configuration.
  ObjectShape(
    Map<String, Schema<Object?>> fields, {
    this.name,
    this.code,
    this.message,
    this.policy = UnknownKeys.strict,
    this.strictCode,
    this.strictMessage,
  }) : fields = Map.unmodifiable(fields);

  /// Declared field schemas.
  final Map<String, Schema<Object?>> fields;

  /// Local root label.
  final String? name;

  /// Root type code override.
  final String? code;

  /// Root type message override.
  final String? message;

  /// Handling of undeclared keys.
  final UnknownKeys policy;

  /// Extra-key code override.
  final String? strictCode;

  /// Extra-key message override.
  final String? strictMessage;

  /// Replaces the policy and its overrides without changing fields.
  ObjectShape withPolicy(UnknownKeys policy, {String? code, String? message}) => ObjectShape(
    fields,
    name: name,
    code: this.code,
    message: this.message,
    policy: policy,
    strictCode: code,
    strictMessage: message,
  );

  /// Validates a complete shape before object-level stages run.
  Schema<Map<String, Object?>> schema() {
    final root = typeSchema<Map<String, Object?>>(
      type: 'an object with string keys',
      name: name,
      code: code,
      message: message,
    );
    return Schema.internal((input, context, path) {
      // Validate keys, not the map's declared generic arguments.
      if (input is! Map || input.keys.any((key) => key is! String)) {
        return Evaluation.invalid(
          IssueTemplate(
            input == null ? 'NOT_NULL' : 'INVALID_TYPE',
            IssueKind.invalidType,
            input == null ? 'Must not be null' : 'Must be an object with string keys',
            customCode: code,
            customMessage: message,
          ).at(path, root.name),
        );
      }
      final output = <String, Object?>{};
      final issues = <ValidationIssue>[];
      for (final entry in fields.entries) {
        // Conditional inference otherwise chooses Object for Some and None.
        // ignore: omit_local_variable_types
        final Option<Object?> present = input.containsKey(entry.key)
            ? Some(input[entry.key])
            : const None();
        final parsed = entry.value.field(present, context, [...path, Field(entry.key)]);
        if (parsed == null) continue;
        switch (parsed.finish()) {
          case Success(:final value):
            output[entry.key] = value;
          case Failure(:final error):
            issues.addAll(error);
        }
      }
      for (final key in input.keys) {
        if (key is! String || fields.containsKey(key)) continue;
        if (policy == UnknownKeys.strict) {
          issues.add(
            IssueTemplate(
              'UNRECOGNIZED_KEY',
              IssueKind.unrecognizedKey,
              'Property is not allowed',
              customCode: strictCode,
              customMessage: strictMessage,
            ).at([...path, Field(key)], root.name),
          );
        } else if (policy == UnknownKeys.passthrough) {
          output[key] = input[key];
        }
      }
      if (issues.isNotEmpty) return Evaluation(const None(), issues);
      return Evaluation.valid(Map<String, Object?>.unmodifiable(output));
    }, name: name);
  }
}

/// An immutable object schema. [T] tracks whether the object itself allows null.
///
/// Compose the shape before adding object-level refinements. Child refinements
/// remain attached to their fields through all shape operations.
final class ObjectSchema<T extends Map<String, Object?>?> extends Schema<T> {
  /// Internal construction: replay immutable derivations over a new shape when
  /// its policy changes, preserving nullable/refinement stage order.
  ObjectSchema.internal(
    ObjectShape shape,
    Schema<T> Function(ObjectShape) build, {
    bool hasRefinements = false,
  }) : this._(shape, build, build(shape), hasRefinements);
  ObjectSchema._(this.shape, this.build, Schema<T> schema, this.hasRefinements)
    : super.internal(
        schema.evaluate,
        name: schema.name,
        isOptional: schema.isOptional,
        missingCode: schema.missingCode,
        missingMessage: schema.missingMessage,
        isNullable: schema.isNullable,
      );

  /// Internal shape configuration.
  final ObjectShape shape;

  /// Internal recipe preserving the typed derivation order.
  final Schema<T> Function(ObjectShape shape) build;

  /// Whether shape changes would invalidate a caller predicate.
  final bool hasRefinements;

  /// Declared fields in their validation order.
  Map<String, Schema<Object?>> get fields => shape.fields;

  /// Internal construction for the public factory.
  static ObjectSchema<Map<String, Object?>> create(
    Map<String, Schema<Object?>> fields, {
    String? name,
    String? code,
    String? message,
  }) => ObjectSchema.internal(
    ObjectShape(fields, name: name, code: code, message: message),
    (shape) => shape.schema(),
  );

  @override
  ObjectSchema<T> optional() => ObjectSchema<T>.internal(
    shape,
    (shape) => build(shape).optional(),
    hasRefinements: hasRefinements,
  );
  @override
  ObjectSchema<T> required({String? code, String? message}) => ObjectSchema<T>.internal(
    shape,
    (shape) => build(shape).required(code: code, message: message),
    hasRefinements: hasRefinements,
  );
  @override
  ObjectSchema<T?> nullable() => ObjectSchema<T?>.internal(
    shape,
    (shape) => build(shape).nullable(),
    hasRefinements: hasRefinements,
  );

  /// Rejects unknown keys, with independent error overrides.
  ObjectSchema<T> strict({String? code, String? message}) => ObjectSchema<T>.internal(
    shape.withPolicy(UnknownKeys.strict, code: code, message: message),
    build,
    hasRefinements: hasRefinements,
  );

  /// Removes unknown keys before output and object refinements.
  ObjectSchema<T> strip() => ObjectSchema<T>.internal(
    shape.withPolicy(UnknownKeys.strip),
    build,
    hasRefinements: hasRefinements,
  );

  /// Preserves unknown values as borrowed references.
  ObjectSchema<T> passthrough() => ObjectSchema<T>.internal(
    shape.withPolicy(UnknownKeys.passthrough),
    build,
    hasRefinements: hasRefinements,
  );
}

/// Object refinements retain shape and policy methods.
extension ObjectRefinement<T extends Map<String, Object?>?> on ObjectSchema<T> {
  /// Checks a complete parsed object; shape changes must precede refinements.
  ObjectSchema<T> refine(
    bool Function(T value) predicate, {
    List<PathSegment> path = const [],
    String? code,
    String? message,
  }) {
    final copiedPath = List<PathSegment>.unmodifiable(path);
    return ObjectSchema<T>.internal(
      shape,
      (shape) => build(shape).refine(predicate, path: copiedPath, code: code, message: message),
      hasRefinements: true,
    );
  }
}

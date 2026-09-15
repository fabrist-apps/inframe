import 'package:conflux/result.dart';
import 'package:conflux/src/val/issue.dart';
import 'package:conflux/src/val/schema.dart';

enum _UnknownKeys { strict, strip, passthrough }

final class _ObjectShape {
  _ObjectShape(
    Map<String, Schema<Object?>> fields, {
    String? name,
    this.code,
    this.message,
    this.unknownKeys = _UnknownKeys.strict,
    this.unknownKeyCode,
    this.unknownKeyMessage,
  }) : fields = Map.unmodifiable(fields),
       name = normalizeSchemaName(name);

  final Map<String, Schema<Object?>> fields;
  final String? name;
  final String? code;
  final String? message;
  final _UnknownKeys unknownKeys;
  final String? unknownKeyCode;
  final String? unknownKeyMessage;

  _ObjectShape withFields(Map<String, Schema<Object?>> fields) => _ObjectShape(
    fields,
    name: name,
    code: code,
    message: message,
    unknownKeys: unknownKeys,
    unknownKeyCode: unknownKeyCode,
    unknownKeyMessage: unknownKeyMessage,
  );

  _ObjectShape withUnknownKeys(_UnknownKeys unknownKeys, {String? code, String? message}) =>
      _ObjectShape(
        fields,
        name: name,
        code: this.code,
        message: this.message,
        unknownKeys: unknownKeys,
        unknownKeyCode: code,
        unknownKeyMessage: message,
      );
}

/// An immutable object shape builder.
///
/// Shape and unknown-key operations are available until a general schema
/// operation such as `nullable`, `optional`, or `refine` is applied.
final class ObjectSchema extends Schema<Map<String, Object?>> {
  ObjectSchema._(_ObjectShape shape)
    : _shape = shape,
      super.internal(_parseObject(shape), name: shape.name);

  /// Creates an object schema with strict unknown-key handling.
  factory ObjectSchema.create(
    Map<String, Schema<Object?>> fields, {
    String? name,
    String? code,
    String? message,
  }) => ObjectSchema._(_ObjectShape(fields, name: name, code: code, message: message));

  final _ObjectShape _shape;

  /// Declared fields in validation order.
  Map<String, Schema<Object?>> get fields => _shape.fields;

  /// Replaces matching fields in place and appends new fields in incoming order.
  ObjectSchema extend(Map<String, Schema<Object?>> fields) =>
      ObjectSchema._(_shape.withFields({...this.fields, ...fields}));

  /// Combines fields and adopts the right object's unknown-key policy.
  ObjectSchema merge(ObjectSchema other) => ObjectSchema._(
    _ObjectShape(
      {...fields, ...other.fields},
      name: _shape.name,
      code: _shape.code,
      message: _shape.message,
      unknownKeys: other._shape.unknownKeys,
      unknownKeyCode: other._shape.unknownKeyCode,
      unknownKeyMessage: other._shape.unknownKeyMessage,
    ),
  );

  /// Keeps requested fields in their original schema order.
  ObjectSchema pick(List<String> keys) {
    final selected = keys.toSet();

    return ObjectSchema._(
      _shape.withFields(
        {
          for (final entry in fields.entries)
            if (selected.contains(entry.key)) entry.key: entry.value,
        },
      ),
    );
  }

  /// Removes requested fields while retaining the order of remaining fields.
  ObjectSchema omit(List<String> keys) {
    final selected = keys.toSet();

    return ObjectSchema._(
      _shape.withFields(
        {
          for (final entry in fields.entries)
            if (!selected.contains(entry.key)) entry.key: entry.value,
        },
      ),
    );
  }

  /// Makes immediate fields optional, without adding nullability or recursing.
  ObjectSchema partial() => ObjectSchema._(
    _shape.withFields(
      {
        for (final entry in fields.entries) entry.key: entry.value.optional(),
      },
    ),
  );

  /// Rejects unknown keys, with independent error overrides.
  ObjectSchema strict({String? code, String? message}) => ObjectSchema._(
    _shape.withUnknownKeys(_UnknownKeys.strict, code: code, message: message),
  );

  /// Removes unknown keys from the parsed output.
  ObjectSchema strip() => ObjectSchema._(_shape.withUnknownKeys(_UnknownKeys.strip));

  /// Preserves unknown values as borrowed references.
  ObjectSchema passthrough() => ObjectSchema._(_shape.withUnknownKeys(_UnknownKeys.passthrough));
}

ParseValue<Map<String, Object?>> _parseObject(_ObjectShape shape) => (input, context, path) {
  if (input is! Map || input.keys.any((key) => key is! String)) {
    return invalid(
      invalidTypeIssue(
        input: input,
        expected: 'an object with string keys',
        path: path,
        name: shape.name,
        code: shape.code,
        message: shape.message,
      ),
    );
  }

  final output = <String, Object?>{};
  final issues = <ValidationIssue>[];

  for (final entry in shape.fields.entries) {
    final parsed = entry.value.field(
      isPresent: input.containsKey(entry.key),
      input: input[entry.key],
      context: context,
      path: [...path, FieldSegment(entry.key)],
    );

    switch (parsed) {
      case null:
        continue;
      case Success(:final value):
        output[entry.key] = value;
      case Failure(:final error):
        issues.addAll(error);
    }
  }

  for (final key in input.keys.cast<String>()) {
    if (shape.fields.containsKey(key)) {
      continue;
    }

    switch (shape.unknownKeys) {
      case _UnknownKeys.strict:
        issues.add(
          IssueTemplate(
            shape.unknownKeyCode ?? 'UNRECOGNIZED_KEY',
            (name) =>
                shape.unknownKeyMessage ??
                (name == null ? 'Property is not allowed' : 'Property is not allowed in $name'),
          ).at([...path, FieldSegment(key)], shape.name),
        );
      case _UnknownKeys.strip:
        break;
      case _UnknownKeys.passthrough:
        output[key] = input[key];
    }
  }

  return issues.isEmpty ? Success(Map<String, Object?>.unmodifiable(output)) : invalidAll(issues);
};

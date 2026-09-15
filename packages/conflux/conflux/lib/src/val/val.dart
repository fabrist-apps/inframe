import 'package:conflux/src/val/object_schema.dart';
import 'package:conflux/src/val/schema.dart';
import 'package:conflux/src/val/string_schema.dart';

/// Factories for immutable synchronous validation schemas.
abstract final class Val {
  /// Validates declared fields and rejects unknown keys by default.
  static ObjectSchema<Map<String, Object?>> object(
    Map<String, Schema<Object?>> fields, {
    String? name,
    String? code,
    String? message,
  }) => ObjectSchema.create(fields, name: name, code: code, message: message);

  /// Accepts a Dart string without coercion or normalization.
  static StringSchema string({String? name, String? code, String? message}) =>
      typeSchema(type: 'a string', name: name, code: code, message: message);
}

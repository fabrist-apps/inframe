import 'dart:core';
import 'dart:core' as core;

import 'package:conflux/src/val/membership_schema.dart';
import 'package:conflux/src/val/numeric_schema.dart';
import 'package:conflux/src/val/object_schema.dart';
import 'package:conflux/src/val/schema.dart';
import 'package:conflux/src/val/string_schema.dart';

/// Factories for immutable synchronous validation schemas.
abstract final class Val {
  /// Accepts a finite Dart double without conversion.
  static Schema<core.double> double({String? name, String? code, String? message}) =>
      numericSchema(type: 'a double', name: name, code: code, message: message);

  /// Accepts a finite Dart number, retaining its numeric type.
  static Schema<num> number({String? name, String? code, String? message}) =>
      numericSchema(type: 'a number', name: name, code: code, message: message);

  /// Accepts a Dart boolean without conversion.
  static Schema<bool> boolean({String? name, String? code, String? message}) =>
      typeSchema(type: 'a boolean', name: name, code: code, message: message);

  /// Accepts the configured primitive value with its exact declared type.
  static LiteralSchema<T> literal<T extends Object>(
    T expected, {
    String? name,
    String? code,
    String? message,
  }) => LiteralSchema(expected, name: name, code: code, message: message);

  /// Accepts one of the configured case-sensitive strings.
  static Schema<String> enumString(
    List<String> values, {
    String? name,
    String? code,
    String? message,
  }) => enumSchema(values, name: name, code: code, message: message);

  /// Accepts supplied enum instances; strings are not converted.
  static Schema<T> enumValues<T extends Enum>(
    List<T> values, {
    String? name,
    String? code,
    String? message,
  }) => enumSchema(values, name: name, code: code, message: message);

  /// Accepts and borrows any instance of T.
  static Schema<T> instance<T extends Object>({String? name, String? code, String? message}) =>
      typeSchema(type: 'an instance of $T', name: name, code: code, message: message);

  /// Accepts a Dart integer without numeric conversion.
  static Schema<core.int> int({String? name, String? code, String? message}) =>
      numericSchema(type: 'an integer', name: name, code: code, message: message);

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

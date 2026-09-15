import 'dart:core';
import 'dart:core' as core;

import 'package:conflux/src/val/collection_schema.dart';
import 'package:conflux/src/val/membership_schema.dart';
import 'package:conflux/src/val/numeric_schema.dart';
import 'package:conflux/src/val/object_schema.dart';
import 'package:conflux/src/val/recursive_schema.dart';
import 'package:conflux/src/val/schema.dart';
import 'package:conflux/src/val/string_schema.dart';
import 'package:conflux/src/val/union_schema.dart';

/// Factories for immutable synchronous validation schemas.
abstract final class Val {
  /// Validates and copies non-null JSON-compatible values, allowing nested null.
  static Schema<Object> any({
    core.int maxDepth = 64,
    String? name,
    String? code,
    String? message,
  }) => JsonSchema(maxDepth: maxDepth, name: name, code: code, message: message).schema();

  /// Defers schema resolution until parsing and bounds active recursive entries.
  static Schema<T> lazy<T>(
    Schema<T> Function() build, {
    core.int maxDepth = 64,
    String? name,
    String? code,
    String? message,
  }) => LazyResolver(build, maxDepth: maxDepth, name: name, code: code, message: message).schema();

  /// Selects a direct object branch through a required string literal field.
  static Schema<Map<String, Object?>> discriminated({
    required String discriminatorKey,
    required Map<String, ObjectSchema<Map<String, Object?>?>> schemas,
    String? name,
    String? code,
    String? message,
  }) => discriminatedSchema(
    discriminatorKey: discriminatorKey,
    schemas: schemas,
    name: name,
    code: code,
    message: message,
  );

  /// Selects the first successful schema in declaration order.
  static Schema<T> anyOf<T>(
    List<Schema<T>> schemas, {
    String? name,
    String? code,
    String? message,
  }) => unionSchema(schemas, name: name, code: code, message: message);

  /// Validates arbitrary string keys against one value schema.
  static Schema<Map<String, T>> map<T>(
    Schema<T> values, {
    String? name,
    String? code,
    String? message,
  }) => mapSchema(values, name: name, code: code, message: message);

  /// Validates each list item and returns an immutable typed list.
  static Schema<List<T>> list<T>(Schema<T> items, {String? name, String? code, String? message}) =>
      listSchema(items, name: name, code: code, message: message);

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

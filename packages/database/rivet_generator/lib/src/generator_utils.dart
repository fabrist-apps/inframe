import 'package:analyzer/dart/element/type.dart';
// Generator helpers are shared only inside rivet_generator.
// ignore_for_file: public_member_api_docs

import 'package:source_gen/source_gen.dart';

String readString(ConstantReader annotation, String field, String fallback) =>
    annotation.peek(field)?.stringValue ?? fallback;

String? readNullableString(ConstantReader annotation, String field) {
  final value = annotation.peek(field);
  return value == null || value.isNull ? null : value.stringValue;
}

String lowerCamel(String value) => value[0].toLowerCase() + value.substring(1);

String literal(String value) => "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

String columnValueType(DartType type) {
  if (type is! InterfaceType || type.typeArguments.isEmpty) {
    throw InvalidGenerationSourceError('Rivet columns must retain their value type.');
  }
  return type.typeArguments.first.getDisplayString();
}

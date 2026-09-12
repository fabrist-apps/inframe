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

String literal(String value) {
  final result = StringBuffer("'");
  for (final rune in value.runes) {
    result.write(
      switch (rune) {
        0x08 => r'\b',
        0x09 => r'\t',
        0x0A => r'\n',
        0x0C => r'\f',
        0x0D => r'\r',
        0x24 => r'\$',
        0x27 => r"\'",
        0x5C => r'\\',
        < 0x20 || 0x7F || 0x2028 || 0x2029 => '\\u${rune.toRadixString(16).padLeft(4, '0')}',
        _ => String.fromCharCode(rune),
      },
    );
  }
  return "$result'";
}

String columnValueType(DartType type) {
  if (type is! InterfaceType || type.typeArguments.isEmpty) {
    throw InvalidGenerationSourceError('Rivet columns must retain their value type.');
  }
  return type.typeArguments.first.getDisplayString();
}

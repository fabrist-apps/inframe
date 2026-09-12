// Generator helpers are shared only inside rivet_generator.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
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

String columnValueType(DartType type, LibraryElement library) {
  if (type is! InterfaceType || type.typeArguments.isEmpty) {
    throw InvalidGenerationSourceError('Rivet columns must retain their value type.');
  }
  return referenceToType(type.typeArguments.first, library);
}

String referenceToType(DartType type, LibraryElement from) {
  if (type is! InterfaceType) return type.getDisplayString();
  final arguments = type.typeArguments.isEmpty
      ? ''
      : '<${type.typeArguments.map((argument) => referenceToType(argument, from)).join(', ')}>';
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
  return '${referenceTo(type.element, from)}$arguments$nullable';
}

String referenceTo(Element target, LibraryElement from) {
  final name = target.displayName;
  if (target.library == from) return name;
  for (final fragment in from.fragments) {
    for (final import in fragment.libraryImports) {
      final prefix = import.prefix?.element;
      final imported = prefix == null
          ? import.namespace.get2(name)
          : prefix.scope.lookup(name).getter;
      if (imported?.baseElement != target.baseElement &&
          (imported?.library?.uri != target.library?.uri || imported?.displayName != name)) {
        continue;
      }
      return prefix == null ? name : '${prefix.displayName}.$name';
    }
  }
  throw InvalidGenerationSourceError(
    '`${target.library?.uri}::$name` is not accessible from `${from.uri}`.',
    element: target,
  );
}

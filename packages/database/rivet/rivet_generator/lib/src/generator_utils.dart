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
  if (type.alias case final alias?) {
    return '${referenceTo(alias.element, from)}${_typeArguments(alias.typeArguments, from)}'
        '${_nullability(alias.nullabilitySuffix)}';
  }
  return switch (type) {
    final InterfaceType interface =>
      '${referenceTo(interface.element, from)}'
          '${_typeArguments(interface.typeArguments, from)}'
          '${_nullability(interface.nullabilitySuffix)}',
    final RecordType record => _recordType(record, from),
    final FunctionType function => _functionType(function, from),
    _ => type.getDisplayString(),
  };
}

String _typeArguments(List<DartType> arguments, LibraryElement from) => arguments.isEmpty
    ? ''
    : '<${arguments.map((argument) => referenceToType(argument, from)).join(', ')}>';

String _recordType(RecordType type, LibraryElement from) {
  final fields = <String>[
    for (final field in type.positionalFields) referenceToType(field.type, from),
  ];
  if (type.positionalFields.length == 1 && type.namedFields.isEmpty) {
    fields[0] = '${fields[0]},';
  }
  if (type.namedFields.isNotEmpty) {
    fields.add(
      '{${type.namedFields.map((field) => '${referenceToType(field.type, from)} ${field.name}').join(', ')}}',
    );
  }
  return '(${fields.join(', ')})${_nullability(type.nullabilitySuffix)}';
}

String _functionType(FunctionType type, LibraryElement from) {
  final required = <String>[];
  final optional = <String>[];
  final named = <String>[];
  for (final parameter in type.formalParameters) {
    final rendered = referenceToType(parameter.type, from);
    if (parameter.isOptionalPositional) {
      optional.add(rendered);
    } else if (parameter.isNamed) {
      named.add('${parameter.isRequiredNamed ? 'required ' : ''}$rendered ${parameter.name}');
    } else {
      required.add(rendered);
    }
  }
  final parameters = <String>[
    ...required,
    if (optional.isNotEmpty) '[${optional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ].join(', ');
  final typeParameters = type.typeParameters.isEmpty
      ? ''
      : '<${type.typeParameters.map((parameter) {
          final bound = parameter.bound;
          return bound == null ? parameter.displayName : '${parameter.displayName} extends ${referenceToType(bound, from)}';
        }).join(', ')}>';
  return '${referenceToType(type.returnType, from)} Function$typeParameters($parameters)'
      '${_nullability(type.nullabilitySuffix)}';
}

String _nullability(NullabilitySuffix suffix) => suffix == NullabilitySuffix.question ? '?' : '';

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

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:rivet/rivet.dart';
import 'package:source_gen/source_gen.dart';

import 'generator_utils.dart';

final class RivetTableGenerator extends GeneratorForAnnotation<RivetTable> {
  const RivetTableGenerator() : super(inPackage: 'rivet');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@RivetTable can only annotate a class.',
        element: element,
      );
    }
    final className = element.displayName;
    final rowName = readString(annotation, 'rowName', '${className}Row');
    if (rowName == className || !RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(rowName)) {
      throw InvalidGenerationSourceError(
        'rowName `$rowName` is invalid or collides with `$className`.',
        element: element,
      );
    }
    final schemaName = readString(annotation, 'schema', 'public');
    final tableName = readString(annotation, 'name', lowerCamel(className));
    final columns = element.fields
        .where(
          (field) =>
              !field.isStatic &&
              field.type.getDisplayString().contains('Rivet') &&
              field.type.getDisplayString().contains('Column'),
        )
        .toList(growable: false);
    if (columns.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Rivet table must declare at least one column.',
        element: element,
      );
    }

    final fields = columns
        .map((field) => '  final ${columnValueType(field.type)} ${field.displayName};')
        .join('\n');
    final parameters = columns.map((field) => '    required this.${field.displayName},').join('\n');
    final descriptorList = columns
        .map((field) => 'definition.${field.displayName} as RivetColumn<Object?>')
        .join(', ');
    final names = columns.map((field) => literal(field.displayName)).join(', ');
    final decodes = columns.indexed
        .map((entry) {
          final index = entry.$1;
          final field = entry.$2;
          return '${field.displayName}: definition.${field.displayName}.decodeValue(values[$index], isSqlNull: sqlNulls[$index])';
        })
        .join(', ');

    return '''
final class $rowName {
  const $rowName({
$parameters
  });

$fields
}

final class _\$${className}DB extends RivetTableAccessor<$className, $rowName> {
  const _\$${className}DB();

  @override
  RivetTableSchema<$className, $rowName> buildSchema() {
    final definition = $className();
    return RivetTableSchema<$className, $rowName>(
      schemaName: ${literal(schemaName)},
      tableName: ${literal(tableName)},
      definition: definition,
      columns: [$descriptorList],
      columnNames: [$names],
      decode: (values, sqlNulls) => $rowName($decodes),
    );
  }
}
''';
  }
}

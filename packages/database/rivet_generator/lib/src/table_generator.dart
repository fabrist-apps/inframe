import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
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
    final relations = element.fields
        .where(
          (field) =>
              !field.isStatic &&
              field.type.getDisplayString().contains('Rivet') &&
              field.type.getDisplayString().contains('Relation<'),
        )
        .toList(growable: false);
    if (columns.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Rivet table must declare at least one column.',
        element: element,
      );
    }

    final fields = [
      ...columns.map((field) => '  final ${columnValueType(field.type)} ${field.displayName};'),
      ...relations.map((field) => '  final ${_relationValueType(field)} ${field.displayName};'),
    ].join('\n');
    final parameters = [
      ...columns.map((field) => '    required this.${field.displayName},'),
      ...relations.map((field) => '    this.${field.displayName} = const Relation.unloaded(),'),
    ].join('\n');
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
    final indexes = element.fields.any((field) => field.displayName == '_indexes')
        ? 'definition._indexes'
        : 'const <RivetIndex>[]';
    final constraints = element.fields.any((field) => field.displayName == '_constraints')
        ? 'definition._constraints'
        : 'const <RivetConstraint>[]';
    final relationMap = relations
        .map(
          (field) =>
              '${literal(field.displayName)}: definition.${field.displayName} as RivetRelationDescriptor<Object?>',
        )
        .join(', ');
    final enumCodecs = columns
        .where(_isEnumColumn)
        .map((field) {
          final enumName = columnValueType(field.type);
          return 'definition.${field.displayName}.useCodec(${enumName}RivetEnum.codec);';
        })
        .join('\n    ');

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
    $enumCodecs
    return RivetTableSchema<$className, $rowName>(
      schemaName: ${literal(schemaName)},
      tableName: ${literal(tableName)},
      definition: definition,
      columns: [$descriptorList],
      columnNames: [$names],
      decode: (values, sqlNulls) => $rowName($decodes),
      indexes: $indexes,
      constraints: $constraints,
      relations: {$relationMap},
    );
  }

}
''';
  }

  bool _isEnumColumn(FieldElement field) {
    final type = field.type;
    if (type is! InterfaceType || type.typeArguments.isEmpty) return false;
    final valueType = type.typeArguments.first;
    final element = valueType.element;
    return element != null &&
        const TypeChecker.typeNamed(RivetEnum, inPackage: 'rivet').hasAnnotationOf(element);
  }

  String _relationValueType(FieldElement field) {
    final type = field.type;
    if (type is! InterfaceType || type.typeArguments.isEmpty) {
      throw InvalidGenerationSourceError(
        'A relation must retain its target type.',
        element: field,
      );
    }
    final target = type.typeArguments.first;
    final targetElement = target.element;
    var targetRow = '${target.getDisplayString()}Row';
    if (targetElement != null) {
      final value = const TypeChecker.typeNamed(
        RivetTable,
        inPackage: 'rivet',
      ).firstAnnotationOf(targetElement);
      if (value != null) {
        targetRow = readString(ConstantReader(value), 'rowName', targetRow);
      }
    }
    return type.element.displayName == 'RivetOneRelation'
        ? 'Relation<$targetRow?>'
        : 'Relation<List<$targetRow>>';
  }
}

// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:rivet/rivet.dart';
import 'package:rivet_generator/src/generator_utils.dart';
import 'package:source_gen/source_gen.dart';

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
    if (rowName == className ||
        element.library.getClass(rowName) != null ||
        !RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(rowName)) {
      throw InvalidGenerationSourceError(
        'rowName `$rowName` is invalid or collides with `$className`.',
        element: element,
      );
    }
    final schemaName = readString(annotation, 'schema', 'public');
    final tableName = readString(annotation, 'name', lowerCamel(className));
    final renamedFrom = readNullableString(annotation, 'renamedFrom');
    final renameMetadata = renamedFrom == null
        ? ''
        : '      renamedFrom: ${literal(renamedFrom)},\n';
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
      ...columns.map(
        (field) =>
            '  /// Value read from `${field.displayName}`.\n'
            '  final ${columnValueType(field.type)} ${field.displayName};',
      ),
      ...relations.map(
        (field) =>
            '  /// Loaded or unloaded `${field.displayName}` relation.\n'
            '  final ${_relationValueType(field)} ${field.displayName};',
      ),
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
        ? '      indexes: () => definition._indexes,\n'
        : '';
    final constraints = element.fields.any((field) => field.displayName == '_constraints')
        ? '      constraints: () => definition._constraints,\n'
        : '';
    final relationMap = relations
        .map(
          (field) =>
              '${literal(field.displayName)}: definition.${field.displayName} as RivetRelationDescriptor<Object?>',
        )
        .join(', ');
    final enumCodecs = columns
        .map((field) => (field, _enumType(field)))
        .where((entry) => entry.$2 != null)
        .map((entry) {
          final field = entry.$1;
          final enumType = entry.$2!;
          final parts = enumType.split('.');
          parts[parts.length - 1] = '${parts.last}RivetEnum';
          return 'definition.${field.displayName}.configureEnum(${parts.join('.')}.codec);';
        })
        .join('\n    ');

    return '''
/// Generated row returned by reads from ${literal('$schemaName.$tableName')}.
final class $rowName {
  /// Creates a row from decoded column and relation values.
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
$renameMetadata      definition: definition,
      columns: [$descriptorList],
      columnNames: [$names],
      decode: (values, sqlNulls) => $rowName($decodes),
$indexes$constraints${relations.isEmpty ? '' : '      relations: {$relationMap},\n'}
    );
  }

}
''';
  }

  String? _enumType(FieldElement field) {
    final library = field.library;
    final parsed = library.session.getParsedLibraryByElement(library);
    if (parsed is ParsedLibraryResult) {
      final declaration = parsed.getFragmentDeclaration(field.firstFragment)?.node;
      if (declaration != null) {
        final visitor = _EnumTextVisitor();
        declaration.accept(visitor);
        if (visitor.enumType case final enumType?) return enumType;
      }
    }
    return _enumTypeFromColumn(field.type);
  }

  String? _enumTypeFromColumn(DartType type) {
    if (type is! InterfaceType) return null;
    for (final argument in type.typeArguments) {
      if (argument.element case final element?
          when const TypeChecker.typeNamed(
            RivetEnum,
            inPackage: 'rivet',
          ).hasAnnotationOf(element)) {
        return argument.getDisplayString().replaceAll('?', '');
      }
      if (_enumTypeFromColumn(argument) case final nested?) return nested;
    }
    return null;
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

final class _EnumTextVisitor extends RecursiveAstVisitor<void> {
  String? enumType;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (enumType == null && node.methodName.name == 'enumText') {
      final arguments = node.typeArguments?.arguments;
      if (arguments != null && arguments.length == 1) {
        enumType = arguments.single.toSource();
      }
    }
    super.visitMethodInvocation(node);
  }
}

// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_generator/src/generator_utils.dart';

final class VoxelDatabaseGenerator extends GeneratorForAnnotation<VoxelDatabase> {
  const VoxelDatabaseGenerator() : super(inPackage: 'voxel');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@VoxelDatabase can only annotate a class.',
        element: element,
      );
    }
    final databaseName = annotation.read('name').stringValue;
    if (databaseName.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Voxel database name must not be empty.',
        element: element,
      );
    }
    final tableReferences = _tableReferences(element, annotation);
    if (tableReferences.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Voxel database must register at least one table.',
        element: element,
      );
    }
    if (tableReferences.toSet().length != tableReferences.length) {
      throw InvalidGenerationSourceError(
        'A Voxel database cannot register a table twice.',
        element: element,
      );
    }
    final className = element.displayName;
    final descriptors = tableReferences
        .map((table) => '$table.db.buildSchema() as VoxelTableSchema<Object?, Object?>')
        .join(', ');
    return '''
abstract class _\$$className {
  /// Connection-free metadata composed for this application database.
  VoxelDatabaseSchema get schema => VoxelDatabaseSchema(
    name: ${literal(databaseName)},
    tables: [$descriptors],
  );
}
''';
  }

  List<String> _tableReferences(ClassElement element, ConstantReader annotation) {
    final tables = annotation.peek('tables');
    if (tables != null && !tables.isNull) {
      return [
        for (final value in tables.listValue)
          if (value.toTypeValue()?.element case final tableElement?)
            referenceTo(tableElement, element.library)
          else
            throw InvalidGenerationSourceError(
              'Every database table must resolve to a declared type.',
              element: element,
            ),
      ];
    }
    final parsed = element.library.session.getParsedLibraryByElement(element.library);
    if (parsed is! ParsedLibraryResult) return const [];
    final declaration = parsed.getFragmentDeclaration(element.firstFragment)?.node;
    if (declaration is! ClassDeclaration) return const [];
    for (final metadata in declaration.metadata) {
      if (metadata.name.name != 'VoxelDatabase') continue;
      for (final argument in metadata.arguments?.arguments ?? const <Expression>[]) {
        if (argument is! NamedArgument || argument.name.lexeme != 'tables') continue;
        final expression = argument.argumentExpression;
        if (expression is! ListLiteral) {
          throw InvalidGenerationSourceError(
            'Imported Voxel tables must be listed directly in the annotation.',
            element: element,
          );
        }
        return [for (final entry in expression.elements) entry.toSource()];
      }
    }
    return const [];
  }
}

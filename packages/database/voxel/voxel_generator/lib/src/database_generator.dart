// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

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
    final tableTypes = annotation
        .read('tables')
        .listValue
        .map((value) {
          final type = value.toTypeValue();
          if (type == null) {
            throw InvalidGenerationSourceError(
              'Every database table must be a type.',
              element: element,
            );
          }
          return type;
        })
        .toList(growable: false);
    if (tableTypes.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Voxel database must register at least one table.',
        element: element,
      );
    }
    if (tableTypes.toSet().length != tableTypes.length) {
      throw InvalidGenerationSourceError(
        'A Voxel database cannot register a table twice.',
        element: element,
      );
    }
    final tableReferences = [
      for (final table in tableTypes)
        if (table.element case final tableElement?)
          referenceTo(tableElement, element.library)
        else
          throw InvalidGenerationSourceError(
            'Every database table must resolve to a declared type.',
            element: element,
          ),
    ];
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
}

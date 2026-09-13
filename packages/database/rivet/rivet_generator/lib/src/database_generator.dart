// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:rivet/rivet.dart';
import 'package:rivet_generator/src/generator_utils.dart';
import 'package:source_gen/source_gen.dart';

final class RivetDatabaseGenerator extends GeneratorForAnnotation<RivetDatabase> {
  const RivetDatabaseGenerator() : super(inPackage: 'rivet');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@RivetDatabase can only annotate a class.',
        element: element,
      );
    }
    final databaseName = annotation.read('name').stringValue;
    if (databaseName.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Rivet database name must not be empty.',
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
        'A Rivet database must register at least one table.',
        element: element,
      );
    }
    if (tableTypes.toSet().length != tableTypes.length) {
      throw InvalidGenerationSourceError(
        'A Rivet database cannot register a table twice.',
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
        .map((table) => '$table.db.buildSchema() as RivetTableSchema<Object?, Object?>')
        .join(', ');
    return '''
/// Connection-free physical schema metadata for [$className].
abstract final class ${className}RivetSchema {
  /// Builds the composed schema used by offline migration tooling.
  static RivetDatabaseSchema build() => RivetDatabaseSchema(
    name: ${literal(databaseName)},
    tables: [$descriptors],
  );
}

abstract class _\$$className {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) {
    final schema = ${className}RivetSchema.build();
    return RivetDb.open(
      name: schema.name,
      connection: connection,
      pool: pool,
      tables: schema.tables,
    );
  }
}
''';
  }
}

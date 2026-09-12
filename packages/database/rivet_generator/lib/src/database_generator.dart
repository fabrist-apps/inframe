// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:rivet/rivet.dart';
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
    final tables = annotation
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
          return type.getDisplayString();
        })
        .toList(growable: false);
    if (tables.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Rivet database must register at least one table.',
        element: element,
      );
    }
    if (tables.toSet().length != tables.length) {
      throw InvalidGenerationSourceError(
        'A Rivet database cannot register a table twice.',
        element: element,
      );
    }
    final className = element.displayName;
    final descriptors = tables
        .map((table) => '$table.db.buildSchema() as RivetTableSchema<Object?, Object?>')
        .join(', ');
    return '''
abstract class _\$$className {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) => RivetDb.open(
    connection: connection,
    pool: pool,
    tables: [$descriptors],
  );
}
''';
  }
}

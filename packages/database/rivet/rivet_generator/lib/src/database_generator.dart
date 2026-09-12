// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:rivet/rivet.dart';
import 'package:rivet_generator/src/generator_utils.dart';
import 'package:source_gen/source_gen.dart';

final class RivetDatabaseGenerator extends GeneratorForAnnotation<RivetDatabase> {
  const RivetDatabaseGenerator() : super(inPackage: 'rivet');

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
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
    final tableReferences = await _tableReferences(element, tableTypes, buildStep);
    final className = element.displayName;
    final descriptors = tableReferences
        .map((table) => '$table.db.buildSchema() as RivetTableSchema<Object?, Object?>')
        .join(', ');
    return '''
abstract class _\$$className {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) => RivetDb.open(
    name: ${literal(databaseName)},
    connection: connection,
    pool: pool,
    tables: [$descriptors],
  );
}
''';
  }

  Future<List<String>> _tableReferences(
    ClassElement element,
    List<DartType> tableTypes,
    BuildStep buildStep,
  ) async {
    final node = await buildStep.resolver.astNodeFor(element.firstFragment, resolve: true);
    if (node is ClassDeclaration) {
      for (final metadata in node.metadata) {
        if (metadata.name.toSource().split('.').last != 'RivetDatabase') continue;
        final arguments = metadata.arguments?.arguments;
        if (arguments == null) continue;
        for (final argument in arguments.whereType<NamedArgument>()) {
          if (argument.name.lexeme != 'tables') continue;
          final expression = argument.argumentExpression;
          if (expression is ListLiteral && expression.elements.length == tableTypes.length) {
            return [for (final table in expression.elements) table.toSource()];
          }
        }
      }
    }
    return [for (final table in tableTypes) table.getDisplayString()];
  }
}

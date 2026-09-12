// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_generator/src/generator_utils.dart';

final class VoxelEnumGenerator extends GeneratorForAnnotation<VoxelEnum> {
  const VoxelEnumGenerator() : super(inPackage: 'voxel');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! EnumElement) {
      throw InvalidGenerationSourceError('@VoxelEnum can only annotate an enum.', element: element);
    }
    final constants = element.fields.where((field) => field.isEnumConstant).toList();
    final labels = <String>[];
    final renamedLabels = <String, String>{};
    for (final constant in constants) {
      final value = const TypeChecker.typeNamed(
        VoxelEnumValue,
        inPackage: 'voxel',
      ).firstAnnotationOf(constant);
      final valueAnnotation = value == null ? null : ConstantReader(value);
      final label = valueAnnotation == null
          ? constant.displayName
          : readString(valueAnnotation, 'name', constant.displayName);
      labels.add(label);
      final renamedFrom = valueAnnotation == null
          ? null
          : readNullableString(valueAnnotation, 'renamedFrom');
      if (renamedFrom != null) renamedLabels[label] = renamedFrom;
    }
    if (labels.toSet().length != labels.length) {
      throw InvalidGenerationSourceError('Native enum labels must be unique.', element: element);
    }
    if (renamedLabels.values.toSet().length != renamedLabels.length ||
        renamedLabels.entries.any(
          (entry) => labels.contains(entry.value) && entry.key != entry.value,
        )) {
      throw InvalidGenerationSourceError(
        'Native enum rename hints must identify unambiguous previous labels.',
        element: element,
      );
    }
    final name = element.displayName;
    final schemaName = readString(annotation, 'schema', 'main');
    final typeName = readString(annotation, 'name', lowerCamel(name));
    final renamedFrom = readNullableString(annotation, 'renamedFrom');
    final values = constants.map((constant) => '$name.${constant.displayName}').join(', ');
    final encodedLabels = labels.map(literal).join(', ');
    final encodedRenames = renamedLabels.entries
        .map((entry) => '${literal(entry.key)}: ${literal(entry.value)}')
        .join(', ');
    return '''
/// Generated Turso metadata and codec for [$name].
abstract final class ${name}VoxelEnum {
  /// Converts [$name] values to and from their stored labels.
  static const codec = VoxelEnumCodec<$name>(
    schemaName: ${literal(schemaName)},
    typeName: ${literal(typeName)},
    ${renamedFrom == null ? '' : 'renamedFrom: ${literal(renamedFrom)},'}
    values: [$values],
    labels: [$encodedLabels],
    ${renamedLabels.isEmpty ? '' : 'renamedLabels: {$encodedRenames},'}
  );
}
''';
  }
}

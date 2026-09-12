import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:rivet/rivet.dart';
import 'package:source_gen/source_gen.dart';

import 'generator_utils.dart';

final class RivetEnumGenerator extends GeneratorForAnnotation<RivetEnum> {
  const RivetEnumGenerator() : super(inPackage: 'rivet');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! EnumElement) {
      throw InvalidGenerationSourceError('@RivetEnum can only annotate an enum.', element: element);
    }
    final constants = element.fields.where((field) => field.isEnumConstant).toList();
    final labels = <String>[];
    for (final constant in constants) {
      final value = const TypeChecker.typeNamed(
        RivetEnumValue,
        inPackage: 'rivet',
      ).firstAnnotationOf(constant);
      labels.add(
        value == null
            ? constant.displayName
            : readString(ConstantReader(value), 'name', constant.displayName),
      );
    }
    if (labels.toSet().length != labels.length) {
      throw InvalidGenerationSourceError('Native enum labels must be unique.', element: element);
    }
    final name = element.displayName;
    final values = constants.map((constant) => '$name.${constant.displayName}').join(', ');
    final encodedLabels = labels.map(literal).join(', ');
    return '''
abstract final class ${name}RivetEnum {
  static const codec = RivetEnumCodec<$name>(
    values: [$values],
    labels: [$encodedLabels],
  );
}
''';
  }
}

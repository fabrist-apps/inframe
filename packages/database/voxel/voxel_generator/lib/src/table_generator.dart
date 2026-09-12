// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_generator/src/generator_utils.dart';

final class VoxelTableGenerator extends GeneratorForAnnotation<VoxelTable> {
  const VoxelTableGenerator() : super(inPackage: 'voxel');

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@VoxelTable can only annotate a class.',
        element: element,
      );
    }
    final className = element.displayName;
    final rowName = readString(annotation, 'rowName', '${className}Row');
    final companionName = '${className}Companion';
    if (rowName == className ||
        rowName == companionName ||
        element.library.getClass(rowName) != null ||
        !RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(rowName)) {
      throw InvalidGenerationSourceError(
        'rowName `$rowName` is invalid or collides with `$className`.',
        element: element,
      );
    }
    final schemaName = readString(annotation, 'schema', 'main');
    final tableName = readString(annotation, 'name', lowerCamel(className));
    final renamedFrom = readNullableString(annotation, 'renamedFrom');
    final renameMetadata = renamedFrom == null
        ? ''
        : '      renamedFrom: ${literal(renamedFrom)},\n';
    const columnChecker = TypeChecker.typeNamed(VoxelColumn, inPackage: 'voxel');
    const relationChecker = TypeChecker.typeNamed(
      VoxelRelationDescriptor,
      inPackage: 'voxel',
    );
    final columns = element.fields
        .where((field) => !field.isStatic && columnChecker.isAssignableFromType(field.type))
        .toList(growable: false);
    final relations = element.fields
        .where((field) => !field.isStatic && relationChecker.isAssignableFromType(field.type))
        .toList(growable: false);
    if (columns.isEmpty) {
      throw InvalidGenerationSourceError(
        'A Voxel table must declare at least one column.',
        element: element,
      );
    }

    final fields = [
      ...columns.map(
        (field) =>
            '  /// Value read from `${field.displayName}`.\n'
            '  final ${_columnValueType(field)} ${field.displayName};',
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
        .map((field) => 'definition.${field.displayName} as VoxelColumn<Object?>')
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
              '${literal(field.displayName)}: definition.${field.displayName} as VoxelRelationDescriptor<Object?>',
        )
        .join(', ');
    final enumCodecs = columns
        .map((field) => (field, _enumType(field)))
        .where((entry) => entry.$2 != null)
        .map((entry) {
          final field = entry.$1;
          final enumType = entry.$2!;
          final parts = enumType.split('.');
          parts[parts.length - 1] = '${parts.last}VoxelEnum';
          return 'definition.${field.displayName}.configureEnum(${parts.join('.')}.codec);';
        })
        .join('\n    ');
    final mutationFields = columns.map(_mutationField).toList(growable: false);
    final companionFields = mutationFields
        .map(
          (field) =>
              '  /// Mutation value for `${field.element.displayName}`.\n'
              '  final VoxelValue<$className, ${field.domainType}, ${field.storageType}> '
              '${field.element.displayName};',
        )
        .join('\n');
    final companionConstructorParameters =
        [
              ...mutationFields.where((field) => field.isRequiredInsert),
              ...mutationFields.where((field) => !field.isRequiredInsert),
            ]
            .map((field) {
              final type = 'VoxelValue<$className, ${field.domainType}, ${field.storageType}>';
              return field.isRequiredInsert
                  ? '    required $type ${field.element.displayName},'
                  : '    $type ${field.element.displayName} = const VoxelValue.absent(),';
            })
            .join('\n');
    final companionInitializers = mutationFields
        .map((field) => '      ${field.element.displayName}: ${field.element.displayName},')
        .join('\n');
    final companionUpdateParameters = mutationFields
        .map((field) {
          final type = 'VoxelValue<$className, ${field.domainType}, ${field.storageType}>';
          return '    $type ${field.element.displayName} = const VoxelValue.absent(),';
        })
        .join('\n');
    final companionPrivateParameters = mutationFields
        .map((field) => '    required this.${field.element.displayName},')
        .join('\n');
    final companionAssignments = mutationFields
        .map(
          (field) =>
              '    VoxelAssignment(${literal(field.element.displayName)}, '
              '${field.element.displayName == 'key' ? 'this.' : ''}${field.element.displayName}),',
        )
        .join('\n');

    return '''
/// Generated row returned by reads from ${literal('$schemaName.$tableName')}.
final class $rowName {
  /// Creates a row from decoded column and relation values.
  const $rowName({
$parameters
  });

$fields
}

/// Generated values accepted by mutations of ${literal('$schemaName.$tableName')}.
final class $companionName implements VoxelCompanion<$className> {
  const $companionName._({
$companionPrivateParameters
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory $companionName.insert({
$companionConstructorParameters
  }) => $companionName._(
$companionInitializers
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory $companionName.update({
$companionUpdateParameters
  }) => $companionName._(
$companionInitializers
  );

$companionFields

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<$className>> operator [](VoxelCompanionKey key) => [
$companionAssignments
  ];
}

final class _\$${className}DB extends VoxelTableAccessor<$className, $rowName> {
  const _\$${className}DB();

  @override
  VoxelTableSchema<$className, $rowName> buildSchema() {
    $className createDefinition() {
      final definition = $className();
      $enumCodecs
      return definition;
    }
    final definition = createDefinition();
    return VoxelTableSchema<$className, $rowName>(
      schemaName: ${literal(schemaName)},
      tableName: ${literal(tableName)},
$renameMetadata      definition: definition,
      definitionType: $className,
      rowType: $rowName,
      columns: [$descriptorList],
      columnNames: [$names],
      createDefinition: createDefinition,
      columnsFor: (definition) => [$descriptorList],
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
    return _enumTypeFromColumn(field.type, field.library);
  }

  _MutationField _mutationField(FieldElement field) {
    final type = field.type;
    if (type is! InterfaceType || type.typeArguments.isEmpty) {
      throw InvalidGenerationSourceError(
        'Voxel columns must retain their mutation value types.',
        element: field,
      );
    }
    final domain = type.typeArguments.first;
    final isMapped = const TypeChecker.typeNamed(
      VoxelMappedColumn,
      inPackage: 'voxel',
    ).isAssignableFromType(type);
    if (isMapped) _validateMappedHookOrder(field);
    final defaults = _columnDefaults(field);
    final domainType = referenceToType(domain, field.library);
    final recoveredDomainType = domainType == 'InvalidType' ? _columnValueType(field) : domainType;
    final storageType = isMapped && type.typeArguments.length > 1
        ? referenceToType(type.typeArguments[1], field.library)
        : recoveredDomainType;
    return _MutationField(
      element: field,
      domainType: recoveredDomainType,
      storageType: storageType,
      isRequiredInsert:
          domain.nullabilitySuffix != NullabilitySuffix.question && !defaults.hasInsertDefault,
    );
  }

  String _columnValueType(FieldElement field) {
    final rendered = columnValueType(field.type, field.library);
    if (rendered != 'InvalidType') return rendered;
    final parsed = field.library.session.getParsedLibraryByElement(field.library);
    if (parsed is! ParsedLibraryResult) return rendered;
    final declaration = parsed.getFragmentDeclaration(field.firstFragment)?.node;
    if (declaration is! VariableDeclaration || declaration.parent is! VariableDeclarationList) {
      return rendered;
    }
    final declared = (declaration.parent! as VariableDeclarationList).type?.toSource();
    if (declared == null) return rendered;
    final start = declared.indexOf('<');
    final end = declared.lastIndexOf('>');
    return start < 0 || end <= start ? rendered : declared.substring(start + 1, end);
  }

  _ColumnDefaults _columnDefaults(FieldElement field) {
    final parsed = field.library.session.getParsedLibraryByElement(field.library);
    if (parsed is! ParsedLibraryResult) return const _ColumnDefaults();
    final declaration = parsed.getFragmentDeclaration(field.firstFragment)?.node;
    if (declaration is! VariableDeclaration || declaration.initializer == null) {
      return const _ColumnDefaults();
    }
    final methods = <String>[];
    _collectColumnMethods(declaration.initializer!, methods);
    return _ColumnDefaults(
      hasDefaultFn: methods.contains('defaultValue') || methods.contains('chronoID'),
      hasOnUpdateFn: methods.contains('onUpdate'),
      hasSqlDefault: methods.contains('defaultSql'),
    );
  }

  void _validateMappedHookOrder(FieldElement field) {
    final parsed = field.library.session.getParsedLibraryByElement(field.library);
    if (parsed is! ParsedLibraryResult) return;
    final declaration = parsed.getFragmentDeclaration(field.firstFragment)?.node;
    if (declaration is! VariableDeclaration || declaration.initializer == null) return;
    final methods = <String>[];
    _collectColumnMethods(declaration.initializer!, methods);
    final mapIndex = methods.indexOf('map');
    if (mapIndex < 0) return;
    final storageHook = methods
        .take(mapIndex)
        .any(
          (method) => method == 'defaultValue' || method == 'onUpdate',
        );
    if (storageHook) {
      throw InvalidGenerationSourceError(
        'Mapped runtime hooks must be declared after map() so they return the domain type.',
        element: field,
      );
    }
  }

  void _collectColumnMethods(Expression expression, List<String> methods) {
    switch (expression) {
      case MethodInvocation(:final methodName, :final target):
        if (target != null) _collectColumnMethods(target, methods);
        methods.add(methodName.name);
      case FunctionExpressionInvocation(:final function):
        _collectColumnMethods(function, methods);
      case ParenthesizedExpression(:final expression):
        _collectColumnMethods(expression, methods);
      case PropertyAccess(:final target):
        if (target != null) _collectColumnMethods(target, methods);
      default:
        return;
    }
  }

  String? _enumTypeFromColumn(DartType type, LibraryElement library) {
    if (type is! InterfaceType) return null;
    for (final argument in type.typeArguments) {
      if (argument.element case final element?
          when const TypeChecker.typeNamed(
            VoxelEnum,
            inPackage: 'voxel',
          ).hasAnnotationOf(element)) {
        return referenceTo(element, library);
      }
      if (_enumTypeFromColumn(argument, library) case final nested?) return nested;
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
    var targetReference = target.getDisplayString();
    if (targetElement == null || targetReference == 'InvalidType') {
      targetReference = _relationTargetFromAst(field) ?? targetReference;
    }
    if (targetElement != null) {
      targetReference = referenceTo(targetElement, field.library);
    }
    final separator = targetReference.lastIndexOf('.');
    final prefix = separator < 0 ? '' : targetReference.substring(0, separator + 1);
    final unprefixedTarget = separator < 0
        ? targetReference
        : targetReference.substring(separator + 1);
    final defaultRowName = '${targetElement?.displayName ?? unprefixedTarget}Row';
    var targetRow = '$prefix$defaultRowName';
    if (targetElement != null) {
      final value = const TypeChecker.typeNamed(
        VoxelTable,
        inPackage: 'voxel',
      ).firstAnnotationOf(targetElement);
      if (value != null) {
        targetRow = '$prefix${readString(ConstantReader(value), 'rowName', defaultRowName)}';
      }
    }
    return const TypeChecker.typeNamed(
          VoxelOneRelation,
          inPackage: 'voxel',
        ).isAssignableFromType(type)
        ? 'Relation<$targetRow?>'
        : 'Relation<List<$targetRow>>';
  }

  String? _relationTargetFromAst(FieldElement field) {
    final parsed = field.library.session.getParsedLibraryByElement(field.library);
    if (parsed is! ParsedLibraryResult) return null;
    final declaration = parsed.getFragmentDeclaration(field.firstFragment)?.node;
    if (declaration is! VariableDeclaration || declaration.initializer == null) return null;
    final visitor = _RelationTargetVisitor();
    declaration.initializer!.accept(visitor);
    return visitor.target;
  }
}

final class _MutationField {
  const _MutationField({
    required this.element,
    required this.domainType,
    required this.storageType,
    required this.isRequiredInsert,
  });

  final FieldElement element;
  final String domainType;
  final String storageType;
  final bool isRequiredInsert;
}

final class _ColumnDefaults {
  const _ColumnDefaults({
    this.hasDefaultFn = false,
    this.hasOnUpdateFn = false,
    this.hasSqlDefault = false,
  });

  final bool hasDefaultFn;
  final bool hasOnUpdateFn;
  final bool hasSqlDefault;

  bool get hasInsertDefault => hasDefaultFn || hasOnUpdateFn || hasSqlDefault;
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

final class _RelationTargetVisitor extends RecursiveAstVisitor<void> {
  String? target;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (target == null && (node.methodName.name == 'one' || node.methodName.name == 'many')) {
      final arguments = node.typeArguments?.arguments;
      if (arguments != null && arguments.length == 1) target = arguments.single.toSource();
    }
    super.visitMethodInvocation(node);
  }
}

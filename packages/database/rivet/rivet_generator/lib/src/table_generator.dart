// Generator implementation types are internal to the builder entry point.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
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
    final schemaName = readString(annotation, 'schema', 'public');
    final tableName = readString(annotation, 'name', lowerCamel(className));
    final renamedFrom = readNullableString(annotation, 'renamedFrom');
    final renameMetadata = renamedFrom == null
        ? ''
        : '      renamedFrom: ${literal(renamedFrom)},\n';
    const columnChecker = TypeChecker.typeNamed(RivetColumn, inPackage: 'rivet');
    const relationChecker = TypeChecker.typeNamed(
      RivetRelationDescriptor,
      inPackage: 'rivet',
    );
    final columns = element.fields
        .where((field) => !field.isStatic && columnChecker.isAssignableFromType(field.type))
        .toList(growable: false);
    final relations = element.fields
        .where((field) => !field.isStatic && relationChecker.isAssignableFromType(field.type))
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
            '  final ${columnValueType(field.type, field.library)} ${field.displayName};',
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
    final relatedDecodes = [
      ...columns.indexed.map((entry) {
        final index = entry.$1;
        final field = entry.$2;
        return '${field.displayName}: transport '
            '? definition.${field.displayName}.decodeTransportValue(values[$index], '
            'isSqlNull: sqlNulls[$index]) '
            ': definition.${field.displayName}.decodeValue(values[$index], '
            'isSqlNull: sqlNulls[$index])';
      }),
      ...relations.map(
        (field) => '${field.displayName}: relations.read(${literal(field.displayName)})',
      ),
    ].join(', ');
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
    final relationBindings = relations
        .map((field) {
          final types = _relationTypes(field);
          final throughFactory = types.through == null
              ? ''
              : '        throughSchema: () => ${types.through}.db.buildSchema(),\n';
          return '''
      definition.${field.displayName}.bind(
        name: ${literal(field.displayName)},
        ownerSchema: builtSchema,
        targetSchema: () => ${types.target}.db.buildSchema(),
$throughFactory      );''';
        })
        .join('\n');
    final includeMethods = relations
        .map((field) {
          final types = _relationTypes(field);
          final fieldName = field.displayName;
          final isOne = const TypeChecker.typeNamed(
            RivetOneRelation,
            inPackage: 'rivet',
          ).isAssignableFromType(field.type);
          final collectionParameters = isOne
              ? ''
              : '''
    RivetOrderBy<${types.target}>? orderBy,
    int? limit,
''';
          final collectionArguments = isOne
              ? ''
              : '''
      orderBy: orderBy,
      limit: limit,
''';
          final throughDeclaration = types.through == null
              ? ''
              : '    final through = ${types.through}.db.buildSchema();\n';
          final throughArgument = types.through == null ? '' : '      throughSchema: through,\n';
          final nestedParameter = types.hasRelations
              ? '    RivetIncludes<${types.include}>? include,\n'
              : '';
          final nestedArgument = types.hasRelations
              ? '      includes: include?.call(${types.include}(target, path: relationPath)) ?? const [],\n'
              : '';
          return '''
  /// Includes the [$fieldName] relation.
  RivetInclude<${types.target}, ${types.row}> $fieldName({
    RivetWhere<${types.target}>? where,
$collectionParameters
$nestedParameter
  }) {
    final target = ${types.target}.db.buildSchema();
$throughDeclaration
    final relationPath = path.isEmpty ? ${literal(fieldName)} : '\$path.$fieldName';
    return RivetInclude<${types.target}, ${types.row}>(
      name: ${literal(fieldName)},
      path: relationPath,
      relation: _schema.relations[${literal(fieldName)}]!,
      targetSchema: target,
$throughArgument
      where: where,
$collectionArguments
$nestedArgument
    );
  }
''';
        })
        .join('\n');
    final includeScope = relations.isEmpty
        ? ''
        : '''
/// Typed relation include scope for [$className].
final class ${className}Include {
  /// Creates the generated include scope.
  const ${className}Include(this._schema, {this.path = ''});

  final RivetTableSchema<$className, $rowName> _schema;

  /// Full relation path used in diagnostics.
  final String path;

$includeMethods
}
''';
    final rowDecoder =
        '''
    $rowName decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => $rowName($relatedDecodes);
''';
    const schemaDecoders = '''
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,
''';
    final findMethod = relations.isEmpty
        ? ''
        : '''
  /// Creates a reusable read plan with typed relation includes.
  RivetFind<$className, $rowName> find({
    RivetWhere<$className>? where,
    RivetOrderBy<$className>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<${className}Include>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(${className}Include(schema)) ?? const [],
    );
  }
''';
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
    final mutationFields = columns.map(_mutationField).toList(growable: false);
    final companionFields = mutationFields
        .map(
          (field) =>
              '  /// Mutation value for `${field.element.displayName}`.\n'
              '  final RivetValue<$className, ${field.domainType}, ${field.storageType}> '
              '${field.element.displayName};',
        )
        .join('\n');
    final companionConstructorParameters =
        [
              ...mutationFields.where((field) => field.isRequiredInsert),
              ...mutationFields.where((field) => !field.isRequiredInsert),
            ]
            .map((field) {
              final type = 'RivetValue<$className, ${field.domainType}, ${field.storageType}>';
              return field.isRequiredInsert
                  ? '    required $type ${field.element.displayName},'
                  : '    $type ${field.element.displayName} = const RivetValue.absent(),';
            })
            .join('\n');
    final companionInitializers = mutationFields
        .map((field) => '      ${field.element.displayName}: ${field.element.displayName},')
        .join('\n');
    final companionUpdateParameters = mutationFields
        .map((field) {
          final type = 'RivetValue<$className, ${field.domainType}, ${field.storageType}>';
          return '    $type ${field.element.displayName} = const RivetValue.absent(),';
        })
        .join('\n');
    final companionPrivateParameters = mutationFields
        .map((field) => '    required this.${field.element.displayName},')
        .join('\n');
    final companionAssignments = mutationFields
        .map(
          (field) =>
              '    RivetAssignment(${literal(field.element.displayName)}, '
              '${field.element.displayName == 'key' ? 'this.' : ''}${field.element.displayName}),',
        )
        .join('\n');

    return '''
$includeScope
/// Generated row returned by reads from ${literal('$schemaName.$tableName')}.
final class $rowName {
  /// Creates a row from decoded column and relation values.
  const $rowName({
$parameters
  });

$fields
}

/// Generated values accepted by mutations of ${literal('$schemaName.$tableName')}.
final class $companionName implements RivetCompanion<$className> {
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
  List<RivetAssignment<$className>> operator [](RivetCompanionKey key) => [
$companionAssignments
  ];
}

final class _\$${className}DB extends RivetTableAccessor<$className, $rowName> {
  const _\$${className}DB();

  @override
  RivetTableSchema<$className, $rowName> buildSchema() {
    $className createDefinition() {
      final definition = $className();
      $enumCodecs
      return definition;
    }
    final definition = createDefinition();
$rowDecoder
    ${relations.isEmpty ? 'return' : 'final builtSchema ='} RivetTableSchema<$className, $rowName>(
      schemaName: ${literal(schemaName)},
      tableName: ${literal(tableName)},
$renameMetadata      definition: definition,
      columns: [$descriptorList],
      columnNames: [$names],
      createDefinition: createDefinition,
      columnsFor: (definition) => [$descriptorList],
$schemaDecoders
$indexes$constraints${relations.isEmpty ? '' : '      relations: {$relationMap},\n'}
    );
${relations.isEmpty ? '' : '$relationBindings\n    return builtSchema;'}
  }

$findMethod

  /// Creates a reusable insert plan.
  RivetInsert<$className, $rowName> insert(
    $companionName companion, {
    RivetOnConflict<$className>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<$className, $rowName> insertMany(
    Iterable<$companionName> companions, {
    RivetOnConflict<$className>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<$className, $rowName> update(
    $companionName companion, {
    RivetWhere<$className>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<$className, $rowName> delete({
    RivetWhere<$className>? where,
  }) => RivetDelete(buildSchema(), where: where);

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
        'Rivet columns must retain their mutation value types.',
        element: field,
      );
    }
    final domain = type.typeArguments.first;
    final isMapped = const TypeChecker.typeNamed(
      RivetMappedColumn,
      inPackage: 'rivet',
    ).isAssignableFromType(type);
    if (isMapped) _validateMappedHookOrder(field);
    final storage = isMapped && type.typeArguments.length > 1 ? type.typeArguments[1] : domain;
    final defaults = _columnDefaults(field);
    return _MutationField(
      element: field,
      domainType: referenceToType(domain, field.library),
      storageType: referenceToType(storage, field.library),
      isRequiredInsert:
          domain.nullabilitySuffix != NullabilitySuffix.question && !defaults.hasInsertDefault,
    );
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
            RivetEnum,
            inPackage: 'rivet',
          ).hasAnnotationOf(element)) {
        return referenceTo(element, library);
      }
      if (_enumTypeFromColumn(argument, library) case final nested?) return nested;
    }
    return null;
  }

  String _relationValueType(FieldElement field) {
    final types = _relationTypes(field);
    final type = field.type;
    return const TypeChecker.typeNamed(
          RivetOneRelation,
          inPackage: 'rivet',
        ).isAssignableFromType(type)
        ? 'Relation<${types.row}?>'
        : 'Relation<List<${types.row}>>';
  }

  _RelationTypes _relationTypes(FieldElement field) {
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
    if (targetElement != null) {
      targetReference = referenceTo(targetElement, field.library);
    }
    final separator = targetReference.lastIndexOf('.');
    final prefix = separator < 0 ? '' : targetReference.substring(0, separator + 1);
    final targetName = targetElement?.displayName ?? targetReference;
    final defaultRowName = '${targetName}Row';
    var targetRow = '$prefix$defaultRowName';
    if (targetElement != null) {
      final value = const TypeChecker.typeNamed(
        RivetTable,
        inPackage: 'rivet',
      ).firstAnnotationOf(targetElement);
      if (value != null) {
        targetRow = '$prefix${readString(ConstantReader(value), 'rowName', defaultRowName)}';
      }
    }
    final targetHasRelations =
        targetElement is ClassElement &&
        targetElement.fields.any(
          (field) =>
              !field.isStatic &&
              const TypeChecker.typeNamed(
                RivetRelationDescriptor,
                inPackage: 'rivet',
              ).isAssignableFromType(field.type),
        );
    final through =
        const TypeChecker.typeNamed(
          RivetManyThroughRelation,
          inPackage: 'rivet',
        ).isAssignableFromType(type)
        ? _typeReference(type.typeArguments[1], field.library)
        : null;
    return _RelationTypes(
      target: targetReference,
      row: targetRow,
      include: '$prefix${targetName}Include',
      hasRelations: targetHasRelations,
      through: through,
    );
  }

  String _typeReference(DartType type, LibraryElement library) {
    final element = type.element;
    return element == null ? type.getDisplayString() : referenceTo(element, library);
  }
}

final class _RelationTypes {
  const _RelationTypes({
    required this.target,
    required this.row,
    required this.include,
    required this.hasRelations,
    required this.through,
  });

  final String target;
  final String row;
  final String include;
  final bool hasRelations;
  final String? through;
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

// Relation state and metadata contracts are documented on their public root types.
// ignore_for_file: public_member_api_docs

import 'package:rivet/src/errors.dart';
import 'package:rivet/src/schema.dart';

typedef RivetIncludes<Scope> = List<RivetInclude<dynamic, dynamic>> Function(
  Scope include,
);

final class RivetRelationValues {
  const RivetRelationValues([this._values = const {}]);

  final Map<String, Relation<dynamic>> _values;

  Relation<T> read<T>(String name) => switch (_values[name]) {
    LoadedRelation<dynamic>(:final value) => Relation<T>.loaded(value as T),
    _ => Relation<T>.unloaded(),
  };
}

/// A relation field that has either been requested or deliberately left unloaded.
sealed class Relation<T> {
  const Relation();

  const factory Relation.unloaded() = UnloadedRelation<T>;
  const factory Relation.loaded(T value) = LoadedRelation<T>;

  bool get isLoaded;
}

final class UnloadedRelation<T> extends Relation<T> {
  const UnloadedRelation();

  @override
  bool get isLoaded => false;
}

final class LoadedRelation<T> extends Relation<T> {
  const LoadedRelation(this.value);

  final T value;

  @override
  bool get isLoaded => true;
}

enum RivetRelationKind { one, many, manyThrough }

/// Runtime metadata for a relation declaration. It never creates a foreign key.
final class RivetRelationDescriptor<Target> {
  RivetRelationDescriptor({
    required this.kind,
    required this.targetTable,
    this.through,
    this.fields = const [],
    this.reference,
    this.inverse,
  });

  final RivetRelationKind kind;
  final Type? through;
  final Type targetTable;
  final List<RivetColumn<dynamic>> fields;
  final List<RivetColumn<dynamic>> Function(Target table)? reference;
  final RivetRelationDescriptor<dynamic> Function(Target table)? inverse;
  List<RivetColumn<dynamic>> references = const [];
  RivetRelationDescriptor<dynamic>? inverseRelation;
  String? _name;
  RivetTableSchema<dynamic, dynamic>? _ownerSchema;
  RivetTableSchema<Target, dynamic> Function()? _targetSchema;
  RivetTableSchema<dynamic, dynamic> Function()? _throughSchema;

  void bind({
    required String name,
    required RivetTableSchema<dynamic, dynamic> ownerSchema,
    required RivetTableSchema<Target, dynamic> Function() targetSchema,
    RivetTableSchema<dynamic, dynamic> Function()? throughSchema,
  }) {
    _name = name;
    _ownerSchema = ownerSchema;
    _targetSchema = targetSchema;
    _throughSchema = throughSchema;
  }

  void resolve(Target definition) {
    references = List.unmodifiable(reference?.call(definition) ?? const []);
    inverseRelation = inverse?.call(definition);
  }
}

final class RivetOneRelation<Target> extends RivetRelationDescriptor<Target> {
  RivetOneRelation(
    Type targetTable, {
    required super.fields,
    required List<RivetColumn<dynamic>> Function(Target table) references,
  }) : super(
         kind: RivetRelationKind.one,
         targetTable: targetTable,
         reference: references,
       );

  RivetPredicate matches(RivetWhere<Target> where) => _relationPredicate(this, where);
}

final class RivetManyRelation<Target> extends RivetRelationDescriptor<Target> {
  RivetManyRelation(
    Type targetTable, {
    RivetRelationDescriptor<dynamic> Function(Target table)? relation,
  }) : super(
         kind: RivetRelationKind.many,
         targetTable: targetTable,
         inverse: relation,
       );

  RivetPredicate any(RivetWhere<Target> where) => _relationPredicate(this, where);

  RivetPredicate none(RivetWhere<Target> where) => _relationPredicate(this, where, negate: true);

  RivetRelationAggregate<int> count({RivetWhere<Target>? where}) =>
      _relationAggregate(this, 'count', const RivetCountCodec(), where: where);

  RivetRelationAggregate<Value?> min<Value>(
    RivetOrderableExpression<Value> Function(Target target) selector, {
    RivetWhere<Target>? where,
  }) => _relationMinMax(this, 'min', selector, where: where);

  RivetRelationAggregate<Value?> max<Value>(
    RivetOrderableExpression<Value> Function(Target target) selector, {
    RivetWhere<Target>? where,
  }) => _relationMinMax(this, 'max', selector, where: where);
}

final class RivetManyThroughRelation<Target, Junction, Source>
    extends RivetRelationDescriptor<Target> {
  RivetManyThroughRelation({required this.source, required this.target})
    : super(
        kind: RivetRelationKind.manyThrough,
        targetTable: Target,
        through: Junction,
      );

  final RivetOneRelation<Source> Function(Junction junction) source;
  final RivetOneRelation<Target> Function(Junction junction) target;
  RivetOneRelation<Source>? sourceRelation;
  RivetOneRelation<Target>? targetRelation;

  void resolveThrough(Junction definition) {
    sourceRelation = source(definition);
    targetRelation = target(definition);
  }

  RivetPredicate any(RivetWhere<Target> where) => _relationPredicate(this, where);

  RivetPredicate none(RivetWhere<Target> where) => _relationPredicate(this, where, negate: true);

  RivetRelationAggregate<int> count({RivetWhere<Target>? where}) =>
      _relationAggregate(this, 'count', const RivetCountCodec(), where: where);

  RivetRelationAggregate<Value?> min<Value>(
    RivetOrderableExpression<Value> Function(Target target) selector, {
    RivetWhere<Target>? where,
  }) => _relationMinMax(this, 'min', selector, where: where);

  RivetRelationAggregate<Value?> max<Value>(
    RivetOrderableExpression<Value> Function(Target target) selector, {
    RivetWhere<Target>? where,
  }) => _relationMinMax(this, 'max', selector, where: where);
}

final class RivetRelationBuilder<Target, RelationType extends RivetRelationDescriptor<Target>> {
  const RivetRelationBuilder(this.descriptor);

  final RelationType descriptor;

  RelationType call() => descriptor;
}

final class RivetManyRelationBuilder<Source, Target> {
  const RivetManyRelationBuilder(this.descriptor);

  final RivetManyRelation<Target> descriptor;

  RivetManyRelation<Target> call() => descriptor;

  RivetRelationBuilder<Target, RivetManyThroughRelation<Target, Junction, Source>>
  through<Junction>({
    required RivetOneRelation<Source> Function(Junction junction) source,
    required RivetOneRelation<Target> Function(Junction junction) target,
  }) => RivetRelationBuilder(
    RivetManyThroughRelation<Target, Junction, Source>(source: source, target: target),
  );
}

RivetPredicate _relationPredicate<Target>(
  RivetRelationDescriptor<Target> relation,
  RivetWhere<Target> where, {
  bool negate = false,
}) {
  final traversal = _RelationTraversal.create(relation);
  final predicate = where(traversal.target.definition);
  if (predicate.columns.any((column) => !column.belongsTo(traversal.target))) {
    throw RivetUnsupportedQueryException(
      'Relation predicate ${traversal.path} can only reference its related table.',
    );
  }
  return RivetPredicate.relation(
    renderSql: (placeholder, nextAlias) {
      final rendered = traversal.render(nextAlias);
      final predicates = [
        ...rendered.predicates,
        '(${predicate.renderWith(placeholder, nextAlias)}) IS TRUE',
      ];
      final exists = 'EXISTS (SELECT 1 FROM ${rendered.fromSql} WHERE ${predicates.join(' AND ')})';
      return negate ? 'NOT $exists' : exists;
    },
    parameters: predicate.parameters,
    columns: traversal.correlationRight,
  );
}

RivetRelationAggregate<int> _relationAggregate<Target>(
  RivetRelationDescriptor<Target> relation,
  String operation,
  RivetCodec<int> codec, {
  RivetWhere<Target>? where,
}) {
  final traversal = _RelationTraversal.create(relation);
  return RivetRelationAggregate._(
    traversal: traversal,
    operation: operation,
    codec: codec,
    where: _aggregateWhere(traversal, where),
  );
}

RivetRelationAggregate<Value?> _relationMinMax<Target, Value>(
  RivetRelationDescriptor<Target> relation,
  String operation,
  RivetOrderableExpression<Value> Function(Target target) selector, {
  RivetWhere<Target>? where,
}) {
  final traversal = _RelationTraversal.create(relation);
  final selected = selector(traversal.target.definition);
  if (selected.columns.any((column) => !column.belongsTo(traversal.target))) {
    throw RivetUnsupportedQueryException(
      'Relation aggregate ${traversal.path} can only select its related table.',
    );
  }
  return RivetRelationAggregate._(
    traversal: traversal,
    operation: operation,
    codec: RivetNullableCodec(selected.codec),
    selected: selected,
    where: _aggregateWhere(traversal, where),
  );
}

RivetPredicate? _aggregateWhere<Target>(
  _RelationTraversal<Target> traversal,
  RivetWhere<Target>? where,
) {
  final predicate = where?.call(traversal.target.definition);
  if (predicate?.columns.any((column) => !column.belongsTo(traversal.target)) ?? false) {
    throw RivetUnsupportedQueryException(
      'Relation aggregate ${traversal.path} can only filter its related table.',
    );
  }
  return predicate;
}

final class RivetRelationAggregate<T>
    implements RivetAliasedExpression<T>, RivetOrderableExpression<T> {
  const RivetRelationAggregate._({
    required _RelationTraversal<dynamic> traversal,
    required this.operation,
    required this.codec,
    this.selected,
    this.where,
  }) : _traversal = traversal;

  final _RelationTraversal<dynamic> _traversal;
  final String operation;
  final RivetOrderableExpression<dynamic>? selected;
  final RivetPredicate? where;

  @override
  final RivetCodec<T> codec;

  @override
  bool get usesRelations => true;

  @override
  bool get referencesRows => true;

  @override
  List<RivetColumn<dynamic>> get columns => _traversal.correlationRight;

  @override
  List<Object?> get parameters => [...?selected?.parameters, ...?where?.parameters];

  @override
  String get sql => throw const RivetUnsupportedQueryException(
    'Relation aggregates require an aliased query context.',
  );

  @override
  String renderParameters({int startAt = 1}) => sql;

  @override
  String renderPlaceholders(String Function(int index) placeholder) => sql;

  @override
  String renderWith(
    String Function(int index) placeholder,
    String Function() nextAlias,
  ) {
    final rendered = _traversal.render(nextAlias);
    final selectedSql = switch (selected) {
      null => '*',
      final RivetAliasedExpression<dynamic> expression => expression.renderWith(
        placeholder,
        nextAlias,
      ),
      final expression => expression.renderPlaceholders(placeholder),
    };
    final predicates = [...rendered.predicates];
    if (where case final predicate?) {
      final renderedWhere = predicate.renderWith(
        (index) => placeholder((selected?.parameters.length ?? 0) + index),
        nextAlias,
      );
      predicates.add('($renderedWhere) IS TRUE');
    }
    final whereSql = predicates.isEmpty ? '' : ' WHERE ${predicates.join(' AND ')}';
    return '(SELECT $operation($selectedSql) FROM ${rendered.fromSql}$whereSql)';
  }

  RivetPredicate equals(T value) => _compare('=', value);
  RivetPredicate lessThan(T value) => _compare('<', value);
  RivetPredicate greaterThan(T value) => _compare('>', value);

  RivetPredicate _compare(String operator, T value) {
    if (value == null) {
      return RivetPredicate.relation(
        renderSql: (placeholder, nextAlias) => '${renderWith(placeholder, nextAlias)} IS NULL',
        parameters: parameters,
        columns: columns,
      );
    }
    final encoded = codec.encode(value);
    return RivetPredicate.relation(
      renderSql: (placeholder, nextAlias) =>
          '${renderWith(placeholder, nextAlias)} $operator '
          '${placeholder(parameters.length)}::${codec.cast}',
      parameters: [...parameters, encoded],
      columns: columns,
    );
  }

  RivetOrder asc({NullsOrder nulls = NullsOrder.last}) =>
      RivetOrder(this, descending: false, nulls: nulls);
  RivetOrder desc({NullsOrder nulls = NullsOrder.last}) =>
      RivetOrder(this, descending: true, nulls: nulls);
}

final class _RelationTraversal<Target> {
  const _RelationTraversal({
    required this.path,
    required this.target,
    required this.correlationLeft,
    required this.correlationRight,
    this.through,
    this.targetJoinLeft = const [],
    this.targetJoinRight = const [],
  });

  factory _RelationTraversal.create(RivetRelationDescriptor<Target> relation) {
    final owner = relation._ownerSchema;
    final targetFactory = relation._targetSchema;
    final path = relation._name;
    if (owner == null || targetFactory == null || path == null) {
      throw StateError('Generated relation metadata is not bound to its table schema.');
    }
    final target = targetFactory();
    if (relation is RivetOneRelation<Target>) {
      relation.resolve(target.definition);
      _validateTraversalMapping(path, relation.fields, relation.references, owner, target);
      return _RelationTraversal(
        path: path,
        target: target,
        correlationLeft: relation.references,
        correlationRight: relation.fields,
      );
    }
    if (relation is RivetManyRelation<Target>) {
      relation.resolve(target.definition);
      final inverse = relation.inverseRelation ?? _inferTraversalInverse(relation, owner, target);
      inverse.resolve(owner.definition);
      _validateTraversalMapping(path, inverse.references, inverse.fields, owner, target);
      return _RelationTraversal(
        path: path,
        target: target,
        correlationLeft: inverse.fields,
        correlationRight: inverse.references,
      );
    }
    final throughRelation = relation as RivetManyThroughRelation<Target, dynamic, dynamic>;
    final through = relation._throughSchema?.call();
    if (through == null)
      throw StateError('Through relation $path has no generated junction schema.');
    throughRelation.resolveThrough(through.definition);
    final sourceRelation = throughRelation.sourceRelation!;
    final targetRelation = throughRelation.targetRelation!;
    if (!through.relations.values.contains(sourceRelation) ||
        !through.relations.values.contains(targetRelation) ||
        sourceRelation.targetTable != owner.definition.runtimeType ||
        targetRelation.targetTable != target.definition.runtimeType) {
      throw ArgumentError(
        'Through relation $path must select junction one-relations to its source and target.',
      );
    }
    sourceRelation.resolve(owner.definition);
    targetRelation.resolve(target.definition);
    _validateTraversalMapping(
      '$path.source',
      sourceRelation.references,
      sourceRelation.fields,
      owner,
      through,
    );
    _validateTraversalMapping(
      '$path.target',
      targetRelation.fields,
      targetRelation.references,
      through,
      target,
    );
    return _RelationTraversal(
      path: path,
      target: target,
      through: through,
      correlationLeft: sourceRelation.fields,
      correlationRight: sourceRelation.references,
      targetJoinLeft: targetRelation.references,
      targetJoinRight: targetRelation.fields,
    );
  }

  final String path;
  final RivetTableSchema<Target, dynamic> target;
  final RivetTableSchema<dynamic, dynamic>? through;
  final List<RivetColumn<dynamic>> correlationLeft;
  final List<RivetColumn<dynamic>> correlationRight;
  final List<RivetColumn<dynamic>> targetJoinLeft;
  final List<RivetColumn<dynamic>> targetJoinRight;

  ({String fromSql, List<String> predicates}) render(String Function() nextAlias) {
    final targetAlias = nextAlias();
    target.qualify(targetAlias);
    var fromSql = '${target.qualifiedName} AS ${quoteIdentifier(targetAlias)}';
    if (through case final junction?) {
      final throughAlias = nextAlias();
      junction.qualify(throughAlias);
      final targetJoin = [
        for (var index = 0; index < targetJoinLeft.length; index++)
          '${targetJoinLeft[index].sql} = ${targetJoinRight[index].sql}',
      ].join(' AND ');
      fromSql =
          '$fromSql JOIN ${junction.qualifiedName} AS '
          '${quoteIdentifier(throughAlias)} ON $targetJoin';
    }
    return (
      fromSql: fromSql,
      predicates: [
        for (var index = 0; index < correlationLeft.length; index++)
          '${correlationLeft[index].sql} = ${correlationRight[index].sql}',
      ],
    );
  }
}

RivetRelationDescriptor<dynamic> _inferTraversalInverse(
  RivetRelationDescriptor<dynamic> relation,
  RivetTableSchema<dynamic, dynamic> owner,
  RivetTableSchema<dynamic, dynamic> target,
) {
  final candidates = target.relations.values
      .where(
        (candidate) =>
            candidate.kind == RivetRelationKind.one &&
            candidate.targetTable == owner.definition.runtimeType,
      )
      .toList(growable: false);
  if (candidates.length != 1) {
    throw ArgumentError(
      'Relation ${relation._name} requires exactly one inverse; found ${candidates.length}.',
    );
  }
  return candidates.single;
}

void _validateTraversalMapping(
  String path,
  List<RivetColumn<dynamic>> source,
  List<RivetColumn<dynamic>> target,
  RivetTableSchema<dynamic, dynamic> sourceSchema,
  RivetTableSchema<dynamic, dynamic> targetSchema,
) {
  if (source.isEmpty || source.length != target.length) {
    throw ArgumentError('Relation $path must map the same non-zero number of columns.');
  }
  if (source.any((column) => !sourceSchema.columns.contains(column)) ||
      target.any((column) => !targetSchema.columns.contains(column))) {
    throw ArgumentError('Relation $path maps columns outside its source or target table.');
  }
  for (var index = 0; index < source.length; index++) {
    if (source[index].codec.cast != target[index].codec.cast) {
      throw ArgumentError('Relation $path maps incompatible column storage types.');
    }
  }
}

final class RivetInclude<Definition, Row> {
  RivetInclude({
    required this.name,
    required this.path,
    required this.relation,
    required this.targetSchema,
    this.throughSchema,
    RivetWhere<Definition>? where,
    RivetOrderBy<Definition>? orderBy,
    this.limit,
    List<RivetInclude<dynamic, dynamic>> includes = const [],
  }) : predicate = where?.call(targetSchema.definition),
       orders = List.unmodifiable(orderBy?.call(targetSchema.definition) ?? const []),
       includes = List.unmodifiable(includes) {
    if ((relation.kind == RivetRelationKind.manyThrough) != (throughSchema != null)) {
      throw ArgumentError('Relation $path requires exactly one matching through schema.');
    }
    if (throughSchema != null && throughSchema!.definition.runtimeType != relation.through) {
      throw ArgumentError('Relation $path received the wrong through schema.');
    }
    if (limit != null && limit! <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    if (relation.kind == RivetRelationKind.one && limit != null) {
      throw ArgumentError.value(limit, 'limit', 'is only supported for collection relations');
    }
    if (predicate?.columns.any((column) => !column.belongsTo(targetSchema)) ?? false) {
      throw RivetUnsupportedQueryException(
        'Include predicate $path can only reference its related table.',
      );
    }
    if (orders.any(
      (order) => order.expression.columns.any((column) => !column.belongsTo(targetSchema)),
    )) {
      throw RivetUnsupportedQueryException(
        'Include ordering $path can only reference its related table.',
      );
    }
    final names = <String>{};
    for (final include in includes) {
      if (!names.add(include.name)) {
        throw RivetUnsupportedQueryException(
          'Relation `${include.path}` is included more than once.',
        );
      }
    }
  }

  final String name;
  final String path;
  final RivetRelationDescriptor<dynamic> relation;
  final RivetTableSchema<Definition, Row> targetSchema;
  final RivetTableSchema<dynamic, dynamic>? throughSchema;
  final RivetPredicate? predicate;
  final List<RivetOrder> orders;
  final int? limit;
  final List<RivetInclude<dynamic, dynamic>> includes;

  Relation<dynamic> decode(Object? envelope) {
    if (envelope is! Map<Object?, Object?>) {
      throw FormatException('Relation $path returned an invalid transport envelope.');
    }
    final count = envelope['count'];
    final rows = envelope['rows'];
    if (count is! int || rows is! List<Object?> || count != rows.length) {
      throw FormatException('Relation $path returned inconsistent row metadata.');
    }
    if (relation.kind == RivetRelationKind.one && count > 1) {
      throw RivetCardinalityException(
        expected: 'zero or one related',
        actual: count,
        relationPath: path,
      );
    }
    final decoded = <Row>[for (final row in rows) _decodeRow(row)];
    return relation.kind == RivetRelationKind.one
        ? Relation<Row?>.loaded(decoded.firstOrNull)
        : Relation<List<Row>>.loaded(List<Row>.unmodifiable(decoded));
  }

  Row _decodeRow(Object? encoded) {
    if (encoded is! List<Object?> ||
        encoded.length != targetSchema.columns.length + includes.length) {
      throw FormatException('Relation $path returned an invalid row transport.');
    }
    final values = <Object?>[];
    final sqlNulls = <bool>[];
    for (var index = 0; index < targetSchema.columns.length; index++) {
      final cell = encoded[index];
      if (cell is! List<Object?> || cell.length != 2 || cell[0] is! bool) {
        throw FormatException('Relation $path returned an invalid column transport.');
      }
      final isSqlNull = cell[0]! as bool;
      sqlNulls.add(isSqlNull);
      values.add(cell[1]);
    }
    final related = <String, Relation<dynamic>>{};
    for (var index = 0; index < includes.length; index++) {
      final include = includes[index];
      related[include.name] = include.decode(encoded[targetSchema.columns.length + index]);
    }
    return targetSchema.decodeRow(
      values,
      sqlNulls,
      relations: RivetRelationValues(related),
      transport: true,
    );
  }
}

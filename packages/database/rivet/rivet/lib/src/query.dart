// Query usage is documented on the plan and terminal entry points and in the package README.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:rivet/src/errors.dart';
import 'package:rivet/src/relation.dart';
import 'package:rivet/src/schema.dart';

const _postgresParameterLimit = 65535;
const int _postgresSqlByteLimit = 1024 * 1024 * 1024;

/// A compiled query plus validated bound values.
final class RivetCompiledQuery {
  RivetCompiledQuery(this.sql, List<Object?> parameters)
    : parameters = List.unmodifiable(parameters) {
    if (parameters.length > _postgresParameterLimit) {
      throw const RivetUnsupportedQueryException(
        'PostgreSQL supports at most 65535 bound parameters.',
      );
    }
    if (utf8.encode(sql).length > _postgresSqlByteLimit) {
      throw const RivetUnsupportedQueryException(
        'The compiled PostgreSQL statement exceeds the supported SQL size.',
      );
    }
  }

  final String sql;
  final List<Object?> parameters;
}

final class ScoredRow<Row> {
  const ScoredRow({required this.row, required this.score});

  final Row row;
  final double? score;
}

/// Execution boundary accepted by query terminals.
// The interface keeps query plans independent from database and transaction owners.
abstract interface class RivetExecutor {
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  );

  Future<int> executeAffected(RivetCompiledQuery query);
}

extension RivetFindAccess<Definition, Row> on RivetTableAccessor<Definition, Row> {
  /// Creates an immutable root read plan.
  RivetFind<Definition, Row> find({
    RivetWhere<Definition>? where,
    RivetOrderBy<Definition>? orderBy,
    int? limit,
    int? offset,
    List<RivetInclude<dynamic, dynamic>> includes = const [],
  }) => RivetFind(
    buildSchema(),
    where: where,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
    includes: includes,
  );
}

/// An immutable, reusable root query plan.
final class RivetFind<Definition, Row> {
  RivetFind(
    this._schema, {
    RivetWhere<Definition>? where,
    RivetOrderBy<Definition>? orderBy,
    int? limit,
    int? offset,
    List<RivetInclude<dynamic, dynamic>> includes = const [],
  }) : _predicate = where?.call(_schema.definition),
       _orders = List.unmodifiable(orderBy?.call(_schema.definition) ?? const []),
       _limit = _positiveOrNull(limit, 'limit'),
       _offset = _nonNegativeOrNull(offset, 'offset'),
       _includes = List.unmodifiable(includes) {
    if (_predicate?.columns.any((column) => !column.belongsTo(_schema)) ?? false) {
      throw const RivetUnsupportedQueryException(
        'A root predicate can only reference columns from its root table.',
      );
    }
    if (_orders.any(
      (order) => order.expression.columns.any((column) => !column.belongsTo(_schema)),
    )) {
      throw const RivetUnsupportedQueryException(
        'Root ordering can only reference columns from its root table.',
      );
    }
    final names = <String>{};
    for (final include in _includes) {
      if (!identical(include.relation, _schema.relations[include.name])) {
        throw RivetUnsupportedQueryException(
          'Relation `${include.path}` does not belong to the root table.',
        );
      }
      if (!names.add(include.name)) {
        throw RivetUnsupportedQueryException(
          'Relation `${include.path}` is included more than once.',
        );
      }
    }
  }

  final RivetTableSchema<Definition, Row> _schema;
  final RivetPredicate? _predicate;
  final List<RivetOrder> _orders;
  final int? _limit;
  final int? _offset;
  final List<RivetInclude<dynamic, dynamic>> _includes;

  RivetScoredFind<Definition, Row, Score> withScore<Score extends double?>(
    RivetExpression<Score> Function(Definition table) score,
  ) {
    final expression = score(_schema.definition);
    if (expression.codec.cast != 'float8' ||
        expression.columns.any((column) => !column.belongsTo(_schema))) {
      throw const RivetUnsupportedQueryException(
        'A score must be a double expression from the root query scope.',
      );
    }
    return RivetScoredFind<Definition, Row, Score>(this, expression);
  }

  Future<List<Row>> get(RivetExecutor executor) => executor.execute(_compile(), _decodeRow);

  Future<Row> getSingle(RivetExecutor executor) async {
    final rows = await executor.execute(_compile(terminalLimit: 2), _decodeRow);
    if (rows.length != 1) {
      throw RivetCardinalityException(expected: 'exactly one', actual: rows.length);
    }
    return rows.single;
  }

  Future<Row?> getSingleOrNull(RivetExecutor executor) async {
    final rows = await executor.execute(_compile(terminalLimit: 2), _decodeRow);
    if (rows.length > 1) {
      throw RivetCardinalityException(expected: 'zero or one', actual: rows.length);
    }
    return rows.firstOrNull;
  }

  Future<Row?> getFirstOrNull(RivetExecutor executor) async {
    final rows = await executor.execute(_compile(terminalLimit: 1), _decodeRow);
    return rows.firstOrNull;
  }

  RivetCompiledQuery _compile({
    int? terminalLimit,
    RivetExpression<dynamic>? score,
  }) {
    if (_includes.isNotEmpty ||
        (_predicate?.usesRelations ?? false) ||
        score is RivetAliasedExpression<dynamic> ||
        _orders.any(
          (order) =>
              order.expression is RivetAliasedExpression<dynamic> &&
              (order.expression as RivetAliasedExpression<dynamic>).usesRelations,
        )) {
      return _compileRelational(terminalLimit: terminalLimit, score: score);
    }
    final parameters = <Object?>[];
    final columns = _schema.columns.indexed
        .map((entry) => '${entry.$2.selectionSql} AS "__rivet_c${entry.$1}"')
        .toList();
    if (score != null) {
      final rendered = score.renderParameters(startAt: parameters.length + 1);
      parameters.addAll(score.parameters);
      columns.add('${score.codec.select(rendered)} AS "__rivet_score"');
    }
    final sql = StringBuffer('SELECT ${columns.join(', ')} FROM ${_schema.qualifiedName}');
    if (_predicate case final predicate?) {
      parameters.addAll(predicate.parameters);
      sql.write(' WHERE ${predicate.renderParameters()}');
    }
    if (_orders.isNotEmpty) {
      sql.write(' ORDER BY ${_renderOrders(_orders, parameters)}');
    }
    final effectiveLimit = switch ((_limit, terminalLimit)) {
      (final int requested, final int terminal) => requested < terminal ? requested : terminal,
      (final int requested, null) => requested,
      (null, final int terminal) => terminal,
      _ => null,
    };
    if (effectiveLimit != null) sql.write(' LIMIT $effectiveLimit');
    if (_offset != null) sql.write(' OFFSET $_offset');
    return RivetCompiledQuery(sql.toString(), parameters);
  }

  Row _decodeRow(List<Object?> values, List<bool> sqlNulls) {
    if (_includes.isEmpty) return _schema.decode(values, sqlNulls);
    final related = <String, Relation<dynamic>>{};
    for (var index = 0; index < _includes.length; index++) {
      final include = _includes[index];
      related[include.name] = include.decode(values[_schema.columns.length + index]);
    }
    return _schema.decodeRow(
      values.take(_schema.columns.length).toList(growable: false),
      sqlNulls.take(_schema.columns.length).toList(growable: false),
      relations: RivetRelationValues(related),
    );
  }

  RivetCompiledQuery _compileRelational({
    int? terminalLimit,
    RivetExpression<dynamic>? score,
  }) {
    var aliasIndex = 0;
    String nextAlias() => '__rivet_t${aliasIndex++}';
    final rootAlias = nextAlias();
    _schema.qualify(rootAlias);
    final parameters = <Object?>[];
    final selections = <String>[
      for (final column in _schema.columns) column.selectionSql,
      for (var index = 0; index < _includes.length; index++)
        '${_compileInclude(_includes[index], _schema, parameters, nextAlias)} AS "__rivet_r$index"',
    ];
    if (score != null) {
      final rendered = _renderExpression(score, parameters, nextAlias: nextAlias);
      selections.add('${score.codec.select(rendered)} AS "__rivet_score"');
    }
    final sql = StringBuffer(
      'SELECT ${selections.join(', ')} FROM ${_schema.qualifiedName} AS ${quoteIdentifier(rootAlias)}',
    );
    if (_predicate case final predicate?) {
      final rendered = predicate.renderParameters(
        startAt: parameters.length + 1,
        nextAlias: nextAlias,
      );
      sql.write(' WHERE $rendered');
      parameters.addAll(predicate.parameters);
    }
    if (_orders.isNotEmpty) {
      sql.write(
        ' ORDER BY ${_renderOrders(_orders, parameters, nextAlias: nextAlias)}',
      );
    }
    final effectiveLimit = switch ((_limit, terminalLimit)) {
      (final int requested, final int terminal) => requested < terminal ? requested : terminal,
      (final int requested, null) => requested,
      (null, final int terminal) => terminal,
      _ => null,
    };
    if (effectiveLimit != null) sql.write(' LIMIT $effectiveLimit');
    if (_offset != null) sql.write(' OFFSET $_offset');
    return RivetCompiledQuery(sql.toString(), parameters);
  }
}

final class RivetScoredFind<Definition, Row, Score extends double?> {
  const RivetScoredFind(this._find, this._score);

  final RivetFind<Definition, Row> _find;
  final RivetExpression<Score> _score;

  Future<List<ScoredRow<Row>>> get(RivetExecutor executor) =>
      executor.execute(_find._compile(score: _score), _decode);

  Future<ScoredRow<Row>> getSingle(RivetExecutor executor) async {
    final rows = await executor.execute(
      _find._compile(terminalLimit: 2, score: _score),
      _decode,
    );
    if (rows.length != 1) {
      throw RivetCardinalityException(expected: 'exactly one', actual: rows.length);
    }
    return rows.single;
  }

  Future<ScoredRow<Row>?> getSingleOrNull(RivetExecutor executor) async {
    final rows = await executor.execute(
      _find._compile(terminalLimit: 2, score: _score),
      _decode,
    );
    if (rows.length > 1) {
      throw RivetCardinalityException(expected: 'zero or one', actual: rows.length);
    }
    return rows.firstOrNull;
  }

  Future<ScoredRow<Row>?> getFirstOrNull(RivetExecutor executor) async {
    final rows = await executor.execute(
      _find._compile(terminalLimit: 1, score: _score),
      _decode,
    );
    return rows.firstOrNull;
  }

  ScoredRow<Row> _decode(List<Object?> values, List<bool> sqlNulls) {
    final scoreIndex = _find._schema.columns.length + _find._includes.length;
    return ScoredRow(
      row: _find._decodeRow(values, sqlNulls),
      score: _score.codec.decode(
        values[scoreIndex],
        isSqlNull: sqlNulls[scoreIndex],
      ),
    );
  }
}

String _compileInclude(
  RivetInclude<dynamic, dynamic> include,
  RivetTableSchema<dynamic, dynamic> source,
  List<Object?> parameters,
  String Function() nextAlias,
) {
  final target = include.targetSchema;
  final alias = nextAlias();
  target.qualify(alias);
  final relation = include.relation;
  final join = relation.kind == RivetRelationKind.manyThrough
      ? _resolveThroughJoin(include, source, target, alias, nextAlias)
      : _resolveDirectJoin(include, source, target, alias);
  final nestedSelections = [
    for (final nested in include.includes) _compileInclude(nested, target, parameters, nextAlias),
  ];
  final cells = <String>[
    for (final column in target.columns) column.codec.transportSql(column.sql),
    ...nestedSelections,
  ];
  final predicates = [...join.predicates];
  if (include.predicate case final predicate?) {
    predicates.add(
      predicate.renderParameters(
        startAt: parameters.length + 1,
        nextAlias: nextAlias,
      ),
    );
    parameters.addAll(predicate.parameters);
  }
  final renderedOrder = include.orders.isEmpty
      ? ''
      : _renderOrders(include.orders, parameters, nextAlias: nextAlias);
  final orderSql = renderedOrder.isEmpty ? '' : ' ORDER BY $renderedOrder';
  final aggregateOrder = include.orders.isEmpty ? '' : ' ORDER BY "__rivet_ordinal"';
  final ordinal = include.orders.isEmpty
      ? ''
      : ', row_number() OVER (ORDER BY $renderedOrder) AS "__rivet_ordinal"';
  final limit = relation.kind == RivetRelationKind.one ? 2 : include.limit;
  final limitSql = limit == null ? '' : '\n  LIMIT $limit';
  return '''
(
SELECT jsonb_build_object(
  'count', count(*),
  'rows', COALESCE(jsonb_agg("__rivet_row"$aggregateOrder), '[]'::jsonb)
)
FROM (
  SELECT jsonb_build_array(${cells.join(', ')}) AS "__rivet_row"$ordinal
  FROM ${join.fromSql}
  WHERE ${predicates.join(' AND ')}$orderSql$limitSql
) AS "__rivet_relation"
)''';
}

({String fromSql, List<String> predicates}) _resolveDirectJoin(
  RivetInclude<dynamic, dynamic> include,
  RivetTableSchema<dynamic, dynamic> source,
  RivetTableSchema<dynamic, dynamic> target,
  String targetAlias,
) {
  final relation = include.relation;
  final mapping = relation.kind == RivetRelationKind.one
      ? _resolveOneMapping(relation, source, target)
      : _resolveManyMapping(include, source, target);
  _validateMapping(include.path, mapping, source, target);
  return (
    fromSql: '${target.qualifiedName} AS ${quoteIdentifier(targetAlias)}',
    predicates: [
      for (var index = 0; index < mapping.source.length; index++)
        '${mapping.target[index].sql} = ${mapping.source[index].sql}',
    ],
  );
}

({String fromSql, List<String> predicates}) _resolveThroughJoin(
  RivetInclude<dynamic, dynamic> include,
  RivetTableSchema<dynamic, dynamic> source,
  RivetTableSchema<dynamic, dynamic> target,
  String targetAlias,
  String Function() nextAlias,
) {
  final through = include.throughSchema!;
  final throughAlias = nextAlias();
  through.qualify(throughAlias);
  final relation = (include.relation as RivetManyThroughRelation<dynamic, dynamic, dynamic>)
    ..resolveThrough(through.definition);
  final sourceRelation = relation.sourceRelation!;
  final targetRelation = relation.targetRelation!;
  if (!through.relations.values.contains(sourceRelation) ||
      !through.relations.values.contains(targetRelation) ||
      sourceRelation.targetTable != source.definition.runtimeType ||
      targetRelation.targetTable != target.definition.runtimeType) {
    throw ArgumentError(
      'Through relation ${include.path} must select junction one-relations to its source and target.',
    );
  }
  sourceRelation.resolve(source.definition);
  targetRelation.resolve(target.definition);
  final sourceMapping = (
    source: sourceRelation.references,
    target: sourceRelation.fields,
  );
  final targetMapping = (
    source: targetRelation.fields,
    target: targetRelation.references,
  );
  _validateMapping('${include.path}.source', sourceMapping, source, through);
  _validateMapping('${include.path}.target', targetMapping, through, target);
  final targetJoin = [
    for (var index = 0; index < targetMapping.source.length; index++)
      '${targetMapping.target[index].sql} = ${targetMapping.source[index].sql}',
  ].join(' AND ');
  return (
    fromSql:
        '${target.qualifiedName} AS ${quoteIdentifier(targetAlias)} '
        'JOIN ${through.qualifiedName} AS ${quoteIdentifier(throughAlias)} ON $targetJoin',
    predicates: [
      for (var index = 0; index < sourceMapping.source.length; index++)
        '${sourceMapping.target[index].sql} = ${sourceMapping.source[index].sql}',
    ],
  );
}

void _validateMapping(
  String path,
  ({List<RivetColumn<dynamic>> source, List<RivetColumn<dynamic>> target}) mapping,
  RivetTableSchema<dynamic, dynamic> source,
  RivetTableSchema<dynamic, dynamic> target,
) {
  if (mapping.source.isEmpty || mapping.source.length != mapping.target.length) {
    throw ArgumentError('Relation $path must map the same non-zero number of columns.');
  }
  if (mapping.source.any((column) => !source.columns.contains(column)) ||
      mapping.target.any((column) => !target.columns.contains(column))) {
    throw ArgumentError('Relation $path maps columns outside its source or target table.');
  }
  for (var index = 0; index < mapping.source.length; index++) {
    if (mapping.source[index].codec.cast != mapping.target[index].codec.cast) {
      throw ArgumentError('Relation $path maps incompatible column storage types.');
    }
  }
}

({List<RivetColumn<dynamic>> source, List<RivetColumn<dynamic>> target}) _resolveOneMapping(
  RivetRelationDescriptor<dynamic> relation,
  RivetTableSchema<dynamic, dynamic> source,
  RivetTableSchema<dynamic, dynamic> target,
) {
  relation.resolve(target.definition);
  return (source: relation.fields, target: relation.references);
}

({List<RivetColumn<dynamic>> source, List<RivetColumn<dynamic>> target}) _resolveManyMapping(
  RivetInclude<dynamic, dynamic> include,
  RivetTableSchema<dynamic, dynamic> source,
  RivetTableSchema<dynamic, dynamic> target,
) {
  final relation = include.relation..resolve(target.definition);
  final inverse = relation.inverseRelation ?? _inferInverse(include, source, target);
  if (!target.relations.values.contains(inverse)) {
    throw ArgumentError('Relation ${include.path} selects an inverse outside its target table.');
  }
  if (inverse.kind != RivetRelationKind.one ||
      inverse.targetTable != source.definition.runtimeType) {
    throw ArgumentError(
      'Relation ${include.path} must resolve to a one-relation back to its source.',
    );
  }
  inverse.resolve(source.definition);
  return (source: inverse.references, target: inverse.fields);
}

RivetRelationDescriptor<dynamic> _inferInverse(
  RivetInclude<dynamic, dynamic> include,
  RivetTableSchema<dynamic, dynamic> source,
  RivetTableSchema<dynamic, dynamic> target,
) {
  final candidates = target.relations.values
      .where(
        (relation) =>
            relation.kind == RivetRelationKind.one &&
            relation.targetTable == source.definition.runtimeType,
      )
      .toList(growable: false);
  if (candidates.length != 1) {
    throw ArgumentError(
      'Relation ${include.path} requires an explicit inverse because its target has '
      '${candidates.length} matching one-relations.',
    );
  }
  return candidates.single;
}

String _renderOrders(
  List<RivetOrder> orders,
  List<Object?> parameters, {
  String Function()? nextAlias,
}) => orders
    .map((order) {
      final expression = order.expression;
      final rendered = _renderExpression(expression, parameters, nextAlias: nextAlias);
      final direction = order.descending ? 'DESC' : 'ASC';
      final nulls = order.nulls == NullsOrder.first ? 'FIRST' : 'LAST';
      return '$rendered $direction NULLS $nulls';
    })
    .join(', ');

String _renderExpression(
  RivetExpression<dynamic> expression,
  List<Object?> parameters, {
  String Function()? nextAlias,
}) {
  final rendered = expression is RivetAliasedExpression<dynamic>
      ? expression.renderWith(
          (index) => '\$${parameters.length + index + 1}',
          nextAlias ??
              (throw const RivetUnsupportedQueryException(
                'The expression requires an aliased query context.',
              )),
        )
      : expression.renderParameters(startAt: parameters.length + 1);
  parameters.addAll(expression.parameters);
  return rendered;
}

int? _positiveOrNull(int? value, String name) {
  if (value != null && value <= 0) throw ArgumentError.value(value, name, 'must be positive');
  return value;
}

int? _nonNegativeOrNull(int? value, String name) {
  if (value != null && value < 0) throw ArgumentError.value(value, name, 'must not be negative');
  return value;
}

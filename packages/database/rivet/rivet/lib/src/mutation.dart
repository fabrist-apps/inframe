// Mutation plans retain values and callbacks, then compile them at execution time.
// ignore_for_file: avoid_returning_this, one_member_abstracts, prefer_initializing_formals, public_member_api_docs

import 'package:rivet/src/errors.dart';
import 'package:rivet/src/query.dart';
import 'package:rivet/src/schema.dart';

sealed class RivetValue<Definition, Domain, Storage> {
  const RivetValue();

  const factory RivetValue.present(Domain value) = RivetPresent<Definition, Domain, Storage>;
  const factory RivetValue.absent() = RivetAbsent<Definition, Domain, Storage>;
  const factory RivetValue.expression(
    RivetExpression<Storage> Function(Definition table) expression,
  ) = RivetExpressionValue<Definition, Domain, Storage>;
}

final class RivetPresent<Definition, Domain, Storage>
    extends RivetValue<Definition, Domain, Storage> {
  const RivetPresent(this.value);

  final Domain value;
}

final class RivetAbsent<Definition, Domain, Storage>
    extends RivetValue<Definition, Domain, Storage> {
  const RivetAbsent();
}

final class RivetExpressionValue<Definition, Domain, Storage>
    extends RivetValue<Definition, Domain, Storage> {
  const RivetExpressionValue(this.expression);

  final RivetExpression<Storage> Function(Definition table) expression;
}

final class RivetAssignment<Definition> {
  RivetAssignment(this.columnName, this.value);

  final String columnName;
  final RivetValue<Definition, dynamic, dynamic> value;
}

enum RivetCompanionKey { assignments }

abstract interface class RivetCompanion<Definition> {
  List<RivetAssignment<Definition>> operator [](RivetCompanionKey key);
}

typedef RivetConflictTarget<Definition> = List<RivetColumn<dynamic>> Function(Definition table);
typedef RivetConflictSet<Definition> = RivetCompanion<Definition> Function(
  Definition old,
  Definition excluded,
);
typedef RivetConflictWhere<Definition> = RivetPredicate Function(
  Definition old,
  Definition excluded,
);
typedef RivetOnConflict<Definition> = RivetConflictAction<Definition> Function(
  RivetConflictBuilder<Definition> conflict,
);

sealed class RivetConflictAction<Definition> {
  const RivetConflictAction();
}

final class RivetConflictBuilder<Definition> {
  const RivetConflictBuilder._(this._schema);

  final RivetTableSchema<Definition, dynamic> _schema;

  RivetConflictAction<Definition> doNothing({
    RivetConflictTarget<Definition>? target,
    RivetWhere<Definition>? targetWhere,
  }) {
    if (target == null && targetWhere != null) {
      throw const RivetUnsupportedQueryException(
        'A conflict targetWhere requires a target.',
      );
    }
    final columns = target == null ? const <RivetColumn<dynamic>>[] : _target(target);
    final predicate = _targetWhere(targetWhere);
    return _RivetDoNothing(columns, predicate);
  }

  RivetConflictAction<Definition> update({
    required RivetConflictTarget<Definition> target,
    required RivetConflictSet<Definition> set,
    RivetWhere<Definition>? targetWhere,
    RivetConflictWhere<Definition>? where,
  }) {
    final old = _schema.scopedDefinition(_schema.tableName);
    final excluded = _schema.scopedDefinition('excluded');
    final assignments = set(old, excluded);
    final predicate = where?.call(old, excluded);
    if (predicate?.columns.any((column) => !column.belongsTo(_schema)) ?? false) {
      throw const RivetUnsupportedQueryException(
        'A conflict update predicate can only reference the inserted table.',
      );
    }
    return _RivetConflictUpdate(
      _target(target),
      _targetWhere(targetWhere),
      assignments,
      predicate,
    );
  }

  List<RivetColumn<dynamic>> _target(RivetConflictTarget<Definition> target) {
    final columns = List<RivetColumn<dynamic>>.unmodifiable(target(_schema.definition));
    if (columns.isEmpty) {
      throw const RivetUnsupportedQueryException(
        'A conflict target must select at least one column.',
      );
    }
    if (columns.any((column) => !column.belongsTo(_schema))) {
      throw const RivetUnsupportedQueryException(
        'Conflict targets can only select columns from the inserted table.',
      );
    }
    return columns;
  }

  RivetPredicate? _targetWhere(RivetWhere<Definition>? targetWhere) {
    final predicate = targetWhere?.call(_schema.definition);
    if (predicate?.columns.any((column) => !column.belongsTo(_schema)) ?? false) {
      throw const RivetUnsupportedQueryException(
        'A conflict targetWhere can only reference the inserted table.',
      );
    }
    return predicate;
  }
}

final class _RivetDoNothing<Definition> extends RivetConflictAction<Definition> {
  const _RivetDoNothing(this.columns, this.targetWhere);

  final List<RivetColumn<dynamic>> columns;
  final RivetPredicate? targetWhere;
}

final class _RivetConflictUpdate<Definition> extends RivetConflictAction<Definition> {
  const _RivetConflictUpdate(
    this.columns,
    this.targetWhere,
    this.assignments,
    this.predicate,
  );

  final List<RivetColumn<dynamic>> columns;
  final RivetPredicate? targetWhere;
  final RivetCompanion<Definition> assignments;
  final RivetPredicate? predicate;
}

extension RivetMutationAccess<Definition, Row> on RivetTableAccessor<Definition, Row> {
  RivetInsert<Definition, Row> insert(
    RivetCompanion<Definition> companion, {
    RivetOnConflict<Definition>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  RivetInsertMany<Definition, Row> insertMany(
    Iterable<RivetCompanion<Definition>> companions, {
    RivetOnConflict<Definition>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  RivetUpdate<Definition, Row> update(
    RivetCompanion<Definition> companion, {
    RivetWhere<Definition>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  RivetDelete<Definition, Row> delete({RivetWhere<Definition>? where}) =>
      RivetDelete(buildSchema(), where: where);
}

final class RivetInsert<Definition, Row> {
  const RivetInsert(
    this._schema,
    this._companion, {
    RivetOnConflict<Definition>? onConflict,
  }) : _onConflict = onConflict;

  final RivetTableSchema<Definition, Row> _schema;
  final RivetCompanion<Definition> _companion;
  final RivetOnConflict<Definition>? _onConflict;

  RivetInsert<Definition, Row> prepare() => this;

  Future<int> execute(RivetExecutor executor) => executor.executeAffected(
    _compileInsert(
      _schema,
      _companion,
      onConflict: _onConflict,
      returning: false,
    ),
  );

  RivetReturningInsert<Definition, Row> returning() =>
      RivetReturningInsert(_schema, _companion, _onConflict);
}

final class RivetReturningInsert<Definition, Row> {
  const RivetReturningInsert(this._schema, this._companion, this._onConflict);

  final RivetTableSchema<Definition, Row> _schema;
  final RivetCompanion<Definition> _companion;
  final RivetOnConflict<Definition>? _onConflict;

  RivetReturningInsert<Definition, Row> prepare() => this;

  Future<List<Row>> get(RivetExecutor executor) => executor.execute(
    _compileInsert(
      _schema,
      _companion,
      onConflict: _onConflict,
      returning: true,
    ),
    _schema.decode,
  );
}

final class RivetInsertMany<Definition, Row> {
  RivetInsertMany(
    this._schema,
    Iterable<RivetCompanion<Definition>> companions, {
    RivetOnConflict<Definition>? onConflict,
  }) : _companions = List.unmodifiable(companions),
       _onConflict = onConflict;

  final RivetTableSchema<Definition, Row> _schema;
  final List<RivetCompanion<Definition>> _companions;
  final RivetOnConflict<Definition>? _onConflict;

  RivetInsertMany<Definition, Row> prepare() => this;

  Future<int> execute(RivetExecutor executor) {
    if (_companions.isEmpty) return Future.value(0);
    return executor.executeAffected(
      _compileInsertMany(
        _schema,
        _companions,
        onConflict: _onConflict,
        returning: false,
      ),
    );
  }

  RivetReturningInsertMany<Definition, Row> returning() =>
      RivetReturningInsertMany(_schema, _companions, _onConflict);
}

final class RivetReturningInsertMany<Definition, Row> {
  const RivetReturningInsertMany(
    this._schema,
    this._companions,
    this._onConflict,
  );

  final RivetTableSchema<Definition, Row> _schema;
  final List<RivetCompanion<Definition>> _companions;
  final RivetOnConflict<Definition>? _onConflict;

  RivetReturningInsertMany<Definition, Row> prepare() => this;

  Future<List<Row>> get(RivetExecutor executor) {
    if (_companions.isEmpty) return Future.value(const []);
    return executor.execute(
      _compileInsertMany(
        _schema,
        _companions,
        onConflict: _onConflict,
        returning: true,
      ),
      _schema.decode,
    );
  }
}

final class RivetUpdate<Definition, Row> {
  RivetUpdate(
    this._schema,
    this._companion, {
    RivetWhere<Definition>? where,
  }) : _predicate = where?.call(_schema.definition) {
    if (_predicate?.columns.any((column) => !column.belongsTo(_schema)) ?? false) {
      throw const RivetUnsupportedQueryException(
        'An update predicate can only reference columns from its target table.',
      );
    }
  }

  final RivetTableSchema<Definition, Row> _schema;
  final RivetCompanion<Definition> _companion;
  final RivetPredicate? _predicate;

  RivetUpdate<Definition, Row> prepare() => this;

  Future<int> execute(RivetExecutor executor) => executor.executeAffected(
    _compileUpdate(_schema, _companion, _predicate, returning: false),
  );

  RivetReturningUpdate<Definition, Row> returning() =>
      RivetReturningUpdate(_schema, _companion, _predicate);
}

final class RivetReturningUpdate<Definition, Row> {
  const RivetReturningUpdate(this._schema, this._companion, this._predicate);

  final RivetTableSchema<Definition, Row> _schema;
  final RivetCompanion<Definition> _companion;
  final RivetPredicate? _predicate;

  RivetReturningUpdate<Definition, Row> prepare() => this;

  Future<List<Row>> get(RivetExecutor executor) => executor.execute(
    _compileUpdate(_schema, _companion, _predicate, returning: true),
    _schema.decode,
  );
}

final class RivetDelete<Definition, Row> {
  RivetDelete(
    this._schema, {
    RivetWhere<Definition>? where,
  }) : _predicate = where?.call(_schema.definition) {
    if (_predicate?.columns.any((column) => !column.belongsTo(_schema)) ?? false) {
      throw const RivetUnsupportedQueryException(
        'A delete predicate can only reference columns from its target table.',
      );
    }
  }

  final RivetTableSchema<Definition, Row> _schema;
  final RivetPredicate? _predicate;

  RivetDelete<Definition, Row> prepare() => this;

  Future<int> execute(RivetExecutor executor) =>
      executor.executeAffected(_compileDelete(_schema, _predicate, returning: false));

  RivetReturningDelete<Definition, Row> returning() => RivetReturningDelete(_schema, _predicate);
}

final class RivetReturningDelete<Definition, Row> {
  const RivetReturningDelete(this._schema, this._predicate);

  final RivetTableSchema<Definition, Row> _schema;
  final RivetPredicate? _predicate;

  RivetReturningDelete<Definition, Row> prepare() => this;

  Future<List<Row>> get(RivetExecutor executor) => executor.execute(
    _compileDelete(_schema, _predicate, returning: true),
    _schema.decode,
  );
}

RivetCompiledQuery _compileInsert<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetCompanion<Definition> companion, {
  required bool returning,
  RivetOnConflict<Definition>? onConflict,
}) {
  return _compileInsertMany(
    schema,
    [companion],
    onConflict: onConflict,
    returning: returning,
  );
}

RivetCompiledQuery _compileInsertMany<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  List<RivetCompanion<Definition>> companions, {
  required bool returning,
  RivetOnConflict<Definition>? onConflict,
}) {
  final parameters = <Object?>[];
  final rowsSql = <String>[];
  for (final companion in companions) {
    final supplied = {
      for (final assignment in companion[RivetCompanionKey.assignments])
        assignment.columnName: assignment.value,
    };
    final valuesSql = <String>[];
    for (final column in schema.columns) {
      final value = supplied[column.dartName];
      if (value == null) {
        throw StateError('Generated companion omitted ${column.dartName}.');
      }
      valuesSql.add(_insertValue(schema, column, value, parameters));
    }
    rowsSql.add('(${valuesSql.join(', ')})');
  }
  final columns = schema.columns.map((column) => quoteIdentifier(column.physicalName)).join(', ');
  final sql = StringBuffer(
    'INSERT INTO ${schema.qualifiedName} ($columns) VALUES ${rowsSql.join(', ')}',
  );
  if (onConflict?.call(RivetConflictBuilder._(schema)) case final conflict?) {
    sql.write(_compileConflict(schema, conflict, parameters));
  }
  if (returning) {
    sql.write(_returning(schema));
  }
  return RivetCompiledQuery(sql.toString(), parameters);
}

String _compileConflict<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetConflictAction<Definition> conflict,
  List<Object?> parameters,
) {
  return switch (conflict) {
    _RivetDoNothing(:final columns, :final targetWhere) =>
      ' ON CONFLICT${columns.isEmpty ? '' : ' (${columns.map((column) => quoteIdentifier(column.physicalName)).join(', ')})'}'
          '${targetWhere == null ? '' : ' WHERE ${targetWhere.renderLiterals()}'}'
          ' DO NOTHING',
    _RivetConflictUpdate(
      :final columns,
      :final targetWhere,
      assignments: final companion,
      :final predicate,
    ) =>
      _compileConflictUpdate(
        schema,
        columns,
        targetWhere,
        companion,
        predicate,
        parameters,
      ),
  };
}

String _compileConflictUpdate<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  List<RivetColumn<dynamic>> target,
  RivetPredicate? targetWhere,
  RivetCompanion<Definition> companion,
  RivetPredicate? predicate,
  List<Object?> parameters,
) {
  final assignments = _compileUpdateAssignments(schema, companion, parameters);
  if (assignments.isEmpty) {
    throw RivetEmptyUpdateException(
      'Conflict update ${schema.schemaName}.${schema.tableName} has no assignments.',
    );
  }
  final sql = StringBuffer(
    ' ON CONFLICT (${target.map((column) => quoteIdentifier(column.physicalName)).join(', ')})'
    '${targetWhere == null ? '' : ' WHERE ${targetWhere.renderLiterals()}'}'
    ' DO UPDATE SET ${assignments.join(', ')}',
  );
  if (predicate != null) {
    sql.write(' WHERE ${predicate.renderParameters(startAt: parameters.length + 1)}');
    parameters.addAll(predicate.parameters);
  }
  return sql.toString();
}

String _insertValue<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetColumn<Object?> column,
  RivetValue<Definition, dynamic, dynamic> value,
  List<Object?> parameters,
) {
  switch (value) {
    case RivetPresent(value: final present):
      parameters.add(column.encodeValue(present));
      return '\$${parameters.length}::${column.codec.cast}';
    case RivetExpressionValue(expression: final build):
      final expression = build(schema.definition);
      if (expression.referencesRows) {
        throw const RivetUnsupportedQueryException(
          'An insert expression cannot reference a target-table row.',
        );
      }
      if (expression.columns.any((source) => !source.belongsTo(schema))) {
        throw const RivetUnsupportedQueryException(
          'A mutation expression can only reference its target table.',
        );
      }
      final rendered = expression.renderParameters(startAt: parameters.length + 1);
      parameters.addAll(expression.parameters);
      return rendered;
    case RivetAbsent():
      final hook = column.defaultFn ?? column.onUpdateFn;
      if (hook != null) {
        parameters.add(column.encodeValue(hook()));
        return '\$${parameters.length}::${column.codec.cast}';
      }
      if (column.sqlDefault != null) return 'DEFAULT';
      if (column.codec.acceptsNull) return 'NULL';
      throw RivetMissingValueException(
        table: '${schema.schemaName}.${schema.tableName}',
        column: column.physicalName,
      );
  }
}

RivetCompiledQuery _compileUpdate<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetCompanion<Definition> companion,
  RivetPredicate? predicate, {
  required bool returning,
}) {
  final parameters = <Object?>[];
  final assignments = _compileUpdateAssignments(schema, companion, parameters);
  if (assignments.isEmpty) {
    throw RivetEmptyUpdateException(
      'Update ${schema.schemaName}.${schema.tableName} has no assignments.',
    );
  }
  final sql = StringBuffer(
    'UPDATE ${schema.qualifiedName} SET ${assignments.join(', ')}',
  );
  if (predicate != null) {
    sql.write(
      ' WHERE ${predicate.renderParameters(startAt: parameters.length + 1)}',
    );
    parameters.addAll(predicate.parameters);
  }
  if (returning) {
    sql.write(_returning(schema));
  }
  return RivetCompiledQuery(sql.toString(), parameters);
}

List<String> _compileUpdateAssignments<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetCompanion<Definition> companion,
  List<Object?> parameters,
) {
  final supplied = {
    for (final assignment in companion[RivetCompanionKey.assignments])
      assignment.columnName: assignment.value,
  };
  final assignments = <String>[];
  for (final column in schema.columns) {
    final value = supplied[column.dartName];
    if (value == null) {
      throw StateError('Generated companion omitted ${column.dartName}.');
    }
    final valueSql = _updateValue(schema, column, value, parameters);
    if (valueSql != null) {
      assignments.add('${quoteIdentifier(column.physicalName)} = $valueSql');
    }
  }
  return assignments;
}

String? _updateValue<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetColumn<Object?> column,
  RivetValue<Definition, dynamic, dynamic> value,
  List<Object?> parameters,
) {
  switch (value) {
    case RivetPresent(value: final present):
      parameters.add(column.encodeValue(present));
      return '\$${parameters.length}::${column.codec.cast}';
    case RivetExpressionValue(expression: final build):
      final expression = build(schema.definition);
      if (expression.columns.any((source) => !source.belongsTo(schema))) {
        throw const RivetUnsupportedQueryException(
          'A mutation expression can only reference its target table.',
        );
      }
      final rendered = expression.renderParameters(
        startAt: parameters.length + 1,
      );
      parameters.addAll(expression.parameters);
      return rendered;
    case RivetAbsent():
      final hook = column.onUpdateFn;
      if (hook == null) return null;
      parameters.add(column.encodeValue(hook()));
      return '\$${parameters.length}::${column.codec.cast}';
  }
}

RivetCompiledQuery _compileDelete<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetPredicate? predicate, {
  required bool returning,
}) {
  final sql = StringBuffer('DELETE FROM ${schema.qualifiedName}');
  final parameters = <Object?>[];
  if (predicate != null) {
    sql.write(' WHERE ${predicate.renderParameters()}');
    parameters.addAll(predicate.parameters);
  }
  if (returning) {
    sql.write(_returning(schema));
  }
  return RivetCompiledQuery(sql.toString(), parameters);
}

String _returning<Definition, Row>(RivetTableSchema<Definition, Row> schema) =>
    ' RETURNING ${schema.columns.indexed.map((entry) => '${entry.$2.selectionSql} AS "__rivet_c${entry.$1}"').join(', ')}';

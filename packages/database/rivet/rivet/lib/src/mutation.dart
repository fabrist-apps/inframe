// Mutation plans retain values and callbacks, then compile them at execution time.
// ignore_for_file: avoid_returning_this, public_member_api_docs

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

abstract interface class RivetCompanion<Definition> {
  List<RivetAssignment<Definition>> get assignments;
}

extension RivetInsertAccess<Definition, Row> on RivetTableAccessor<Definition, Row> {
  RivetInsert<Definition, Row> insert(RivetCompanion<Definition> companion) =>
      RivetInsert(buildSchema(), companion);
}

final class RivetInsert<Definition, Row> {
  const RivetInsert(this._schema, this._companion);

  final RivetTableSchema<Definition, Row> _schema;
  final RivetCompanion<Definition> _companion;

  RivetInsert<Definition, Row> prepare() => this;

  Future<int> execute(RivetExecutor executor) =>
      executor.executeAffected(_compileInsert(_schema, _companion, returning: false));

  RivetReturningInsert<Definition, Row> returning() => RivetReturningInsert(_schema, _companion);
}

final class RivetReturningInsert<Definition, Row> {
  const RivetReturningInsert(this._schema, this._companion);

  final RivetTableSchema<Definition, Row> _schema;
  final RivetCompanion<Definition> _companion;

  RivetReturningInsert<Definition, Row> prepare() => this;

  Future<List<Row>> get(RivetExecutor executor) => executor.execute(
    _compileInsert(_schema, _companion, returning: true),
    _schema.decode,
  );
}

RivetCompiledQuery _compileInsert<Definition, Row>(
  RivetTableSchema<Definition, Row> schema,
  RivetCompanion<Definition> companion, {
  required bool returning,
}) {
  final supplied = {
    for (final assignment in companion.assignments) assignment.columnName: assignment.value,
  };
  final parameters = <Object?>[];
  final valueSql = <String>[];
  for (final column in schema.columns) {
    final value = supplied[column.dartName];
    if (value == null) {
      throw StateError('Generated companion omitted ${column.dartName}.');
    }
    valueSql.add(_insertValue(schema, column, value, parameters));
  }
  final columns = schema.columns.map((column) => quoteIdentifier(column.physicalName)).join(', ');
  final sql = StringBuffer(
    'INSERT INTO ${schema.qualifiedName} ($columns) VALUES (${valueSql.join(', ')})',
  );
  if (returning) {
    sql
      ..write(' RETURNING ')
      ..write(
        schema.columns.indexed
            .map((entry) => '${entry.$2.selectionSql} AS "__rivet_c${entry.$1}"')
            .join(', '),
      );
  }
  return RivetCompiledQuery(sql.toString(), parameters);
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

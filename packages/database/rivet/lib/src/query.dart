// Query usage is documented on the plan and terminal entry points and in the package README.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:rivet/src/errors.dart';
import 'package:rivet/src/schema.dart';

const _postgresParameterLimit = 65535;
const int _postgresSqlByteLimit = 1024 * 1024 * 1024;

typedef RivetWhere<Definition> = RivetPredicate Function(Definition table);
typedef RivetOrderBy<Definition> = List<RivetOrder> Function(Definition table);

/// A compiled query plus validated bound values.
final class RivetCompiledQuery {
  const RivetCompiledQuery._(this.sql, this.parameters);

  final String sql;
  final List<Object?> parameters;
}

/// Execution boundary accepted by query terminals.
// The interface keeps query plans independent from database and transaction owners.
// ignore: one_member_abstracts
abstract interface class RivetExecutor {
  Future<List<Row>> execute<Row>(
    RivetCompiledQuery query,
    RivetRowDecoder<Row> decode,
  );
}

extension RivetFindAccess<Definition, Row> on RivetTableAccessor<Definition, Row> {
  /// Creates an immutable root read plan.
  RivetFind<Definition, Row> find({
    RivetWhere<Definition>? where,
    RivetOrderBy<Definition>? orderBy,
    int? limit,
    int? offset,
  }) => RivetFind(
    buildSchema(),
    where: where,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
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
  }) : _predicate = where?.call(_schema.definition),
       _orders = List.unmodifiable(orderBy?.call(_schema.definition) ?? const []),
       _limit = _positiveOrNull(limit, 'limit'),
       _offset = _nonNegativeOrNull(offset, 'offset') {
    if (_predicate?.columns.any((column) => !column.belongsTo(_schema)) ?? false) {
      throw const RivetUnsupportedQueryException(
        'A root predicate can only reference columns from its root table.',
      );
    }
    if (_orders.any((order) => !order.column.belongsTo(_schema))) {
      throw const RivetUnsupportedQueryException(
        'Root ordering can only reference columns from its root table.',
      );
    }
  }

  final RivetTableSchema<Definition, Row> _schema;
  final RivetPredicate? _predicate;
  final List<RivetOrder> _orders;
  final int? _limit;
  final int? _offset;

  Future<List<Row>> get(RivetExecutor executor) => executor.execute(_compile(), _schema.decode);

  Future<Row> getSingle(RivetExecutor executor) async {
    final rows = await executor.execute(_compile(terminalLimit: 2), _schema.decode);
    if (rows.length != 1) {
      throw RivetCardinalityException(expected: 'exactly one', actual: rows.length);
    }
    return rows.single;
  }

  Future<Row?> getSingleOrNull(RivetExecutor executor) async {
    final rows = await executor.execute(_compile(terminalLimit: 2), _schema.decode);
    if (rows.length > 1) {
      throw RivetCardinalityException(expected: 'zero or one', actual: rows.length);
    }
    return rows.firstOrNull;
  }

  Future<Row?> getFirstOrNull(RivetExecutor executor) async {
    final rows = await executor.execute(_compile(terminalLimit: 1), _schema.decode);
    return rows.firstOrNull;
  }

  RivetCompiledQuery _compile({int? terminalLimit}) {
    if ((_predicate?.parameters.length ?? 0) > _postgresParameterLimit) {
      throw const RivetUnsupportedQueryException(
        'PostgreSQL supports at most 65535 bound parameters.',
      );
    }
    final columns = _schema.columns.indexed
        .map((entry) => '${entry.$2.selectionSql} AS "__rivet_c${entry.$1}"')
        .join(', ');
    final sql = StringBuffer('SELECT $columns FROM ${_schema.qualifiedName}');
    final parameters = <Object?>[];
    if (_predicate case final predicate?) {
      parameters.addAll(predicate.parameters);
      sql.write(' WHERE ${predicate.renderParameters()}');
    }
    if (_orders.isNotEmpty) {
      sql
        ..write(' ORDER BY ')
        ..write(
          _orders
              .map((order) {
                final direction = order.descending ? 'DESC' : 'ASC';
                final nulls = order.nulls == NullsOrder.first ? 'FIRST' : 'LAST';
                return '${order.column.sql} $direction NULLS $nulls';
              })
              .join(', '),
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
    final rendered = sql.toString();
    if (utf8.encode(rendered).length > _postgresSqlByteLimit) {
      throw const RivetUnsupportedQueryException(
        'The compiled PostgreSQL statement exceeds the supported SQL size.',
      );
    }
    return RivetCompiledQuery._(rendered, List.unmodifiable(parameters));
  }
}

int? _positiveOrNull(int? value, String name) {
  if (value != null && value <= 0) throw ArgumentError.value(value, name, 'must be positive');
  return value;
}

int? _nonNegativeOrNull(int? value, String name) {
  if (value != null && value < 0) throw ArgumentError.value(value, name, 'must not be negative');
  return value;
}

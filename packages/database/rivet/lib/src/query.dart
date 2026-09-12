import 'schema.dart';

typedef RivetWhere<Definition> = RivetPredicate Function(Definition table);
typedef RivetOrderBy<Definition> = List<RivetOrder> Function(Definition table);

/// A compiled query plus validated bound values.
final class RivetCompiledQuery {
  const RivetCompiledQuery(this.sql, this.parameters);

  final String sql;
  final List<Object?> parameters;
}

/// Execution boundary accepted by query terminals.
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
       _orders = orderBy?.call(_schema.definition) ?? const [],
       _limit = _positiveOrNull(limit, 'limit'),
       _offset = _nonNegativeOrNull(offset, 'offset');

  final RivetTableSchema<Definition, Row> _schema;
  final RivetPredicate? _predicate;
  final List<RivetOrder> _orders;
  final int? _limit;
  final int? _offset;

  Future<List<Row>> get(RivetExecutor executor) => executor.execute(_compile(), _schema.decode);

  RivetCompiledQuery _compile({int? terminalLimit}) {
    final columns = _schema.columns.map((column) => column.sql).join(', ');
    final sql = StringBuffer('SELECT $columns FROM ${_schema.qualifiedName}');
    final parameters = <Object?>[];
    if (_predicate case final predicate?) {
      var predicateSql = predicate.sql;
      for (final value in predicate.parameters) {
        parameters.add(value);
        predicateSql = predicateSql.replaceFirst('@value', '\$${parameters.length}');
      }
      sql.write(' WHERE $predicateSql');
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
    return RivetCompiledQuery(sql.toString(), List.unmodifiable(parameters));
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

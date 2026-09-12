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
}

final class RivetManyRelation<Target> extends RivetRelationDescriptor<Target> {
  RivetManyRelation(
    Type targetTable, {
    super.through,
    RivetRelationDescriptor<dynamic> Function(Target table)? relation,
  }) : super(
         kind: through == null ? RivetRelationKind.many : RivetRelationKind.manyThrough,
         targetTable: targetTable,
         inverse: relation,
       );
}

final class RivetRelationBuilder<Target, RelationType extends RivetRelationDescriptor<Target>> {
  const RivetRelationBuilder(this.descriptor);

  final RelationType descriptor;

  RelationType call() => descriptor;
}

final class RivetInclude<Definition, Row> {
  RivetInclude({
    required this.name,
    required this.path,
    required this.relation,
    required this.targetSchema,
    RivetWhere<Definition>? where,
    RivetOrderBy<Definition>? orderBy,
    this.limit,
    List<RivetInclude<dynamic, dynamic>> includes = const [],
  }) : predicate = where?.call(targetSchema.definition),
       orders = List.unmodifiable(orderBy?.call(targetSchema.definition) ?? const []),
       includes = List.unmodifiable(includes) {
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
    if (orders.any((order) => !order.column.belongsTo(targetSchema))) {
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
    final decoded = [for (final row in rows) _decodeRow(row)];
    return relation.kind == RivetRelationKind.one
        ? Relation<dynamic>.loaded(decoded.firstOrNull)
        : Relation<dynamic>.loaded(List<Object?>.unmodifiable(decoded));
  }

  Object? _decodeRow(Object? encoded) {
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

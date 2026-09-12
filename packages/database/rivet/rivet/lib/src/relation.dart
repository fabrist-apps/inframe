// Relation state and metadata contracts are documented on their public root types.
// ignore_for_file: public_member_api_docs

import 'package:rivet/src/schema.dart';

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

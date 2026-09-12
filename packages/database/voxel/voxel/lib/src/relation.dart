// Relation state and metadata contracts are documented on their public root types.
// ignore_for_file: public_member_api_docs

import 'package:voxel/src/schema.dart';

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

enum VoxelRelationKind { one, many, manyThrough }

/// Runtime metadata for a relation declaration. It never creates a foreign key.
final class VoxelRelationDescriptor<Target> {
  VoxelRelationDescriptor({
    required this.kind,
    required this.targetTable,
    this.through,
    this.fields = const [],
    this.reference,
    this.inverse,
    this.source,
    this.target,
  });

  final VoxelRelationKind kind;
  final Type? through;
  final Type targetTable;
  final List<VoxelColumn<dynamic>> fields;
  final List<VoxelColumn<dynamic>> Function(Target table)? reference;
  final VoxelRelationDescriptor<dynamic> Function(Target table)? inverse;
  final VoxelRelationDescriptor<dynamic> Function(Object table)? source;
  final VoxelRelationDescriptor<dynamic> Function(Object table)? target;
  List<VoxelColumn<dynamic>> references = const [];
  VoxelRelationDescriptor<dynamic>? inverseRelation;

  void resolve(Target definition) {
    references = List.unmodifiable(reference?.call(definition) ?? const []);
    inverseRelation = inverse?.call(definition);
  }
}

final class VoxelOneRelation<Target> extends VoxelRelationDescriptor<Target> {
  VoxelOneRelation(
    Type targetTable, {
    required super.fields,
    required List<VoxelColumn<dynamic>> Function(Target table) references,
  }) : super(
         kind: VoxelRelationKind.one,
         targetTable: targetTable,
         reference: references,
       );
}

final class VoxelManyRelation<Target> extends VoxelRelationDescriptor<Target> {
  VoxelManyRelation(
    Type targetTable, {
    super.through,
    VoxelRelationDescriptor<dynamic> Function(Target table)? relation,
    super.source,
    super.target,
  }) : super(
         kind: through == null ? VoxelRelationKind.many : VoxelRelationKind.manyThrough,
         targetTable: targetTable,
         inverse: relation,
       );
}

final class VoxelRelationBuilder<Target, RelationType extends VoxelRelationDescriptor<Target>> {
  const VoxelRelationBuilder(this.descriptor);

  final RelationType descriptor;

  RelationType call() => descriptor;
}

/// Builds a direct or junction-backed many relation.
final class VoxelManyRelationBuilder<Target> {
  const VoxelManyRelationBuilder(this.descriptor);

  final VoxelManyRelation<Target> descriptor;

  VoxelManyRelation<Target> call() => descriptor;

  VoxelRelationBuilder<Target, VoxelManyRelation<Target>> through<Through>({
    required VoxelRelationDescriptor<dynamic> Function(Through table) source,
    required VoxelRelationDescriptor<dynamic> Function(Through table) target,
  }) => VoxelRelationBuilder(
    VoxelManyRelation<Target>(
      descriptor.targetTable,
      through: Through,
      source: (table) => source(table as Through),
      target: (table) => target(table as Through),
    ),
  );
}

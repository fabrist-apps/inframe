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
  const RivetRelationDescriptor({required this.kind, this.through});

  final RivetRelationKind kind;
  final Type? through;
}

final class RivetOneRelation<Target> extends RivetRelationDescriptor<Target> {
  const RivetOneRelation() : super(kind: RivetRelationKind.one);
}

final class RivetManyRelation<Target> extends RivetRelationDescriptor<Target> {
  const RivetManyRelation({super.through})
    : super(kind: through == null ? RivetRelationKind.many : RivetRelationKind.manyThrough);
}

final class RivetRelationBuilder<Target, RelationType extends RivetRelationDescriptor<Target>> {
  const RivetRelationBuilder(this.descriptor);

  final RelationType descriptor;

  RelationType call() => descriptor;
}

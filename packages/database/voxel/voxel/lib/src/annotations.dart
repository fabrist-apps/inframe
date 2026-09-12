// Public usage is documented in the package README; these fields mirror the declaration syntax.
// ignore_for_file: public_member_api_docs

/// Marks a table declaration for Voxel generation.
final class VoxelTable {
  const VoxelTable({this.name, this.schema, this.renamedFrom, this.rowName});

  final String? name;
  final String? schema;
  final String? renamedFrom;
  final String? rowName;
}

/// Marks an application database declaration for Voxel generation.
final class VoxelDatabase {
  const VoxelDatabase({required this.name, required this.tables});

  final String name;
  final List<Type> tables;
}

/// Marks a Turso enum declaration for Voxel generation.
final class VoxelEnum {
  const VoxelEnum({this.name, this.schema, this.renamedFrom});

  final String? name;
  final String? schema;
  final String? renamedFrom;
}

/// Overrides the stored label and rename hint for an enum value.
final class VoxelEnumValue {
  const VoxelEnumValue({this.name, this.renamedFrom});

  final String? name;
  final String? renamedFrom;
}

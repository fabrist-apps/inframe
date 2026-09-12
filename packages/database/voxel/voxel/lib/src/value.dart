import 'package:voxel/src/schema.dart';

// Generated companions expose these small protocol types directly.
// ignore_for_file: one_member_abstracts, public_member_api_docs

/// A value supplied to a generated Voxel companion.
sealed class VoxelValue<Definition, Domain, Storage> {
  const VoxelValue();

  const factory VoxelValue.present(Domain value) = VoxelPresent<Definition, Domain, Storage>;
  const factory VoxelValue.absent() = VoxelAbsent<Definition, Domain, Storage>;
  const factory VoxelValue.expression(
    VoxelExpression<Storage> Function(Definition table) expression,
  ) = VoxelExpressionValue<Definition, Domain, Storage>;
}

final class VoxelPresent<Definition, Domain, Storage>
    extends VoxelValue<Definition, Domain, Storage> {
  const VoxelPresent(this.value);

  final Domain value;
}

final class VoxelAbsent<Definition, Domain, Storage>
    extends VoxelValue<Definition, Domain, Storage> {
  const VoxelAbsent();
}

final class VoxelExpressionValue<Definition, Domain, Storage>
    extends VoxelValue<Definition, Domain, Storage> {
  const VoxelExpressionValue(this.expression);

  final VoxelExpression<Storage> Function(Definition table) expression;
}

final class VoxelAssignment<Definition> {
  const VoxelAssignment(this.columnName, this.value);

  final String columnName;
  final VoxelValue<Definition, dynamic, dynamic> value;
}

enum VoxelCompanionKey { assignments }

abstract interface class VoxelCompanion<Definition> {
  List<VoxelAssignment<Definition>> operator [](VoxelCompanionKey key);
}

import 'package:test/test.dart';
import 'package:voxel/voxel.dart';

import 'generated_consumer.dart';

void main() {
  test('rejects missing and cross-schema foreign-key targets', () {
    final source = CrossSchemaSources.db.buildSchema() as VoxelTableSchema<Object?, Object?>;
    final target = ExternalTargets.db.buildSchema() as VoxelTableSchema<Object?, Object?>;

    expect(() => VoxelDatabaseSchema(name: 'missing', tables: [source]), throwsArgumentError);
    expect(
      () => VoxelDatabaseSchema(name: 'cross_schema', tables: [source, target]),
      throwsArgumentError,
    );
  });

  test('rejects colliding physical table names', () {
    final first = Users.db.buildSchema() as VoxelTableSchema<Object?, Object?>;
    final column = VoxelColumn<String>(VoxelTextCodec());
    final second = VoxelTableSchema<Object?, Object?>(
      schemaName: first.schemaName,
      tableName: first.tableName,
      definition: Object(),
      definitionType: Object,
      rowType: Object,
      columns: [column as VoxelColumn<Object?>],
      columnNames: const ['value'],
      decode: (_, _) => Object(),
    );
    expect(
      () => VoxelDatabaseSchema(name: 'collision', tables: [first, second]),
      throwsArgumentError,
    );
  });
}

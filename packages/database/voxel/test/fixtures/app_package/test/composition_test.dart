import 'package:test/test.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/posts.dart';
import 'package:voxel_fixture_schema/authors.dart' as schema;

void main() {
  test('composes public metadata from independently generated packages', () {
    final database = FixtureAppDatabase().schema;
    expect(database.name, 'fixture_app');
    expect(database.formatVersion, 1);
    expect(database.tables, hasLength(4));
    final authors = database.tables.singleWhere((table) => table.definition is schema.Authors);
    expect(authors.indexes.single.name, 'authors_name');
    expect(authors.constraints.single.name, 'authors_name_present');
    final posts = database.tables.singleWhere((table) => table.definition is Posts);
    expect(posts.definitionType, Posts);
    expect(posts.rowType, PostsRow);
    final author = posts.relations['author']!;
    expect(author.targetTable, schema.Authors);
    expect(author.references.single.physicalName, 'id');
    expect(
      posts.columns
          .singleWhere((column) => column.dartName == 'authorID')
          .foreignKey
          ?.referencedColumn
          ?.physicalName,
      'id',
    );
    expect(posts.relations['tags']?.kind, VoxelRelationKind.manyThrough);
  });

  test('rejects duplicate and reserved table registrations', () {
    final authors = schema.Authors.db.buildSchema() as VoxelTableSchema<Object?, Object?>;
    expect(
      () => VoxelDatabaseSchema(name: 'duplicate', tables: [authors, authors]),
      throwsArgumentError,
    );
    expect(
      () => VoxelDatabaseSchema(
        name: 'reserved',
        tables: [
          VoxelTableSchema<Object?, Object?>(
            schemaName: 'main',
            tableName: '_voxel_phases',
            definition: Object(),
            columns: const [],
            columnNames: const [],
            decode: (_, _) => Object(),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}

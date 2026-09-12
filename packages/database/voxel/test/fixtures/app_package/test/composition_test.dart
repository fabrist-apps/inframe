import 'package:test/test.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/posts.dart';
import 'package:voxel_fixture_schema/authors.dart' as schema;

final class _FirstDefinition {}

final class _SecondDefinition {}

void main() {
  test('composes public metadata from independently generated packages', () {
    final database = FixtureAppDatabase().schema;
    expect(database.name, 'fixture_app');
    expect(database.formatVersion, 1);
    expect(database.tables, hasLength(6));
    final authors = database.tables.singleWhere((table) => table.definition is schema.Authors);
    expect(authors.indexes.single.name, 'authors_name');
    expect(authors.indexes.single.predicate, isNotNull);
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
    final translations = database.tables.singleWhere(
      (table) => table.definition is Translations,
    );
    final foreignKey = translations.constraints.single;
    expect(foreignKey.columns.map((column) => column.physicalName), ['language', 'key']);
    expect(foreignKey.referencedColumns.map((column) => column.physicalName), [
      'language',
      'key',
    ]);
    expect(foreignKey.onDelete, VoxelReferentialAction.cascade);
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
            tableName: '_VOXEL_PHASES',
            definition: Object(),
            definitionType: Object,
            rowType: Object,
            columns: [VoxelColumn(VoxelTextCodec())],
            columnNames: const ['value'],
            decode: (_, _) => Object(),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('rejects unsupported, empty, and case-colliding physical metadata', () {
    expect(
      () => _schema(_FirstDefinition(), tableName: 'values', formatVersion: 99),
      throwsArgumentError,
    );
    expect(() => _schema(_FirstDefinition(), tableName: ''), throwsArgumentError);
    expect(
      () => VoxelTableSchema<_FirstDefinition, Object?>(
        schemaName: 'main',
        tableName: 'duplicateColumns',
        definition: _FirstDefinition(),
        definitionType: _FirstDefinition,
        rowType: Object,
        columns: [
          VoxelColumn<String>(VoxelTextCodec()) as VoxelColumn<Object?>,
          VoxelColumn<String>(VoxelTextCodec()) as VoxelColumn<Object?>,
        ],
        columnNames: const ['value', 'Value'],
        decode: (_, _) => Object(),
      ),
      throwsArgumentError,
    );
    expect(
      () => VoxelDatabaseSchema(
        name: 'case_collision',
        tables: [
          _schema(_FirstDefinition(), tableName: 'users'),
          _schema(_SecondDefinition(), tableName: 'Users'),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => VoxelDatabaseSchema(
        name: 'index_collision',
        tables: [
          _schema(_FirstDefinition(), tableName: 'first', indexName: 'shared'),
          _schema(_SecondDefinition(), tableName: 'second', indexName: 'SHARED'),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => VoxelDatabaseSchema(
        name: 'table_index_collision',
        tables: [
          _schema(_FirstDefinition(), tableName: 'posts'),
          _schema(_SecondDefinition(), tableName: 'users', indexName: 'POSTS'),
        ],
      ),
      throwsArgumentError,
    );
  });
}

VoxelTableSchema<Object?, Object?> _schema(
  Object definition, {
  required String tableName,
  int formatVersion = 1,
  String? indexName,
}) {
  final column = VoxelOrderableColumn<String>(VoxelTextCodec());
  return VoxelTableSchema<Object?, Object?>(
    schemaName: 'main',
    tableName: tableName,
    formatVersion: formatVersion,
    definition: definition,
    definitionType: definition.runtimeType,
    rowType: Object,
    columns: [column as VoxelColumn<Object?>],
    columnNames: const ['value'],
    decode: (_, _) => Object(),
    indexes: indexName == null
        ? null
        : () => [
            VoxelIndexBuilder(indexName, unique: false).on([column]),
          ],
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_generator/voxel_generator.dart';

// Fixture maps spell out optional migration metadata for readability.
// ignore_for_file: use_null_aware_elements

void main() {
  group('Voxel generated migration', () {
    test('should create and round-trip an imported table through Turso', () async {
      final directory = Directory.systemTemp.createTempSync('voxel_sql_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final migrationId = await const VoxelMigrationGenerator().generate(
        schema: VoxelDatabaseSchema(
          name: 'accounts',
          tables: [ImportedUsers.db.buildSchema()],
        ),
        directory: directory,
        name: 'create users',
      );
      final journal = jsonDecode(
        File('${directory.path}/journal.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
      final sql = File(
        '${directory.path}/${entry['directory']}/migration.sql',
      ).readAsStringSync();

      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS auth");
      await database.execute(sql);
      await database.execute(
        'INSERT INTO auth.users (id, name) VALUES (?, ?)',
        parameters: [1, 'Ada'],
      );
      final row = (await database.query('SELECT id, name FROM auth.users')).rows.single;

      expect(migrationId, isNotNull);
      expect(row.getInt('id'), 1);
      expect(row.getString('name'), 'Ada');
    });

    test('should apply an added column and declared renames without replacing rows', () async {
      final directory = Directory.systemTemp.createTempSync('voxel_diff_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      await generator.generateDeclaration(
        declaration: _physicalDeclaration('users', ['id', 'name']),
        directory: directory,
        name: 'initial',
      );

      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS auth");
      await _executeMigration(database, _migrationSql(directory));
      await database.execute("INSERT INTO auth.users VALUES (1, 'Ada')");

      await generator.generateDeclaration(
        declaration: _physicalDeclaration(
          'members',
          ['id', 'displayName', 'nickname'],
          tableRenamedFrom: 'users',
          columnRenamedFrom: {'displayName': 'name'},
          nullable: {'nickname'},
        ),
        directory: directory,
        name: 'rename users',
      );
      await _executeMigration(database, _migrationSql(directory));
      final row = (await database.query(
        'SELECT id, displayName, nickname FROM auth.members',
      )).rows.single;

      expect(row.getInt('id'), 1);
      expect(row.getString('displayName'), 'Ada');
      expect(row.value('nickname'), isNull);
    });
  });
}

Map<String, Object?> _physicalDeclaration(
  String table,
  List<String> columns, {
  String? tableRenamedFrom,
  Map<String, String> columnRenamedFrom = const {},
  Set<String> nullable = const {},
}) => {
  'formatVersion': 1,
  'dialect': 'voxel',
  'name': 'accounts',
  'tables': [
    {
      'schema': 'auth',
      'name': table,
      if (tableRenamedFrom != null) 'renamedFrom': tableRenamedFrom,
      'columns': [
        for (final column in columns)
          {
            'name': column,
            if (columnRenamedFrom[column] case final previous?) 'renamedFrom': previous,
            'storage': {
              'kind': column == 'id' ? 'integer' : 'text',
              'nullable': nullable.contains(column),
              'codecVersion': 1,
            },
            'primaryKey': column == 'id',
          },
      ],
      'indexes': <Object?>[],
      'constraints': <Object?>[],
    },
  ],
  'enums': <Object?>[],
  'requirements': <Object?>[],
};

String _migrationSql(Directory directory) {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  return File('${directory.path}/${entry['directory']}/migration.sql').readAsStringSync();
}

Future<void> _executeMigration(TursoDatabase database, String sql) async {
  for (final statement in sql.split(';')) {
    if (statement.trim().isNotEmpty) await database.execute('$statement;');
  }
}

final class ImportedUsers extends VoxelTableDefinition<ImportedUsers> {
  static const db = _ImportedUsersAccessor();

  late final VoxelOrderableColumn<int> id = integer().primaryKey()();
  late final VoxelOrderableColumn<String> name = text()();
}

final class _ImportedUsersAccessor extends VoxelTableAccessor<ImportedUsers, Object> {
  const _ImportedUsersAccessor();

  @override
  VoxelTableSchema<ImportedUsers, Object> buildSchema() {
    final definition = ImportedUsers();
    return VoxelTableSchema(
      schemaName: 'auth',
      tableName: 'users',
      definition: definition,
      columns: [definition.id, definition.name],
      columnNames: const ['id', 'name'],
      decode: (_, _) => Object(),
      definitionType: ImportedUsers,
      rowType: Object,
    );
  }
}

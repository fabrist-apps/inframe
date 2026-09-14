import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_generator/voxel_generator.dart';

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
  });
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

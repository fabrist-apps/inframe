import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_generator/voxel_generator.dart';

void main() {
  group('VoxelMigrationGenerator', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('voxel_migration_test_');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    test('should publish an initial migration with ordered artifacts', () async {
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final migrationId = await generator.generate(
        schema: VoxelDatabaseSchema(
          name: 'accounts',
          tables: [Users.db.buildSchema()],
        ),
        directory: directory,
        name: 'create users',
      );

      expect(migrationId, '00000000000000000000000000000006');
      final journal = jsonDecode(
        File('${directory.path}/journal.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
      final migrationDirectory = Directory('${directory.path}/${entry['directory']}');

      expect(journal, containsPair('databaseId', '00000000000000000000000000000001'));
      expect(migrationDirectory.listSync().map((file) => file.path.split('/').last), {
        'migration.sql',
        'snapshot.json',
        'migration.json',
      });
      expect(
        File('${migrationDirectory.path}/migration.sql').readAsStringSync(),
        'CREATE TABLE "auth"."users" (\n'
        '  "id" INTEGER NOT NULL PRIMARY KEY,\n'
        '  "name" TEXT NOT NULL\n'
        ');\n',
      );
      final migration = jsonDecode(
        File('${migrationDirectory.path}/migration.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(migration['id'], migrationId);
      expect(migration['parentId'], isNull);
      expect(migration['checksum'], entry['checksum']);
      expect(migration['phases']! as List<Object?>, hasLength(1));
    });
  });
}

@VoxelTable(schema: 'auth', name: 'users')
final class Users extends VoxelTableDefinition<Users> {
  static const db = _UsersAccessor();

  late final VoxelOrderableColumn<int> id = integer().primaryKey()();
  late final VoxelOrderableColumn<String> name = text()();
}

final class _UsersAccessor extends VoxelTableAccessor<Users, Object> {
  const _UsersAccessor();

  @override
  VoxelTableSchema<Users, Object> buildSchema() {
    final definition = Users();
    return VoxelTableSchema(
      schemaName: 'auth',
      tableName: 'users',
      definition: definition,
      columns: [definition.id, definition.name],
      columnNames: const ['id', 'name'],
      decode: (_, _) => Object(),
      definitionType: Users,
      rowType: Object,
    );
  }
}

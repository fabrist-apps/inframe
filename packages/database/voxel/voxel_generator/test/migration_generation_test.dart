import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_generator/voxel_generator.dart';

// Fixture maps spell out optional migration metadata for readability.
// ignore_for_file: use_null_aware_elements

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

      expect(migrationId, '00000000000000000000000000000007');
      final journal = jsonDecode(
        File('${directory.path}/journal.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
      final migrationDirectory = Directory(
        '${directory.path}/${entry['directory']}',
      );

      expect(journal, containsPair('databaseId', '00000000000000000000000000000001'));
      expect(migrationDirectory.listSync().map((file) => file.path.split('/').last), {
        'migration.sql',
        'snapshot.json',
        'migration.json',
      });
      expect(
        File('${migrationDirectory.path}/migration.sql').readAsStringSync(),
        'CREATE TABLE "auth"."users" (\n'
        '  "id" INTEGER NOT NULL,\n'
        '  "name" TEXT NOT NULL,\n'
        '  CONSTRAINT "users_pkey" PRIMARY KEY ("id")\n'
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

    test('should reject a covered SQL edit during offline checking', () async {
      var nextId = 0;
      final schema = VoxelDatabaseSchema(
        name: 'accounts',
        tables: [Users.db.buildSchema()],
      );
      await VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      ).generate(schema: schema, directory: directory, name: 'create users');

      await const VoxelMigrationChecker().check(
        directory: directory,
        schema: schema,
      );
      final journal = jsonDecode(
        File('${directory.path}/journal.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
      final sql = File('${directory.path}/${entry['directory']}/migration.sql');
      sql.writeAsStringSync('${sql.readAsStringSync()}-- reviewed\n');

      await expectLater(
        const VoxelMigrationChecker().check(directory: directory),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject duplicate JSON keys before interpreting a journal', () async {
      File('${directory.path}/journal.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"formatVersion":1,"formatVersion":1,"dialect":"voxel",'
          '"databaseId":"00000000000000000000000000000001","entries":[]}',
        );

      await expectLater(
        const VoxelMigrationChecker().check(directory: directory),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate JSON key `formatVersion`'),
          ),
        ),
      );
    });

    test('should reject a current composed schema mismatch', () async {
      var nextId = 0;
      await VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      ).generate(
        schema: VoxelDatabaseSchema(
          name: 'accounts',
          tables: [Users.db.buildSchema()],
        ),
        directory: directory,
        name: 'create users',
      );

      await expectLater(
        const VoxelMigrationChecker().check(
          directory: directory,
          schema: VoxelDatabaseSchema(
            name: 'accounts',
            tables: [RenamedUsers.db.buildSchema()],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should ignore JSON formatting and key order in checksums', () async {
      var nextId = 0;
      await VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      ).generate(
        schema: VoxelDatabaseSchema(
          name: 'accounts',
          tables: [Users.db.buildSchema()],
        ),
        directory: directory,
        name: 'create users',
      );
      final journal = jsonDecode(
        File('${directory.path}/journal.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
      final snapshotFile = File(
        '${directory.path}/${entry['directory']}/snapshot.json',
      );
      final snapshot = jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>;
      snapshotFile.writeAsStringSync(
        jsonEncode(Map.fromEntries(snapshot.entries.toList().reversed)),
      );

      await const VoxelMigrationChecker().check(directory: directory);
    });

    test('should append ordinary changes and preserve renamed identities', () async {
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      await generator.generateDeclaration(
        declaration: _declaration(table: 'users', columns: ['id', 'name']),
        directory: directory,
        name: 'create users',
      );
      final first = _finalSnapshot(directory);
      final firstTable = (first['tables']! as List<Object?>).single! as Map<String, Object?>;
      final firstColumns = (firstTable['columns']! as List<Object?>).cast<Map<String, Object?>>();

      final migrationId = await generator.generateDeclaration(
        declaration: _declaration(
          table: 'members',
          tableRenamedFrom: 'users',
          columns: ['id', 'displayName', 'nickname'],
          columnRenames: {'displayName': 'name'},
          nullable: {'nickname'},
        ),
        directory: directory,
        name: 'rename users',
      );
      final second = _finalSnapshot(directory);
      final secondTable = (second['tables']! as List<Object?>).single! as Map<String, Object?>;
      final secondColumns = (secondTable['columns']! as List<Object?>).cast<Map<String, Object?>>();
      final sql = _finalSql(directory);

      expect(migrationId, isNotNull);
      expect(secondTable['id'], firstTable['id']);
      expect(
        secondColumns.firstWhere((column) => column['name'] == 'displayName')['id'],
        firstColumns.firstWhere((column) => column['name'] == 'name')['id'],
      );
      expect(sql, contains('ALTER TABLE "auth"."users" RENAME TO "members";'));
      expect(sql, contains('RENAME COLUMN "name" TO "displayName";'));
      expect(sql, contains('ADD COLUMN "nickname" TEXT;'));
      expect(
        (jsonDecode(File('${directory.path}/journal.json').readAsStringSync())
                as Map<String, Object?>)['entries']!
            as List<Object?>,
        hasLength(2),
      );
    });

    test('should emit no migration for runtime-only declaration changes', () async {
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final declaration = _declaration(table: 'users', columns: ['id', 'name']);
      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'create users',
      );

      expect(
        await generator.generateDeclaration(
          declaration: {...declaration, 'rowName': 'Account'},
          directory: directory,
          name: 'runtime only',
        ),
        isNull,
      );
    });

    test('should generate indexes, checks and same-schema foreign keys', () async {
      var nextId = 0;
      await VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      ).generate(
        schema: VoxelDatabaseSchema(
          name: 'content',
          tables: [Parents.db.buildSchema(), Children.db.buildSchema()],
        ),
        directory: directory,
        name: 'create constrained tables',
      );

      final sql = _finalSql(directory);
      expect(sql, contains('CHECK'));
      expect(sql, contains('REFERENCES "parents" ("id")'));
      expect(sql, contains('CREATE UNIQUE INDEX "content"."parent_name_unique"'));
      expect(sql, contains('WHERE NOT (("name" = \'\'))'));
    });
  });
}

Map<String, Object?> _declaration({
  required String table,
  required List<String> columns,
  String? tableRenamedFrom,
  Map<String, String> columnRenames = const {},
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
            if (columnRenames[column] case final previous?) 'renamedFrom': previous,
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

Map<String, Object?> _finalSnapshot(Directory directory) {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  return jsonDecode(
    File('${directory.path}/${entry['directory']}/snapshot.json').readAsStringSync(),
  ) as Map<String, Object?>;
}

String _finalSql(Directory directory) {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  return File('${directory.path}/${entry['directory']}/migration.sql').readAsStringSync();
}

final class Parents extends VoxelTableDefinition<Parents> {
  static const db = _ParentsAccessor();

  late final VoxelOrderableColumn<int> id = integer().primaryKey()();
  late final VoxelOrderableColumn<String> name = text()();
  late final List<VoxelIndex> indexes = [
    uniqueIndex('parent_name_unique').on([name]).where(~name.equals('')),
  ];
  late final List<VoxelConstraint> constraints = [
    check('parent_name_check', ~name.equals('')),
  ];
}

final class Children extends VoxelTableDefinition<Children> {
  static const db = _ChildrenAccessor();

  late final VoxelOrderableColumn<int> id = integer().primaryKey()();
  late final VoxelOrderableColumn<int> parentId = integer().references<Parents>(
    (parent) => parent.id,
  )();
}

final class _ParentsAccessor extends VoxelTableAccessor<Parents, Object> {
  const _ParentsAccessor();

  @override
  VoxelTableSchema<Parents, Object> buildSchema() {
    final definition = Parents();
    return VoxelTableSchema(
      schemaName: 'content',
      tableName: 'parents',
      definition: definition,
      columns: [definition.id, definition.name],
      columnNames: const ['id', 'name'],
      decode: (_, _) => Object(),
      definitionType: Parents,
      rowType: Object,
      indexes: () => definition.indexes,
      constraints: () => definition.constraints,
    );
  }
}

final class _ChildrenAccessor extends VoxelTableAccessor<Children, Object> {
  const _ChildrenAccessor();

  @override
  VoxelTableSchema<Children, Object> buildSchema() {
    final definition = Children();
    return VoxelTableSchema(
      schemaName: 'content',
      tableName: 'children',
      definition: definition,
      columns: [definition.id, definition.parentId],
      columnNames: const ['id', 'parentId'],
      decode: (_, _) => Object(),
      definitionType: Children,
      rowType: Object,
    );
  }
}

@VoxelTable(schema: 'auth', name: 'renamedUsers')
final class RenamedUsers extends VoxelTableDefinition<RenamedUsers> {
  static const db = _RenamedUsersAccessor();

  late final VoxelOrderableColumn<int> id = integer().primaryKey()();
  late final VoxelOrderableColumn<String> name = text()();
}

final class _RenamedUsersAccessor extends VoxelTableAccessor<RenamedUsers, Object> {
  const _RenamedUsersAccessor();

  @override
  VoxelTableSchema<RenamedUsers, Object> buildSchema() {
    final definition = RenamedUsers();
    return VoxelTableSchema(
      schemaName: 'auth',
      tableName: 'renamedUsers',
      definition: definition,
      columns: [definition.id, definition.name],
      columnNames: const ['id', 'name'],
      decode: (_, _) => Object(),
      definitionType: RenamedUsers,
      rowType: Object,
    );
  }
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

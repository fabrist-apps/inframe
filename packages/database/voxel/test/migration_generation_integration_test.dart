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

    test('should enforce generated indexes, checks and foreign keys', () async {
      final directory = Directory.systemTemp.createTempSync('voxel_constraints_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      await const VoxelMigrationGenerator().generateDeclaration(
        declaration: _constrainedDeclaration(),
        directory: directory,
        name: 'constraints',
      );

      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS content");
      await _executeMigration(database, _migrationSql(directory));
      await database.execute('PRAGMA foreign_keys=ON');
      await database.execute("INSERT INTO content.parents VALUES (1, 'Ada')");
      await database.execute('INSERT INTO content.children VALUES (1, 1)');

      await expectLater(
        database.execute("INSERT INTO content.parents VALUES (2, 'Ada')"),
        throwsA(isA<TursoDatabaseException>()),
      );
      await expectLater(
        database.execute("INSERT INTO content.parents VALUES (2, '')"),
        throwsA(isA<TursoDatabaseException>()),
      );
      await expectLater(
        database.execute('INSERT INTO content.children VALUES (2, 99)'),
        throwsA(isA<TursoDatabaseException>()),
      );
    });

    test('should rebuild transactionally and validate incoming foreign keys', () async {
      final directory = Directory.systemTemp.createTempSync('voxel_rebuild_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      await generator.generateDeclaration(
        declaration: _constrainedDeclaration(),
        directory: directory,
        name: 'constraints',
      );

      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS content");
      await _executeMigration(database, _migrationSql(directory));
      await database.execute("INSERT INTO content.parents VALUES (1, '42')");
      await database.execute('INSERT INTO content.children VALUES (1, 1)');

      final changed = _constrainedDeclaration();
      final parents = (changed['tables']! as List<Object?>).first! as Map<String, Object?>;
      final name = (parents['columns']! as List<Object?>).last! as Map<String, Object?>;
      name['storage'] = {'kind': 'integer', 'nullable': false, 'codecVersion': 1};
      await generator.generateDeclaration(
        declaration: changed,
        directory: directory,
        name: 'convert parent name',
        storageTransforms: {
          'content.parents.name': 'CAST("name" AS INTEGER)',
        },
      );
      await const VoxelMigrationChecker().check(directory: directory);
      await _executeLatestGeneratedMigration(database, directory);

      final parent = (await database.query(
        'SELECT name, typeof(name) AS storage FROM content.parents',
      )).rows.single;
      expect(parent.getInt('name'), 42);
      expect(parent.getString('storage'), 'integer');
      expect((await database.query('PRAGMA foreign_keys')).rows.single.getInt('foreign_keys'), 1);
      expect(
        (await database.query('SELECT parentId FROM content.children')).rows.single
            .getInt('parentId'),
        1,
      );
    });

    test('should preserve incoming foreign keys when a rebuilt parent is renamed', () async {
      final directory = Directory.systemTemp.createTempSync('voxel_renamed_rebuild_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      await generator.generateDeclaration(
        declaration: _constrainedDeclaration(),
        directory: directory,
        name: 'constraints',
      );
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS content");
      await _executeMigration(database, _migrationSql(directory));
      await database.execute('PRAGMA foreign_keys=ON');
      await database.execute("INSERT INTO content.parents VALUES (1, '42')");
      await database.execute('INSERT INTO content.children VALUES (1, 1)');

      final changed = _constrainedDeclaration();
      final parents = (changed['tables']! as List<Object?>).first! as Map<String, Object?>;
      parents['name'] = 'guardians';
      parents['renamedFrom'] = 'parents';
      final name = (parents['columns']! as List<Object?>).last! as Map<String, Object?>;
      name['storage'] = {'kind': 'integer', 'nullable': false, 'codecVersion': 1};
      final children = (changed['tables']! as List<Object?>).last! as Map<String, Object?>;
      final foreignKey =
          (children['constraints']! as List<Object?>).single! as Map<String, Object?>;
      (foreignKey['references']! as Map<String, Object?>)['table'] = 'guardians';
      await generator.generateDeclaration(
        declaration: changed,
        directory: directory,
        name: 'rename and rebuild parent',
        storageTransforms: {
          'content.guardians.name': 'CAST("name" AS INTEGER)',
        },
      );
      await _executeLatestGeneratedMigration(database, directory);

      await database.execute('INSERT INTO content.children VALUES (2, 1)');
      await expectLater(
        database.execute('INSERT INTO content.children VALUES (3, 99)'),
        throwsA(isA<TursoDatabaseException>()),
      );
      final foreignKeyTarget = (await database.query('PRAGMA content.foreign_key_list(children)'))
          .rows
          .single
          .getString('table');
      expect(foreignKeyTarget, 'guardians');
    });

    test('should roll back a rebuild when final foreign-key validation fails', () async {
      final directory = Directory.systemTemp.createTempSync('voxel_rebuild_rollback_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      await generator.generateDeclaration(
        declaration: _constrainedDeclaration(),
        directory: directory,
        name: 'constraints',
      );
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS content");
      await _executeMigration(database, _migrationSql(directory));
      await database.execute('PRAGMA foreign_keys=OFF');
      await database.execute("INSERT INTO content.parents VALUES (1, '42')");
      await database.execute('INSERT INTO content.children VALUES (1, 99)');

      final changed = _constrainedDeclaration();
      final parents = (changed['tables']! as List<Object?>).first! as Map<String, Object?>;
      final name = (parents['columns']! as List<Object?>).last! as Map<String, Object?>;
      name['storage'] = {'kind': 'integer', 'nullable': false, 'codecVersion': 1};
      await generator.generateDeclaration(
        declaration: changed,
        directory: directory,
        name: 'convert parent name',
        storageTransforms: {
          'content.parents.name': 'CAST("name" AS INTEGER)',
        },
      );

      await expectLater(
        _executeLatestGeneratedMigration(database, directory),
        throwsA(isA<StateError>()),
      );
      final parent = (await database.query(
        'SELECT name, typeof(name) AS storage FROM content.parents',
      )).rows.single;
      expect(parent.getString('name'), '42');
      expect(parent.getString('storage'), 'text');
      expect((await database.query('PRAGMA foreign_keys')).rows.single.getInt('foreign_keys'), 1);
    });

    test('should transform scalar and array enum labels without collapsing nulls', () async {
      final directory = Directory.systemTemp.createTempSync('voxel_enum_migration_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      var nextId = 0;
      final generator = VoxelMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final declaration = _enumDeclaration();
      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'enums',
      );
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await database.execute("ATTACH DATABASE ':memory:' AS auth");
      await _executeMigration(database, _migrationSql(directory));
      await database.execute("INSERT INTO auth.jobs VALUES ('done')");
      await database.execute("INSERT INTO auth.queues VALUES ('[\"done\",null,\"queued\"]')");
      await database.execute('INSERT INTO auth.queues VALUES (NULL)');

      final declaredEnum = (declaration['enums']! as List<Object?>).single! as Map<String, Object?>;
      declaredEnum['values'] = [
        {'dartName': 'queued', 'label': 'queued'},
        {'dartName': 'complete', 'label': 'complete', 'renamedFrom': 'done'},
      ];
      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'rename enum label',
        storageTransforms: {
          'auth.jobs.mood': 'CASE "mood" WHEN \'done\' THEN \'complete\' ELSE "mood" END',
          'auth.queues.moods': 'CASE WHEN "moods" IS NULL THEN NULL ELSE (SELECT json_group_array(CASE value WHEN \'done\' THEN \'complete\' ELSE value END) FROM json_each("moods")) END',
        },
      );
      await const VoxelMigrationChecker().check(directory: directory);
      await _executeLatestGeneratedMigration(database, directory);

      expect(
        (await database.query('SELECT mood FROM auth.jobs')).rows.single.getString('mood'),
        'complete',
      );
      final arrays = (await database.query('SELECT moods FROM auth.queues ORDER BY moods IS NULL'))
          .rows;
      expect(arrays.first.getString('moods'), '["complete",null,"queued"]');
      expect(arrays.last.value('moods'), isNull);
    });
  });
}

Map<String, Object?> _constrainedDeclaration() => {
  'formatVersion': 1,
  'dialect': 'voxel',
  'name': 'content',
  'tables': [
    {
      'schema': 'content',
      'name': 'parents',
      'columns': [
        _column('id', 'integer', primaryKey: true),
        _column('name', 'text'),
      ],
      'indexes': [
        {
          'name': 'parent_name_unique',
          'unique': true,
          'terms': [
            {'column': 'name', 'descending': false},
          ],
          'predicate': _notEmptyExpression('name'),
          'options': <String, Object?>{},
          'platforms': ['native', 'browser'],
        },
      ],
      'constraints': [
        {
          'name': 'parent_name_check',
          'kind': 'check',
          'columns': <Object?>[],
          'expression': _notEmptyExpression('name'),
        },
      ],
    },
    {
      'schema': 'content',
      'name': 'children',
      'columns': [
        _column('id', 'integer', primaryKey: true),
        _column('parentId', 'integer'),
      ],
      'indexes': <Object?>[],
      'constraints': [
        {
          'name': 'children_parent_fkey',
          'kind': 'foreignKey',
          'columns': ['parentId'],
          'references': {
            'schema': 'content',
            'table': 'parents',
            'columns': ['id'],
          },
          'onDelete': 'noAction',
          'onUpdate': 'noAction',
        },
      ],
    },
  ],
  'enums': <Object?>[],
  'requirements': <Object?>[],
};

Map<String, Object?> _column(String name, String kind, {bool primaryKey = false}) => {
  'name': name,
  'storage': {'kind': kind, 'nullable': false, 'codecVersion': 1},
  'primaryKey': primaryKey,
};

Map<String, Object?> _notEmptyExpression(String column) => {
  'formatVersion': 1,
  'kind': 'operator',
  'operator': 'NOT',
  'arguments': [
    {
      'formatVersion': 1,
      'kind': 'operator',
      'operator': '=',
      'arguments': [
        {'formatVersion': 1, 'kind': 'reference', 'objectName': column},
        {
          'formatVersion': 1,
          'kind': 'literal',
          'literalType': 'string',
          'value': '',
        },
      ],
    },
  ],
};

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

Map<String, Object?> _enumDeclaration() => {
  'formatVersion': 1,
  'dialect': 'voxel',
  'name': 'enums',
  'tables': [
    {
      'schema': 'auth',
      'name': 'jobs',
      'columns': [_enumColumn('mood')],
      'indexes': <Object?>[],
      'constraints': <Object?>[],
    },
    {
      'schema': 'auth',
      'name': 'queues',
      'columns': [
        {
          'name': 'moods',
          'storage': {
            'kind': 'array',
            'nullable': true,
            'codecVersion': 1,
            'element': _enumStorage(nullable: true),
          },
          'primaryKey': false,
        },
      ],
      'indexes': <Object?>[],
      'constraints': <Object?>[],
    },
  ],
  'enums': [
    {
      'schema': 'types',
      'name': 'mood',
      'values': [
        {'dartName': 'queued', 'label': 'queued'},
        {'dartName': 'complete', 'label': 'done'},
      ],
    },
  ],
  'requirements': <Object?>[],
};

Map<String, Object?> _enumColumn(String name) => {
  'name': name,
  'storage': _enumStorage(nullable: false),
  'primaryKey': false,
};

Map<String, Object?> _enumStorage({required bool nullable}) => {
  'kind': 'enum',
  'nullable': nullable,
  'codecVersion': 1,
  'enum': {'schema': 'types', 'name': 'mood'},
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

Future<void> _executeLatestGeneratedMigration(
  TursoDatabase database,
  Directory directory,
) async {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  final migrationDirectory = '${directory.path}/${entry['directory']}';
  final migration = jsonDecode(
    File('$migrationDirectory/migration.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final sql = File('$migrationDirectory/migration.sql').readAsStringSync();
  final bytes = utf8.encode(sql);
  for (final rawPhase in migration['phases']! as List<Object?>) {
    final phase = rawPhase! as Map<String, Object?>;
    final rebuild = phase['rebuild'] as Map<String, Object?>?;
    if (rebuild != null) await database.execute('PRAGMA foreign_keys=OFF');
    await database.execute('BEGIN');
    try {
      for (final rawRange in phase['statements']! as List<Object?>) {
        final range = rawRange! as Map<String, Object?>;
        await database.execute(
          utf8.decode(bytes.sublist(range['startByte']! as int, range['endByte']! as int)),
        );
      }
      if (rebuild != null) {
        for (final rawValidation in rebuild['validations']! as List<Object?>) {
          final validation = rawValidation! as Map<String, Object?>;
          final row = (await database.query(validation['sql']! as String)).rows.single;
          if (row.getInt('valid') != 1) throw StateError('Rebuild validation failed.');
        }
      }
      await database.execute('COMMIT');
    } on Object {
      await database.execute('ROLLBACK');
      rethrow;
    } finally {
      if (rebuild != null) await database.execute('PRAGMA foreign_keys=ON');
    }
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

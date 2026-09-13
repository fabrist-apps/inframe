import 'dart:convert';
import 'dart:io';

import 'package:rivet/rivet.dart';
import 'package:rivet_generator/rivet_generator.dart';
import 'package:test/test.dart';

void main() {
  group('RivetMigrationGenerator', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('rivet_migration_test_');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    test('should publish an initial migration with ordered artifacts', () async {
      var nextId = 0;
      final generator = RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final migrationId = await generator.generate(
        schema: RivetDatabaseSchema(
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
        'CREATE SCHEMA IF NOT EXISTS "auth";\n'
        'CREATE TABLE "auth"."users" (\n'
        '  "id" int4 NOT NULL,\n'
        '  "name" text NOT NULL\n'
        ');\n'
        'ALTER TABLE "auth"."users" ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");\n',
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
      final schema = RivetDatabaseSchema(
        name: 'accounts',
        tables: [Users.db.buildSchema()],
      );
      await RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      ).generate(schema: schema, directory: directory, name: 'create users');

      await const RivetMigrationChecker().check(
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
        const RivetMigrationChecker().check(directory: directory),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject duplicate JSON keys before interpreting a journal', () async {
      File('${directory.path}/journal.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"formatVersion":1,"formatVersion":1,"dialect":"rivet",'
          '"databaseId":"00000000000000000000000000000001","entries":[]}',
        );

      await expectLater(
        const RivetMigrationChecker().check(directory: directory),
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
      await RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      ).generate(
        schema: RivetDatabaseSchema(
          name: 'accounts',
          tables: [Users.db.buildSchema()],
        ),
        directory: directory,
        name: 'create users',
      );

      await expectLater(
        const RivetMigrationChecker().check(
          directory: directory,
          schema: RivetDatabaseSchema(
            name: 'accounts',
            tables: [RenamedUsers.db.buildSchema()],
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should ignore JSON formatting and key order in checksums', () async {
      var nextId = 0;
      await RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      ).generate(
        schema: RivetDatabaseSchema(
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

      await const RivetMigrationChecker().check(directory: directory);
    });

    test('should preserve identities through table and column renames', () async {
      var nextId = 0;
      final generator = RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      await generator.generate(
        schema: RivetDatabaseSchema(
          name: 'accounts',
          tables: [Users.db.buildSchema()],
        ),
        directory: directory,
        name: 'create users',
      );
      final firstSnapshot = _lastArtifact(directory, 'snapshot.json');

      final migrationId = await generator.generate(
        schema: RivetDatabaseSchema(
          name: 'accounts',
          tables: [Members.db.buildSchema()],
        ),
        directory: directory,
        name: 'rename users',
      );
      final secondSnapshot = _lastArtifact(directory, 'snapshot.json');
      final migration = _lastArtifact(directory, 'migration.json');
      final sql = _lastArtifactFile(directory, 'migration.sql').readAsStringSync();
      final firstTable =
          (firstSnapshot['tables']! as List<Object?>).single! as Map<String, Object?>;
      final secondTable =
          (secondSnapshot['tables']! as List<Object?>).single! as Map<String, Object?>;
      final firstColumns = (firstTable['columns']! as List<Object?>).cast<Map<String, Object?>>();
      final secondColumns = (secondTable['columns']! as List<Object?>).cast<Map<String, Object?>>();

      expect(migrationId, isNotNull);
      expect(migration['parentId'], firstSnapshot['migrationId']);
      expect(secondTable['id'], firstTable['id']);
      expect(secondColumns[0]['id'], firstColumns[0]['id']);
      expect(secondColumns[1]['id'], firstColumns[1]['id']);
      expect(sql, contains('ALTER TABLE "auth"."users" RENAME TO "members";'));
      expect(sql, contains('RENAME COLUMN "name" TO "fullName";'));
      expect(sql, contains('ADD COLUMN "active" bool DEFAULT true NOT NULL;'));
      await const RivetMigrationChecker().check(
        directory: directory,
        schema: RivetDatabaseSchema(
          name: 'accounts',
          tables: [Members.db.buildSchema()],
        ),
      );

      expect(
        await generator.generate(
          schema: RivetDatabaseSchema(
            name: 'accounts',
            tables: [Members.db.buildSchema()],
          ),
          directory: directory,
          name: 'runtime only',
        ),
        isNull,
      );
    });

    test('should generate supported column alterations and removals', () async {
      var nextId = 0;
      final generator = RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final initial = RivetDatabaseSchema(
        name: 'accounts',
        tables: [Users.db.buildSchema()],
      );
      await generator.generate(schema: initial, directory: directory, name: 'initial');
      final declaration = initial.toJson();
      final table = (declaration['tables']! as List<Object?>).single! as Map<String, Object?>;
      final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();
      columns[0]['storage'] = {
        ...(columns[0]['storage']! as Map<String, Object?>),
        'kind': 'real',
      };
      columns[1]['storage'] = {
        ...(columns[1]['storage']! as Map<String, Object?>),
        'nullable': true,
      };
      columns[1]['default'] = {
        'formatVersion': 1,
        'kind': 'sql',
        'sql': "'unknown'",
      };

      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'alter users',
      );
      final sql = _lastArtifactFile(directory, 'migration.sql').readAsStringSync();

      expect(sql, contains('TYPE float8 USING "id"::float8;'));
      expect(sql, contains('ALTER COLUMN "name" DROP NOT NULL;'));
      expect(sql, contains("ALTER COLUMN \"name\" SET DEFAULT 'unknown';"));

      table['columns'] = [columns.first];
      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'remove name',
      );
      expect(
        _lastArtifactFile(directory, 'migration.sql').readAsStringSync(),
        contains('DROP COLUMN "name";'),
      );
    });

    test('should generate indexes, checks, composite keys, and foreign keys', () async {
      var nextId = 0;
      final generator = RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final declaration = _constraintDeclaration();

      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'constraints',
      );
      final sql = _lastArtifactFile(directory, 'migration.sql').readAsStringSync();
      final snapshot = _lastArtifact(directory, 'snapshot.json');

      expect(
        sql,
        contains(
          'CREATE UNIQUE INDEX "users_email_active" ON "auth"."users" '
          '("email" ASC, "tenant" DESC) WHERE ("active" = true);',
        ),
      );
      expect(sql, contains('ADD CONSTRAINT "email_present" CHECK (NOT (("email" = \'\')));'));
      expect(
        sql,
        contains('ADD CONSTRAINT "memberships_pkey" PRIMARY KEY ("tenant", "userId");'),
      );
      expect(
        sql,
        contains(
          'REFERENCES "auth"."users" ("tenant") ON DELETE CASCADE ON UPDATE RESTRICT;',
        ),
      );
      final tables = (snapshot['tables']! as List<Object?>).cast<Map<String, Object?>>();
      final identities = <Object?>{
        for (final table in tables) ...[
          for (final index in table['indexes']! as List<Object?>)
            (index! as Map<String, Object?>)['id'],
          for (final constraint in table['constraints']! as List<Object?>)
            (constraint! as Map<String, Object?>)['id'],
        ],
      };
      expect(identities, hasLength(5));
      await const RivetMigrationChecker().check(directory: directory);

      final users = (declaration['tables']! as List<Object?>).cast<Map<String, Object?>>().first;
      final index = (users['indexes']! as List<Object?>).first! as Map<String, Object?>;
      users['indexes'] = [
        {
          ...index,
          'options': <String, Object?>{'method': 'hnsw'},
        },
      ];
      await expectLater(
        generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'unsupported search index',
        ),
        throwsA(isA<UnsupportedError>()),
      );
      final migrationFile = _lastArtifactFile(directory, 'migration.json');
      final editedMigration = jsonDecode(migrationFile.readAsStringSync()) as Map<String, Object?>;
      final editedPhases = (editedMigration['phases']! as List<Object?>)
          .cast<Map<String, Object?>>();
      editedPhases.first['platforms'] = ['postgresql', 'review-edit'];
      migrationFile.writeAsStringSync(jsonEncode(editedMigration));
      await expectLater(
        const RivetMigrationChecker().check(directory: directory),
        throwsA(isA<FormatException>()),
      );
    });

    test('should create one shared native enum before scalar and array columns', () async {
      var nextId = 0;
      final generator = RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final declaration = _enumDeclaration();

      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'native enum',
      );
      final sql = _lastArtifactFile(directory, 'migration.sql').readAsStringSync();
      final snapshot = _lastArtifact(directory, 'snapshot.json');
      final enumValue = (snapshot['enums']! as List<Object?>).single! as Map<String, Object?>;
      final values = (enumValue['values']! as List<Object?>).cast<Map<String, Object?>>();
      final tables = (snapshot['tables']! as List<Object?>).cast<Map<String, Object?>>();
      final storages = [
        for (final table in tables)
          for (final column in table['columns']! as List<Object?>)
            (column! as Map<String, Object?>)['storage']! as Map<String, Object?>,
      ];

      expect('CREATE TYPE'.allMatches(sql), hasLength(1));
      expect(sql.indexOf('CREATE TYPE'), lessThan(sql.indexOf('CREATE TABLE')));
      expect(sql, contains('CREATE TYPE "types"."mood" AS ENUM (\'queued\', \'done\');'));
      expect(values.map((value) => value['label']), ['queued', 'done']);
      expect(values.map((value) => value['id']).toSet(), hasLength(2));
      expect(storages.first['enumId'], enumValue['id']);
      expect((storages.last['element']! as Map<String, Object?>)['enumId'], enumValue['id']);
      final declaredValues =
          ((declaration['enums']! as List<Object?>).single! as Map<String, Object?>)['values']!
              as List<Object?>;
      (declaredValues.last! as Map<String, Object?>)['dartName'] = 'finished';
      expect(
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'no enum change',
        ),
        isNull,
      );
      final declaredEnum = (declaration['enums']! as List<Object?>).single! as Map<String, Object?>;
      declaredEnum['values'] = [
        {'dartName': 'first', 'label': 'same'},
        {'dartName': 'second', 'label': 'same'},
      ];
      await expectLater(
        generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'invalid enum',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        (jsonDecode(File('${directory.path}/journal.json').readAsStringSync())
            as Map<String, Object?>)['entries'],
        hasLength(1),
      );
    });

    test('should separate enum additions from later uses and preserve rename identities', () async {
      var nextId = 0;
      final generator = RivetMigrationGenerator(
        createId: () => (++nextId).toRadixString(16).padLeft(32, '0'),
      );
      final declaration = _enumDeclaration();
      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'native enum',
      );
      final before = _lastArtifact(directory, 'snapshot.json');
      final oldEnum = (before['enums']! as List<Object?>).single! as Map<String, Object?>;
      final oldValues = (oldEnum['values']! as List<Object?>).cast<Map<String, Object?>>();
      final declaredEnum =
          ((declaration['enums']! as List<Object?>).single! as Map<String, Object?>)
            ..['name'] = 'state'
            ..['renamedFrom'] = 'mood'
            ..['values'] = [
              {'dartName': 'queued', 'label': 'queued'},
              {'dartName': 'running', 'label': 'running'},
              {'dartName': 'complete', 'label': 'complete', 'renamedFrom': 'done'},
            ];
      for (final table in declaration['tables']! as List<Object?>) {
        for (final column in (table! as Map<String, Object?>)['columns']! as List<Object?>) {
          _renameEnumStorage((column! as Map<String, Object?>)['storage']! as Map<String, Object?>);
        }
      }
      final jobs = (declaration['tables']! as List<Object?>).first! as Map<String, Object?>;
      ((jobs['columns']! as List<Object?>).first! as Map<String, Object?>)['default'] = {
        'formatVersion': 1,
        'kind': 'literal',
        'literalType': 'string',
        'value': 'running',
      };

      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'evolve enum',
      );
      final after = _lastArtifact(directory, 'snapshot.json');
      final migration = _lastArtifact(directory, 'migration.json');
      final sql = _lastArtifactFile(directory, 'migration.sql').readAsStringSync();
      final nextEnum = (after['enums']! as List<Object?>).single! as Map<String, Object?>;
      final nextValues = (nextEnum['values']! as List<Object?>).cast<Map<String, Object?>>();
      final phases = (migration['phases']! as List<Object?>).cast<Map<String, Object?>>();

      expect(nextEnum['id'], oldEnum['id']);
      expect(nextValues.first['id'], oldValues.first['id']);
      expect(nextValues.last['id'], oldValues.last['id']);
      expect(nextValues.map((value) => value['label']), ['queued', 'running', 'complete']);
      expect(sql, contains('ALTER TYPE "types"."mood" RENAME TO "state";'));
      expect(sql, contains("RENAME VALUE 'done' TO 'complete';"));
      expect(sql, contains("ADD VALUE 'running' BEFORE 'complete';"));
      expect(phases, hasLength(3));
      expect(
        (phases[1]['statements']! as List<Object?>).single,
        isA<Map<String, Object?>>(),
      );
      expect(
        sql.indexOf("ADD VALUE 'running'"),
        lessThan(sql.indexOf("SET DEFAULT 'running'")),
      );
      expect(
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'resolved enum hints',
        ),
        isNull,
      );

      final reorderedValues = declaredEnum['values']! as List<Object?>;
      declaredEnum['values'] = [reorderedValues.last, reorderedValues.first, reorderedValues[1]];
      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'reorder enum',
      );
      final reorderedSnapshot = _lastArtifact(directory, 'snapshot.json');
      final reorderedEnum =
          (reorderedSnapshot['enums']! as List<Object?>).single! as Map<String, Object?>;
      expect(
        (reorderedEnum['values']! as List<Object?>).cast<Map<String, Object?>>().map(
          (value) => value['id'],
        ),
        [nextValues.last['id'], nextValues.first['id'], nextValues[1]['id']],
      );
      expect(
        _lastArtifactFile(directory, 'migration.sql').readAsStringSync(),
        allOf(contains('CREATE TYPE "types"."__rivet_'), contains('DROP TYPE "types"."state";')),
      );

      declaredEnum['values'] = [reorderedValues.last, reorderedValues.first];
      final jobsColumns = (jobs['columns']! as List<Object?>).cast<Map<String, Object?>>();
      jobsColumns.first['default'] = {
        'formatVersion': 1,
        'kind': 'literal',
        'literalType': 'string',
        'value': 'queued',
      };
      await expectLater(
        generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'remove without transform',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('requires --enum-transform'),
          ),
        ),
      );
      await generator.generateDeclaration(
        declaration: declaration,
        directory: directory,
        name: 'remove enum label',
        enumLabelTransforms: const {'types.state.running': 'queued'},
      );
      final removalSql = _lastArtifactFile(directory, 'migration.sql').readAsStringSync();
      expect(removalSql, contains("SET \"mood\" = 'queued'::\"types\".\"state\""));
      expect(removalSql, contains('array_replace("moods"'));
    });
  });
}

void _renameEnumStorage(Map<String, Object?> storage) {
  if (storage['kind'] == 'enum') {
    storage['enum'] = {'schema': 'types', 'name': 'state'};
  }
  if (storage['element'] case final Map<String, Object?> element) {
    _renameEnumStorage(element);
  }
}

Map<String, Object?> _enumDeclaration() => {
  'formatVersion': 1,
  'dialect': 'rivet',
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
      'schema': 'work',
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

Map<String, Object?> _constraintDeclaration() => {
  'formatVersion': 1,
  'dialect': 'rivet',
  'name': 'constraints',
  'tables': [
    {
      'schema': 'auth',
      'name': 'users',
      'columns': [
        _column('tenant', primaryKey: true),
        _column('email'),
        _column('active', kind: 'boolean'),
      ],
      'indexes': [
        {
          'name': 'users_email_active',
          'unique': true,
          'terms': [
            {'column': 'email', 'descending': false},
            {'column': 'tenant', 'descending': true},
          ],
          'predicate': _operator('=', _reference('active'), _literal(true)),
          'options': <String, Object?>{},
          'platforms': ['postgresql'],
        },
      ],
      'constraints': [
        {
          'name': 'email_present',
          'kind': 'check',
          'columns': <String>[],
          'expression': _operator('NOT', _operator('=', _reference('email'), _literal(''))),
        },
      ],
    },
    {
      'schema': 'work',
      'name': 'memberships',
      'columns': [_column('tenant'), _column('userId')],
      'indexes': <Object?>[],
      'constraints': [
        {
          'name': 'memberships_pkey',
          'kind': 'primaryKey',
          'columns': ['tenant', 'userId'],
        },
        {
          'name': 'membership_tenant_fkey',
          'kind': 'foreignKey',
          'columns': ['tenant'],
          'references': {
            'schema': 'auth',
            'table': 'users',
            'columns': ['tenant'],
          },
          'onDelete': 'cascade',
          'onUpdate': 'restrict',
        },
      ],
    },
  ],
  'enums': <Object?>[],
  'requirements': <Object?>[],
};

Map<String, Object?> _column(
  String name, {
  String kind = 'integer',
  bool primaryKey = false,
}) => {
  'name': name,
  'storage': {'kind': kind, 'nullable': false, 'codecVersion': 1},
  'primaryKey': primaryKey,
};

Map<String, Object?> _reference(String name) => {
  'formatVersion': 1,
  'kind': 'reference',
  'objectName': name,
};

Map<String, Object?> _literal(Object value) => {
  'formatVersion': 1,
  'kind': 'literal',
  'literalType': value is bool ? 'boolean' : 'string',
  'value': value,
};

Map<String, Object?> _operator(
  String operator,
  Map<String, Object?> first, [
  Map<String, Object?>? second,
]) => {
  'formatVersion': 1,
  'kind': 'operator',
  'operator': operator,
  'arguments': [first, ?second],
};

Map<String, Object?> _lastArtifact(Directory directory, String name) =>
    jsonDecode(_lastArtifactFile(directory, name).readAsStringSync()) as Map<String, Object?>;

File _lastArtifactFile(Directory directory, String name) {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  return File('${directory.path}/${entry['directory']}/$name');
}

@RivetTable(schema: 'auth', name: 'renamedUsers')
final class RenamedUsers extends RivetTableDefinition<RenamedUsers> {
  static const db = _RenamedUsersAccessor();

  late final RivetOrderableColumn<int> id = integer().primaryKey()();
  late final RivetOrderableColumn<String> name = text()();
}

final class _RenamedUsersAccessor extends RivetTableAccessor<RenamedUsers, Object> {
  const _RenamedUsersAccessor();

  @override
  RivetTableSchema<RenamedUsers, Object> buildSchema() {
    final definition = RenamedUsers();
    return RivetTableSchema(
      schemaName: 'auth',
      tableName: 'renamedUsers',
      definition: definition,
      columns: [definition.id, definition.name],
      columnNames: const ['id', 'name'],
      decode: (_, _) => Object(),
    );
  }
}

@RivetTable(schema: 'auth', name: 'members', renamedFrom: 'users')
final class Members extends RivetTableDefinition<Members> {
  static const db = _MembersAccessor();

  late final RivetOrderableColumn<int> id = integer().primaryKey()();
  late final RivetOrderableColumn<String> fullName = text(renamedFrom: 'name')();
  late final RivetOrderableColumn<bool> active = boolean().defaultSql('true')();
}

final class _MembersAccessor extends RivetTableAccessor<Members, Object> {
  const _MembersAccessor();

  @override
  RivetTableSchema<Members, Object> buildSchema() {
    final definition = Members();
    return RivetTableSchema(
      schemaName: 'auth',
      tableName: 'members',
      renamedFrom: 'users',
      definition: definition,
      columns: [definition.id, definition.fullName, definition.active],
      columnNames: const ['id', 'fullName', 'active'],
      decode: (_, _) => Object(),
    );
  }
}

@RivetTable(schema: 'auth', name: 'users')
final class Users extends RivetTableDefinition<Users> {
  static const db = _UsersAccessor();

  late final RivetOrderableColumn<int> id = integer().primaryKey()();
  late final RivetOrderableColumn<String> name = text()();
}

final class _UsersAccessor extends RivetTableAccessor<Users, Object> {
  const _UsersAccessor();

  @override
  RivetTableSchema<Users, Object> buildSchema() {
    final definition = Users();
    return RivetTableSchema(
      schemaName: 'auth',
      tableName: 'users',
      definition: definition,
      columns: [definition.id, definition.name],
      columnNames: const ['id', 'name'],
      decode: (_, _) => Object(),
    );
  }
}

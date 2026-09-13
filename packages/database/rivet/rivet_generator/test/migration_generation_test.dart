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

      expect(migrationId, '00000000000000000000000000000006');
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
        '  "id" int4 NOT NULL PRIMARY KEY,\n'
        '  "name" text NOT NULL\n'
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
  });
}

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

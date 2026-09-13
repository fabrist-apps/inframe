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
  });
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

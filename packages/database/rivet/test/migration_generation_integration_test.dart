import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:rivet_generator/rivet_generator.dart';
import 'package:test/test.dart';

import 'generated_consumer.dart';
import 'migration_fixture.dart';

void main() {
  group('RivetMigrationGenerator integration', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late Directory directory;
    late pg.Connection connection;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('rivet_migration_integration_');
      if (databaseUrl == null) return;
      connection = await pg.Connection.openFromUrl(databaseUrl);
      await connection.execute('DROP SCHEMA IF EXISTS auth CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS work CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS fbr120 CASCADE');
    });

    tearDown(() async {
      if (databaseUrl != null) await connection.close();
      directory.deleteSync(recursive: true);
    });

    test(
      'should apply generated ordinary SQL without the migration runner',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        final journal = jsonDecode(
          File('${directory.path}/journal.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
        final sql = File(
          '${directory.path}/${entry['directory']}/migration.sql',
        ).readAsStringSync();
        final migration = jsonDecode(
          File(
            '${directory.path}/${entry['directory']}/migration.json',
          ).readAsStringSync(),
        ) as Map<String, Object?>;

        final sqlBytes = utf8.encode(sql);
        final phase = (migration['phases']! as List<Object?>).single! as Map<String, Object?>;
        for (final value in phase['statements']! as List<Object?>) {
          final statement = value! as Map<String, Object?>;
          await connection.execute(
            utf8.decode(
              sqlBytes.sublist(
                statement['startByte']! as int,
                statement['endByte']! as int,
              ),
            ),
          );
        }
        await connection.execute(
          'INSERT INTO "auth"."users" ("id", "name") VALUES (1, \'Bhaswanth\')',
        );
        final rows = await connection.execute(
          'SELECT "name" FROM "auth"."users" WHERE "id" = 1',
        );

        expect(rows.single.single, 'Bhaswanth');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve data through declared table and column renames',
      () async {
        const generator = RivetMigrationGenerator();
        await generator.generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        await _applyLastMigration(connection, directory);
        await connection.execute(
          'INSERT INTO "auth"."users" ("id", "name") VALUES (1, \'Bhaswanth\')',
        );

        await generator.generate(
          schema: MigratedFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'rename users',
        );
        await _applyLastMigration(connection, directory);
        final rows = await connection.execute(
          'SELECT "fullName", "active" FROM "auth"."members" WHERE "id" = 1',
        );

        expect(rows.single, ['Bhaswanth', true]);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should enforce generated indexes, checks, composite keys, and foreign keys',
      () async {
        await const RivetMigrationGenerator().generateDeclaration(
          declaration: _constraintDeclaration(),
          directory: directory,
          name: 'constraints',
        );
        await _applyLastMigration(connection, directory);

        await connection.execute(
          "INSERT INTO auth.users (id, email, active) VALUES (1, 'a@example.com', true)",
        );
        await expectLater(
          connection.execute(
            "INSERT INTO auth.users (id, email, active) VALUES (2, 'a@example.com', true)",
          ),
          throwsA(anything),
        );
        await connection.execute(
          "INSERT INTO auth.users (id, email, active) VALUES (2, 'a@example.com', false)",
        );
        await expectLater(
          connection.execute("INSERT INTO auth.users (id, email, active) VALUES (3, '', true)"),
          throwsA(anything),
        );
        await expectLater(
          connection.execute('INSERT INTO work.projects (id, "ownerId") VALUES (1, 999)'),
          throwsA(anything),
        );
        await connection.execute('INSERT INTO work.projects (id, "ownerId") VALUES (1, 1)');
        await connection.execute('DELETE FROM auth.users WHERE id = 1');
        expect(
          (await connection.execute('SELECT count(*) FROM work.projects')).single.single,
          0,
        );
        await connection.execute('INSERT INTO work.memberships (tenant, "userId") VALUES (1, 2)');
        await expectLater(
          connection.execute('INSERT INTO work.memberships (tenant, "userId") VALUES (1, 2)'),
          throwsA(anything),
        );
        final indexDefinition = await connection.execute(
          "SELECT indexdef FROM pg_indexes WHERE schemaname = 'auth' "
          "AND indexname = 'users_email_active'",
        );
        expect(
          indexDefinition.single.single,
          allOf(contains('(email)'), contains('WHERE (active = true)')),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should round-trip scalar and array values through one generated native enum type',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: RivetDatabaseSchema(
            name: 'enum_fixture',
            tables: [EnumValues.db.buildSchema()],
          ),
          directory: directory,
          name: 'native enum',
        );
        await _applyLastMigration(connection, directory);
        final database = await RivetTestDatabase().open(
          connection: RivetConnection.url(databaseUrl!, sslMode: RivetSslMode.disable),
        );
        addTearDown(database.close);

        await EnumValues.db
            .insert(
              EnumValuesCompanion.insert(
                status: const RivetValue.present(WorkStatus.queued),
                nullableStatuses: const RivetValue.present([
                  WorkStatus.queued,
                  null,
                  WorkStatus.complete,
                ]),
                mappedStatus: const RivetValue.present(WorkState(WorkStatus.complete)),
              ),
            )
            .execute(database);
        final row = (await EnumValues.db.find().get(database)).single;

        expect(row.status, WorkStatus.queued);
        expect(row.nullableStatuses, [WorkStatus.queued, null, WorkStatus.complete]);
        expect(row.mappedStatus.value, WorkStatus.complete);
        final enumTypes = await connection.execute(
          'SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace '
          "WHERE n.nspname = 'fbr120' AND t.typname = 'workStatus'",
        );
        expect(enumTypes.single.single, 1);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

Map<String, Object?> _constraintDeclaration() => {
  'formatVersion': 1,
  'dialect': 'rivet',
  'name': 'constraints',
  'tables': [
    {
      'schema': 'auth',
      'name': 'users',
      'columns': [
        _column('id', primaryKey: true),
        _column('email', kind: 'text'),
        _column('active', kind: 'boolean'),
      ],
      'indexes': [
        {
          'name': 'users_email_active',
          'unique': true,
          'terms': [
            {'column': 'email', 'descending': false},
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
      'name': 'projects',
      'columns': [_column('id', primaryKey: true), _column('ownerId')],
      'indexes': <Object?>[],
      'constraints': [
        {
          'name': 'projects_owner_fkey',
          'kind': 'foreignKey',
          'columns': ['ownerId'],
          'references': {
            'schema': 'auth',
            'table': 'users',
            'columns': ['id'],
          },
          'onDelete': 'cascade',
          'onUpdate': 'restrict',
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

Future<void> _applyLastMigration(pg.Connection connection, Directory directory) async {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  final migrationDirectory = '${directory.path}/${entry['directory']}';
  final sqlBytes = File('$migrationDirectory/migration.sql').readAsBytesSync();
  final migration = jsonDecode(
    File('$migrationDirectory/migration.json').readAsStringSync(),
  ) as Map<String, Object?>;
  for (final rawPhase in migration['phases']! as List<Object?>) {
    final phase = rawPhase! as Map<String, Object?>;
    for (final value in phase['statements']! as List<Object?>) {
      final statement = value! as Map<String, Object?>;
      await connection.execute(
        utf8.decode(
          sqlBytes.sublist(
            statement['startByte']! as int,
            statement['endByte']! as int,
          ),
        ),
      );
    }
  }
}

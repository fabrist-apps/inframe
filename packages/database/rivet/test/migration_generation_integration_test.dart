import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:rivet_generator/rivet_generator.dart';
import 'package:rivet_generator/src/migration/sealer.dart';
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
      await connection.execute('DROP SCHEMA IF EXISTS fbr121 CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS fbr122 CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS fbr138 CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS fbr139 CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS fbr148 CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS enum_evolution CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS metadata CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS search CASCADE');
      await connection.execute('DROP SCHEMA IF EXISTS fbr195 CASCADE');
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
      'should reject a missing required extension before bootstrapping history',
      () async {
        await connection.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await connection.execute('DROP EXTENSION IF EXISTS vector');
        final schema = RivetDatabaseSchema(
          name: 'vector_indexes',
          tables: [
            VectorDocuments.db.buildSchema() as RivetTableSchema<Object?, Object?>,
          ],
        );
        await const RivetMigrationGenerator().generate(
          schema: schema,
          directory: directory,
          name: 'hnsw indexes',
        );

        await expectLater(
          RivetMigrator(
            connection: RivetConnection.url(databaseUrl!),
            directory: directory,
          ).migrate(),
          throwsA(
            isA<RivetMigrationException>().having(
              (error) => error.message,
              'message',
              contains('extension `vector` >= 0.8.6, but it is not installed'),
            ),
          ),
        );
        final historySchema = await connection.execute(
          "SELECT 1 FROM pg_namespace WHERE nspname = '_rivet'",
        );
        expect(historySchema, isEmpty);
        await connection.execute('CREATE EXTENSION vector');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should apply checked HNSW indexes after extension preflight',
      () async {
        await connection.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await connection.execute('CREATE EXTENSION IF NOT EXISTS vector');
        final schema = RivetDatabaseSchema(
          name: 'vector_indexes',
          tables: [
            VectorDocuments.db.buildSchema() as RivetTableSchema<Object?, Object?>,
          ],
        );
        await const RivetMigrationGenerator().generate(
          schema: schema,
          directory: directory,
          name: 'hnsw indexes',
        );

        await RivetMigrator(
          connection: RivetConnection.url(databaseUrl!),
          directory: directory,
        ).migrate();

        final indexes = await connection.execute('''
          SELECT indexdef FROM pg_indexes
          WHERE schemaname = 'fbr195' AND tablename = 'vectorDocuments'
          ORDER BY indexname
        ''');
        expect(indexes, hasLength(4));
        expect(
          indexes.map((row) => row.first! as String),
          containsAll([
            contains('USING hnsw (embedding vector_cosine_ops)'),
            contains('USING hnsw (embedding vector_l2_ops)'),
            contains('USING hnsw (embedding vector_ip_ops)'),
          ]),
        );
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
        final schema = RivetDatabaseSchema(
          name: 'enum_fixture',
          tables: [EnumValues.db.buildSchema()],
        );
        await const RivetMigrationGenerator().generate(
          schema: schema,
          directory: directory,
          name: 'native enum',
        );
        await const RivetMigrationChecker().check(
          directory: directory,
          schema: schema,
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

    test(
      'should commit enum additions before later use and preserve stored data',
      () async {
        const generator = RivetMigrationGenerator();
        final declaration = _evolvingEnumDeclaration();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial enum',
        );
        await _applyLastMigration(connection, directory);
        await connection.execute(
          'INSERT INTO enum_evolution.jobs (id, status, statuses) '
          "VALUES (1, 'done', ARRAY['queued', 'done']::enum_evolution.mood[])",
        );

        final enumValue = ((declaration['enums']! as List<Object?>).single! as Map<String, Object?>)
          ..['name'] = 'state'
          ..['renamedFrom'] = 'mood'
          ..['values'] = [
            {'dartName': 'queued', 'label': 'queued'},
            {'dartName': 'running', 'label': 'running'},
            {'dartName': 'complete', 'label': 'complete', 'renamedFrom': 'done'},
          ];
        final table = (declaration['tables']! as List<Object?>).single! as Map<String, Object?>;
        final columns = (table['columns']! as List<Object?>).cast<Map<String, Object?>>();
        for (final column in columns) {
          _renameEnumReference(column['storage']! as Map<String, Object?>);
        }
        columns[1]['default'] = {
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
        expect(enumValue['name'], 'state');
        final migration = _lastArtifact(directory, 'migration.json');
        expect(migration['phases']! as List<Object?>, hasLength(3));
        await _applyLastMigration(connection, directory);
        final existing = await connection.execute(
          'SELECT status::text, statuses::text[] FROM enum_evolution.jobs WHERE id = 1',
        );
        expect(existing.single, [
          'complete',
          ['queued', 'complete'],
        ]);
        await connection.execute(
          'INSERT INTO enum_evolution.jobs (id, statuses) '
          "VALUES (2, ARRAY['running']::enum_evolution.state[])",
        );
        expect(
          (await connection.execute(
            'SELECT status::text FROM enum_evolution.jobs WHERE id = 2',
          )).single.single,
          'running',
        );

        final evolvedValues = enumValue['values']! as List<Object?>;
        enumValue['values'] = [evolvedValues.last, evolvedValues.first, evolvedValues[1]];
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'reorder enum',
        );
        await _applyLastMigration(connection, directory);
        final order = await connection.execute(
          'SELECT e.enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid '
          "JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'enum_evolution' "
          "AND t.typname = 'state' ORDER BY e.enumsortorder",
        );
        expect(order.map((row) => row.single), ['complete', 'queued', 'running']);
        await connection.execute(
          'INSERT INTO enum_evolution.jobs (id, status, statuses) '
          "VALUES (3, 'queued', ARRAY['queued']::enum_evolution.state[])",
        );

        columns[1]['default'] = {
          'formatVersion': 1,
          'kind': 'literal',
          'literalType': 'string',
          'value': 'complete',
        };
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'default to removable label',
        );
        await _applyLastMigration(connection, directory);

        enumValue['values'] = [evolvedValues.first, evolvedValues[1]];
        columns[1]['default'] = {
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
          throwsA(isA<FormatException>()),
        );
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'remove complete',
          enumLabelTransforms: const {'enum_evolution.state.complete': 'queued'},
        );
        await expectLater(
          _applyLastMigration(connection, directory),
          throwsA(anything),
        );
        expect(
          (await connection.execute(
            'SELECT status::text FROM enum_evolution.jobs WHERE id = 1',
          )).single.single,
          'complete',
        );
        await connection.execute('DELETE FROM enum_evolution.jobs WHERE id = 3');
        await _applyLastMigration(connection, directory);
        final transformed = await connection.execute(
          'SELECT status::text, statuses::text[] FROM enum_evolution.jobs WHERE id = 1',
        );
        expect(transformed.single, [
          'queued',
          ['queued', 'queued'],
        ]);
        expect(
          (await connection.execute(
            "SELECT count(*) FROM pg_indexes WHERE schemaname = 'enum_evolution' "
            "AND indexname = 'jobs_status_idx'",
          )).single.single,
          1,
        );
        expect(
          (await connection.execute(
            "SELECT count(*) FROM pg_constraint WHERE conname = 'status_reflexive'",
          )).single.single,
          1,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should execute a sealed concurrent index with structural recovery metadata',
      () async {
        const generator = RivetMigrationGenerator();
        final declaration = _constraintDeclaration();
        final users = (declaration['tables']! as List<Object?>).first! as Map<String, Object?>;
        final indexes = users['indexes']! as List<Object?>;
        users['indexes'] = <Object?>[];
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial',
        );
        await _applyLastMigration(connection, directory);
        users['indexes'] = indexes;
        final migrationId = await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'concurrent index',
        );
        final journal = jsonDecode(
          File('${directory.path}/journal.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
        final path = '${directory.path}/${entry['directory']}';
        final sqlFile = File('$path/migration.sql');
        sqlFile.writeAsStringSync(
          sqlFile.readAsStringSync().replaceFirst(
            'CREATE UNIQUE INDEX',
            'CREATE UNIQUE INDEX CONCURRENTLY',
          ),
        );
        final migrationFile = File('$path/migration.json');
        final migration = jsonDecode(migrationFile.readAsStringSync()) as Map<String, Object?>;
        final phase = ((migration['phases']! as List<Object?>).single! as Map<String, Object?>)
          ..['mode'] = 'nontransactional'
          ..['recovery'] = {
            'kind': 'catalog',
            'operationId': '22222222222222222222222222222222',
            'before': {
              'schema': 'auth',
              'table': 'users',
              'index': 'users_email_active',
              'exists': false,
            },
            'after': {
              'schema': 'auth',
              'table': 'users',
              'index': 'users_email_active',
              'method': 'btree',
              'terms': [
                {'column': 'email', 'descending': false},
              ],
              'predicate': '(active = true)',
              'options': <String, Object?>{},
              'unique': true,
              'valid': true,
              'ready': true,
            },
            'inspector': 'postgresql.index.v1',
          };
        migrationFile.writeAsStringSync(jsonEncode(migration));
        expect(phase['mode'], 'nontransactional');
        await RivetArtifactSealer().seal(
          directory: directory,
          migrationId: migrationId!,
        );
        await _applyLastMigration(connection, directory);

        final catalog = await connection.execute(
          'SELECT i.indisvalid, i.indisready, pg_get_indexdef(i.indexrelid) '
          'FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid '
          'JOIN pg_namespace n ON n.oid = c.relnamespace '
          "WHERE n.nspname = 'auth' AND c.relname = 'users_email_active'",
        );
        expect(catalog.single[0], true);
        expect(catalog.single[1], true);
        expect(
          catalog.single[2],
          allOf(
            contains('UNIQUE INDEX'),
            contains('(email)'),
            contains('WHERE (active = true)'),
          ),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should apply an enum rebuild before renaming its dependent table',
      () async {
        const generator = RivetMigrationGenerator();
        final declaration = _evolvingEnumDeclaration();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial enum',
        );
        await _applyLastMigration(connection, directory);
        await connection.execute(
          '''INSERT INTO enum_evolution.jobs (id, status, statuses) '''
          '''VALUES (1, 'done', ARRAY['queued', 'done']::enum_evolution.mood[])''',
        );

        (declaration['tables']! as List<Object?>).single! as Map<String, Object?>
          ..['name'] = 'tasks'
          ..['renamedFrom'] = 'jobs';
        final enumValue = (declaration['enums']! as List<Object?>).single! as Map<String, Object?>;
        final values = enumValue['values']! as List<Object?>;
        enumValue['values'] = values.reversed.toList();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'rebuild enum and rename table',
        );

        await _applyLastMigration(connection, directory);

        expect(
          (await connection.execute(
            'SELECT status::text FROM enum_evolution.tasks WHERE id = 1',
          )).single.single,
          'done',
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should rename a referenced table without dropping its primary key',
      () async {
        const generator = RivetMigrationGenerator();
        final declaration = _constraintDeclaration();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial constraints',
        );
        await _applyLastMigration(connection, directory);
        (declaration['tables']! as List<Object?>).first! as Map<String, Object?>
          ..['name'] = 'accounts'
          ..['renamedFrom'] = 'users';
        final projects = (declaration['tables']! as List<Object?>)[1]! as Map<String, Object?>;
        final foreignKey =
            (projects['constraints']! as List<Object?>).single! as Map<String, Object?>;
        (foreignKey['references']! as Map<String, Object?>)['table'] = 'accounts';
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'rename referenced table',
        );

        await _applyLastMigration(connection, directory);
        await connection.execute(
          "INSERT INTO auth.accounts (id, email, active) VALUES (1, 'a@example.com', true)",
        );
        await connection.execute('INSERT INTO work.projects (id, "ownerId") VALUES (1, 1)');
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should drop foreign keys before their referenced primary keys',
      () async {
        const generator = RivetMigrationGenerator();
        final declaration = _constraintDeclaration();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial constraints',
        );
        await _applyLastMigration(connection, directory);
        declaration['tables'] = <Object?>[];
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'drop related tables',
        );

        await _applyLastMigration(connection, directory);

        expect(
          (await connection.execute(
            "SELECT count(*) FROM pg_tables WHERE schemaname IN ('auth', 'work')",
          )).single.single,
          0,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

Map<String, Object?> _evolvingEnumDeclaration() => {
  'formatVersion': 1,
  'dialect': 'rivet',
  'name': 'enum_evolution',
  'tables': [
    {
      'schema': 'enum_evolution',
      'name': 'jobs',
      'columns': [
        _column('id', primaryKey: true),
        {
          'name': 'status',
          'storage': _enumStorage(nullable: false),
          'primaryKey': false,
        },
        {
          'name': 'statuses',
          'storage': {
            'kind': 'array',
            'nullable': false,
            'codecVersion': 1,
            'element': _enumStorage(nullable: false),
          },
          'primaryKey': false,
        },
      ],
      'indexes': [
        {
          'name': 'jobs_status_idx',
          'unique': true,
          'terms': [
            {'column': 'status', 'descending': false},
          ],
          'options': <String, Object?>{},
          'platforms': ['postgresql'],
        },
      ],
      'constraints': [
        {
          'name': 'status_reflexive',
          'kind': 'check',
          'columns': <String>[],
          'expression': _operator('=', _reference('status'), _reference('status')),
        },
      ],
    },
  ],
  'enums': [
    {
      'schema': 'enum_evolution',
      'name': 'mood',
      'values': [
        {'dartName': 'queued', 'label': 'queued'},
        {'dartName': 'complete', 'label': 'done'},
      ],
    },
  ],
  'requirements': <Object?>[],
};

Map<String, Object?> _enumStorage({required bool nullable}) => {
  'kind': 'enum',
  'nullable': nullable,
  'codecVersion': 1,
  'enum': {'schema': 'enum_evolution', 'name': 'mood'},
};

void _renameEnumReference(Map<String, Object?> storage) {
  if (storage['kind'] == 'enum') {
    storage['enum'] = {'schema': 'enum_evolution', 'name': 'state'};
  }
  if (storage['element'] case final Map<String, Object?> element) {
    _renameEnumReference(element);
  }
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

Map<String, Object?> _lastArtifact(Directory directory, String name) {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  return jsonDecode(File('${directory.path}/${entry['directory']}/$name').readAsStringSync())
      as Map<String, Object?>;
}

Future<void> _applyLastMigration(
  pg.Connection connection,
  Directory directory,
) async {
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
    if (phase['mode'] == 'nontransactional') {
      for (final value in phase['statements']! as List<Object?>) {
        await connection.execute(_statementSql(sqlBytes, value! as Map<String, Object?>));
      }
      continue;
    }
    await connection.runTx((transaction) async {
      for (final value in phase['statements']! as List<Object?>) {
        await transaction.execute(_statementSql(sqlBytes, value! as Map<String, Object?>));
      }
    });
  }
}

String _statementSql(List<int> sqlBytes, Map<String, Object?> statement) => utf8.decode(
  sqlBytes.sublist(
    statement['startByte']! as int,
    statement['endByte']! as int,
  ),
);

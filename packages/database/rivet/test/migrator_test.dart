import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet/rivet.dart';
import 'package:rivet_generator/rivet_generator.dart';
import 'package:rivet_generator/src/migration/sealer.dart';
import 'package:rivet_generator/src/migration/sql_parser.dart';
import 'package:test/test.dart';

import 'migration_fixture.dart';

void main() {
  group('RivetMigrator', () {
    final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL'];
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('rivet_migrator_test_');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    test('should reject invalid artifacts before opening a connection', () async {
      File('${directory.path}/journal.json').writeAsStringSync(
        '{"formatVersion":1,"formatVersion":1}',
      );
      final migrator = RivetMigrator(
        connection: RivetConnection.url(
          'postgresql://invalid:invalid@127.0.0.1:1/unreachable',
          sslMode: RivetSslMode.disable,
        ),
        directory: directory,
      );

      await expectLater(migrator.migrate(), throwsA(isA<FormatException>()));
    });

    test('should reject transaction-control SQL before opening a connection', () async {
      final migrationId = await const RivetMigrationGenerator().generate(
        schema: MigrationFixtureDatabaseRivetSchema.build(),
        directory: directory,
        name: 'initial',
      );
      final journal =
          jsonDecode(
                File('${directory.path}/journal.json').readAsStringSync(),
              )!
              as Map<String, Object?>;
      final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
      final artifactDirectory = '${directory.path}/${entry['directory']}';
      final migration =
          jsonDecode(
                File('$artifactDirectory/migration.json').readAsStringSync(),
              )!
              as Map<String, Object?>;
      final phase = (migration['phases']! as List<Object?>).first! as Map<String, Object?>;
      final statement = (phase['statements']! as List<Object?>).first! as Map<String, Object?>;
      final start = statement['startByte']! as int;
      final end = statement['endByte']! as int;
      final sqlFile = File('$artifactDirectory/migration.sql');
      final bytes = sqlFile.readAsBytesSync().toList(growable: true);
      const transactionControl = 'START/**/TRANSACTION';
      final padding = List.filled(end - start - transactionControl.length - 1, ' ').join();
      final replacement = utf8.encode('$transactionControl$padding;');
      bytes.replaceRange(start, end, replacement);
      sqlFile.writeAsBytesSync(bytes);
      await RivetArtifactSealer().seal(directory: directory, migrationId: migrationId!);

      await expectLater(
        RivetMigrator(
          connection: RivetConnection.url(
            'postgresql://invalid:invalid@127.0.0.1:1/unreachable',
            sslMode: RivetSslMode.disable,
          ),
          directory: directory,
        ).migrate(),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject a negative lock timeout', () {
      expect(
        () => RivetMigrator(
          connection: RivetConnection.url('postgresql://localhost/postgres'),
          directory: directory,
          lockTimeout: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test(
      'should apply a transactional migration once with durable receipts',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        final connection = RivetConnection.url(databaseUrl!, sslMode: RivetSslMode.disable);
        final fixture = await pg.Connection.openFromUrl(databaseUrl);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS work CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS enum_evolution CASCADE');

        await RivetMigrator(connection: connection, directory: directory).migrate();
        final firstReceipts = await fixture.execute(
          'SELECT "migrationId", "phaseId", status FROM _rivet.phase_receipts',
        );
        await RivetMigrator(connection: connection, directory: directory).migrate();
        final secondReceipts = await fixture.execute(
          'SELECT "migrationId", "phaseId", status FROM _rivet.phase_receipts',
        );

        expect(firstReceipts, hasLength(1));
        expect(firstReceipts.single[2], 'completed');
        expect(secondReceipts.map((row) => row.toList()), firstReceipts.map((row) => row.toList()));
        final journal = jsonDecode(
          File('${directory.path}/journal.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
        expect(firstReceipts.single[0], entry['id']);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject a resealed edit to applied migration history',
      () async {
        final migrationId = await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
        final migrator = RivetMigrator(
          connection: RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable),
          directory: directory,
        );
        await migrator.migrate();
        final journal =
            jsonDecode(
                  File('${directory.path}/journal.json').readAsStringSync(),
                )!
                as Map<String, Object?>;
        final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
        final sql = File('${directory.path}/${entry['directory']}/migration.sql');
        sql.writeAsStringSync('${sql.readAsStringSync()}\n-- edited after application\n');
        await RivetArtifactSealer().seal(
          directory: directory,
          migrationId: migrationId!,
        );

        await expectLater(migrator.migrate(), throwsA(isA<RivetMigrationException>()));
        expect(
          (await fixture.execute('SELECT count(*) FROM _rivet.migrations')).single.single,
          1,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should roll back migration effects and receipts when a statement fails',
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
        final migrationId = entry['id']! as String;
        final sql = File('${directory.path}/${entry['directory']}/migration.sql');
        final originalSql = sql.readAsStringSync();
        final lastStatement = parseRivetSqlStatements(originalSql).last;
        final bytes = utf8.encode(originalSql);
        sql.writeAsStringSync(
          '${utf8.decode(bytes.sublist(0, lastStatement['startByte']))}SELECT 1 / 0;\n',
        );
        await RivetArtifactSealer().seal(directory: directory, migrationId: migrationId);
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS work CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS enum_evolution CASCADE');

        await expectLater(
          RivetMigrator(
            connection: RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable),
            directory: directory,
          ).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );

        expect(
          (await fixture.execute("SELECT to_regnamespace('auth')")).single[0],
          isNull,
        );
        expect(
          (await fixture.execute('SELECT count(*) FROM _rivet.migrations')).single[0],
          0,
        );
        expect(
          (await fixture.execute('SELECT count(*) FROM _rivet.phase_receipts')).single[0],
          0,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should make one lock attempt at zero timeout without executing SQL',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
        await fixture.execute(
          pg.Sql.named('SELECT pg_advisory_lock(@key)'),
          parameters: {'key': int.parse('1151101229740241950')},
        );

        await expectLater(
          RivetMigrator(
            connection: RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable),
            directory: directory,
            lockTimeout: Duration.zero,
          ).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );

        expect(
          (await fixture.execute("SELECT to_regnamespace('_rivet')")).single[0],
          isNull,
        );
        expect((await fixture.execute("SELECT to_regnamespace('auth')")).single[0], isNull);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should serialize runners and re-read history after acquiring ownership',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS work CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS enum_evolution CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);

        await Future.wait([
          RivetMigrator(connection: connection, directory: directory).migrate(),
          RivetMigrator(connection: connection, directory: directory).migrate(),
        ]);

        expect(
          (await fixture.execute('SELECT count(*) FROM _rivet.migrations')).single[0],
          1,
        );
        expect(
          (await fixture.execute('SELECT count(*) FROM _rivet.phase_receipts')).single[0],
          1,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should apply and resume ordered transactional phases',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        await _splitLastMigrationIntoTwoPhases(directory);
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS work CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS enum_evolution CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);

        await RivetMigrator(connection: connection, directory: directory).migrate();
        await RivetMigrator(connection: connection, directory: directory).migrate();

        final receipts = await fixture.execute(
          'SELECT "phaseId", status FROM _rivet.phase_receipts ORDER BY "phaseId"',
        );
        expect(receipts.map((row) => row.toList()), [
          ['0', 'completed'],
          ['1', 'completed'],
        ]);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should commit an enum addition before a later phase uses the label',
      () async {
        final declaration = _enumMigrationDeclaration();
        const generator = RivetMigrationGenerator();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial enum',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS enum_evolution CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);
        await RivetMigrator(connection: connection, directory: directory).migrate();

        final enumValue = (declaration['enums']! as List<Object?>).single! as Map<String, Object?>;
        enumValue['values'] = [
          {'dartName': 'queued', 'label': 'queued'},
          {'dartName': 'running', 'label': 'running'},
          {'dartName': 'done', 'label': 'done'},
        ];
        final table = (declaration['tables']! as List<Object?>).single! as Map<String, Object?>;
        final status = (table['columns']! as List<Object?>)[1]! as Map<String, Object?>;
        status['default'] = {
          'formatVersion': 1,
          'kind': 'literal',
          'literalType': 'string',
          'value': 'running',
        };
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'add running',
        );

        await RivetMigrator(connection: connection, directory: directory).migrate();
        await fixture.execute('INSERT INTO enum_evolution.jobs (id) VALUES (1)');

        expect(
          (await fixture.execute(
            'SELECT status::text FROM enum_evolution.jobs WHERE id = 1',
          )).single.single,
          'running',
        );
        expect(
          (await fixture.execute(
            'SELECT count(*) FROM _rivet.phase_receipts WHERE "migrationId" = '
            '(SELECT id FROM _rivet.migrations ORDER BY ordinal DESC LIMIT 1)',
          )).single.single,
          2,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should resume after a process dies between transactional phase commits',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        await _splitLastMigrationIntoTwoPhases(
          directory,
          finalStatement: 'SELECT pg_sleep(2);',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS work CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS enum_evolution CASCADE');
        final process = await Process.start(
          Platform.resolvedExecutable,
          [
            'run',
            'packages/database/rivet/test/fixtures/migrator_process.dart',
            directory.path,
            databaseUrl,
          ],
          workingDirectory: Directory.current.path,
        );
        addTearDown(() {
          process.kill(ProcessSignal.sigkill);
        });
        await _waitForPhaseReceipt(fixture, 1);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(process.kill(ProcessSignal.sigkill), isTrue);
        await process.exitCode;

        expect(
          (await fixture.execute('SELECT count(*) FROM _rivet.phase_receipts')).single.single,
          1,
        );
        await RivetMigrator(
          connection: RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable),
          directory: directory,
        ).migrate();
        expect(
          (await fixture.execute('SELECT count(*) FROM _rivet.phase_receipts')).single.single,
          2,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should complete a concurrent btree index from structural evidence',
      () async {
        final declaration = _indexMigrationDeclaration();
        const generator = RivetMigrationGenerator();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial table',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS recovery CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);
        await RivetMigrator(connection: connection, directory: directory).migrate();

        final table = (declaration['tables']! as List<Object?>).single! as Map<String, Object?>;
        table['indexes'] = [
          {
            'name': 'users_name_idx',
            'unique': false,
            'terms': [
              {'column': 'name', 'descending': false},
            ],
            'predicate': null,
            'options': <String, Object?>{},
            'platforms': ['postgresql'],
          },
        ];
        final migrationId = await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'concurrent index',
        );
        await _sealConcurrentIndex(directory, migrationId!);

        await RivetMigrator(connection: connection, directory: directory).migrate();

        final index = await fixture.execute('''
          SELECT i.indisvalid, i.indisready, am.amname
          FROM pg_index i
          JOIN pg_class c ON c.oid = i.indexrelid
          JOIN pg_am am ON am.oid = c.relam
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'recovery' AND c.relname = 'users_name_idx'
        ''');
        expect(index.single, [true, true, 'btree']);
        final receipt = await fixture.execute('''
          SELECT status, "attemptId", evidence FROM _rivet.phase_receipts
          WHERE "migrationId" = '$migrationId'
        ''');
        expect(receipt.single[0], 'completed');
        expect(receipt.single[1], matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(receipt.single[2], isA<Map<String, Object?>>());
        final evidence = receipt.single[2]! as Map<String, Object?>;
        await fixture.execute(
          pg.Sql.named('''
            UPDATE _rivet.phase_receipts
            SET status = 'started', evidence = CAST(@evidence AS jsonb)
            WHERE "migrationId" = @migrationId
          '''),
          parameters: {
            'migrationId': migrationId,
            'evidence': jsonEncode(evidence['before']),
          },
        );

        await RivetMigrator(connection: connection, directory: directory).migrate();

        expect(
          (await fixture.execute(
            "SELECT status FROM _rivet.phase_receipts WHERE \"migrationId\" = '$migrationId'",
          )).single.single,
          'completed',
        );

        await fixture.execute('DROP INDEX recovery.users_name_idx');
        await fixture.execute(
          'CREATE INDEX users_name_idx ON recovery.users (name text_pattern_ops)',
        );
        await fixture.execute(
          pg.Sql.named('''
            UPDATE _rivet.phase_receipts
            SET status = 'started', evidence = CAST(@evidence AS jsonb)
            WHERE "migrationId" = @migrationId
          '''),
          parameters: {
            'migrationId': migrationId,
            'evidence': jsonEncode(evidence['before']),
          },
        );
        await expectLater(
          RivetMigrator(connection: connection, directory: directory).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );
        expect(
          (await fixture.execute(
            "SELECT pg_get_indexdef('recovery.users_name_idx'::regclass)",
          )).single.single,
          contains('text_pattern_ops'),
        );

        await fixture.execute('DROP TABLE recovery.users CASCADE');
        await fixture.execute('''
          CREATE TABLE recovery.users (id bigint PRIMARY KEY, name text NOT NULL)
        ''');
        await fixture.execute('CREATE INDEX users_name_idx ON recovery.users (name)');
        await expectLater(
          RivetMigrator(connection: connection, directory: directory).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should reject a preexisting index instead of treating it as completion',
      () async {
        final declaration = _indexMigrationDeclaration();
        const generator = RivetMigrationGenerator();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial table',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS recovery CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);
        await RivetMigrator(connection: connection, directory: directory).migrate();
        await fixture.execute(
          'CREATE INDEX users_name_idx ON recovery.users (id DESC)',
        );
        final table = (declaration['tables']! as List<Object?>).single! as Map<String, Object?>;
        table['indexes'] = [
          {
            'name': 'users_name_idx',
            'unique': false,
            'terms': [
              {'column': 'name', 'descending': false},
            ],
            'predicate': null,
            'options': <String, Object?>{},
            'platforms': ['postgresql'],
          },
        ];
        final migrationId = await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'concurrent index',
        );
        await _sealConcurrentIndex(directory, migrationId!);

        await expectLater(
          RivetMigrator(connection: connection, directory: directory).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );

        expect(
          (await fixture.execute(
            "SELECT pg_get_indexdef('recovery.users_name_idx'::regclass)",
          )).single.single,
          contains('(id DESC)'),
        );
        expect(
          (await fixture.execute(
            "SELECT count(*) FROM _rivet.migrations WHERE id = '$migrationId'",
          )).single.single,
          0,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should execute reviewed custom SQL only when its checks prove the precondition',
      () async {
        final declaration = _indexMigrationDeclaration();
        const generator = RivetMigrationGenerator();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial table',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS recovery CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);
        await RivetMigrator(connection: connection, directory: directory).migrate();
        declaration['tables'] = [
          ...(declaration['tables']! as List<Object?>),
          _simpleTable('audits'),
        ];
        final migrationId = await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'custom checked table',
        );
        await _sealRecovery(directory, migrationId!, {
          'kind': 'catalog',
          'operationId': '33333333333333333333333333333333',
          'before': {'table': 'recovery.audits', 'exists': false},
          'after': {'table': 'recovery.audits', 'exists': true},
          'checks': [
            {
              'sql': r'SELECT to_regclass($1) IS NOT NULL',
              'parameters': [
                {'type': 'string', 'value': 'recovery.audits'},
              ],
              'expected': true,
            },
          ],
        });

        await RivetMigrator(connection: connection, directory: directory).migrate();

        expect(
          (await fixture.execute(
            "SELECT to_regclass('recovery.audits') IS NOT NULL",
          )).single.single,
          isTrue,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve manual SQL as started until explicit resolution',
      () async {
        final declaration = _indexMigrationDeclaration();
        const generator = RivetMigrationGenerator();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial table',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS recovery CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);
        await RivetMigrator(connection: connection, directory: directory).migrate();
        declaration['tables'] = [
          ...(declaration['tables']! as List<Object?>),
          _simpleTable('manual_effect'),
        ];
        final migrationId = await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'manual table',
        );
        await _sealRecovery(directory, migrationId!, {
          'kind': 'manual',
          'operationId': '44444444444444444444444444444444',
          'before': {'description': 'manual effect absent'},
          'after': {'description': 'operator verified manual effect'},
        });

        await expectLater(
          RivetMigrator(connection: connection, directory: directory).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );
        await expectLater(
          RivetMigrator(connection: connection, directory: directory).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );

        final receipts = await fixture.execute(
          "SELECT status FROM _rivet.phase_receipts WHERE \"migrationId\" = '$migrationId'",
        );
        expect(receipts.single.single, 'started');
        expect(
          (await fixture.execute(
            "SELECT to_regclass('recovery.manual_effect') IS NOT NULL",
          )).single.single,
          isTrue,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should report an uninitialized database without bootstrapping history',
      () async {
        await const RivetMigrationGenerator().generate(
          schema: MigrationFixtureDatabaseRivetSchema.build(),
          directory: directory,
          name: 'initial',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');

        final status = await RivetMigrator(
          connection: RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable),
          directory: directory,
        ).status();

        expect(status.migrations.single.phases.single.state, RivetMigrationPhaseState.pending);
        expect(
          (await fixture.execute("SELECT to_regnamespace('_rivet')")).single.single,
          isNull,
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should report completed and interrupted receipts without changing them',
      () async {
        final declaration = _indexMigrationDeclaration();
        const generator = RivetMigrationGenerator();
        await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'initial table',
        );
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
        await fixture.execute('DROP SCHEMA IF EXISTS recovery CASCADE');
        final connection = RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable);
        await RivetMigrator(connection: connection, directory: directory).migrate();
        declaration['tables'] = [
          ...(declaration['tables']! as List<Object?>),
          _simpleTable('manual_status'),
        ];
        final migrationId = await generator.generateDeclaration(
          declaration: declaration,
          directory: directory,
          name: 'manual status',
        );
        await _sealRecovery(directory, migrationId!, {
          'kind': 'manual',
          'operationId': '55555555555555555555555555555555',
          'before': {'description': 'absent'},
          'after': {'description': 'present'},
        });
        await expectLater(
          RivetMigrator(connection: connection, directory: directory).migrate(),
          throwsA(isA<RivetMigrationException>()),
        );
        final before = await fixture.execute(
          'SELECT status, "attemptId", evidence FROM _rivet.phase_receipts '
          'ORDER BY "migrationId", "phaseId"',
        );

        final status = await RivetMigrator(
          connection: connection,
          directory: directory,
        ).status();
        final after = await fixture.execute(
          'SELECT status, "attemptId", evidence FROM _rivet.phase_receipts '
          'ORDER BY "migrationId", "phaseId"',
        );

        expect(status.migrations.first.phases.single.state, RivetMigrationPhaseState.completed);
        expect(status.migrations.last.phases.single.state, RivetMigrationPhaseState.started);
        expect(status.migrations.last.phases.single.attemptId, isNotEmpty);
        expect(status.migrations.last.phases.single.evidence, isNotEmpty);
        expect(after.map((row) => row.toList()), before.map((row) => row.toList()));
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should complete manual recovery only with matching operator input and audit it',
      () async {
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        final recovery = await _prepareManualRecovery(
          directory,
          databaseUrl,
          fixture,
          tableName: 'manual_complete',
        );

        await expectLater(
          recovery.migrator.resolve(
            migrationId: recovery.migrationId,
            phaseId: '0',
            expectedChecksum: recovery.checksum,
            attemptId: recovery.attemptId,
            reason: '   ',
            resolution: RivetMigrationResolution.completed,
          ),
          throwsArgumentError,
        );
        await expectLater(
          recovery.migrator.resolve(
            migrationId: recovery.migrationId,
            phaseId: '0',
            expectedChecksum: List.filled(64, '0').join(),
            attemptId: recovery.attemptId,
            reason: 'Verified the manually created table.',
            resolution: RivetMigrationResolution.completed,
          ),
          throwsA(isA<RivetMigrationException>()),
        );

        await recovery.migrator.resolve(
          migrationId: recovery.migrationId,
          phaseId: '0',
          expectedChecksum: recovery.checksum,
          attemptId: recovery.attemptId,
          reason: 'Verified the manually created table.',
          resolution: RivetMigrationResolution.completed,
        );

        final status = await recovery.migrator.status();
        expect(status.migrations.last.phases.single.state, RivetMigrationPhaseState.completed);
        final audits = await fixture.execute('''
          SELECT "migrationId", "phaseId", checksum, "attemptId", resolution, reason
          FROM _rivet.recovery_audits
        ''');
        expect(audits.single, [
          recovery.migrationId,
          '0',
          recovery.checksum,
          recovery.attemptId,
          'completed',
          'Verified the manually created table.',
        ]);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should preserve the old attempt in an audit before retrying manual work',
      () async {
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        final recovery = await _prepareManualRecovery(
          directory,
          databaseUrl,
          fixture,
          tableName: 'manual_retry',
        );
        await fixture.execute('DROP TABLE recovery.manual_retry');

        await recovery.migrator.resolve(
          migrationId: recovery.migrationId,
          phaseId: '0',
          expectedChecksum: recovery.checksum,
          attemptId: recovery.attemptId,
          reason: 'Removed the partial object and approved one retry.',
          resolution: RivetMigrationResolution.retry,
        );
        final retried = await recovery.migrator.status();
        final newAttempt = retried.migrations.last.phases.single.attemptId;
        expect(newAttempt, isNot(recovery.attemptId));

        await expectLater(recovery.migrator.migrate(), throwsA(isA<RivetMigrationException>()));
        expect(
          (await fixture.execute(
            "SELECT to_regclass('recovery.manual_retry') IS NOT NULL",
          )).single.single,
          isTrue,
        );
        await fixture.execute('DROP TABLE recovery.manual_retry');
        await expectLater(recovery.migrator.migrate(), throwsA(isA<RivetMigrationException>()));
        expect(
          (await fixture.execute(
            "SELECT to_regclass('recovery.manual_retry') IS NOT NULL",
          )).single.single,
          isFalse,
        );
        await recovery.migrator.resolve(
          migrationId: recovery.migrationId,
          phaseId: '0',
          expectedChecksum: recovery.checksum,
          attemptId: newAttempt!,
          reason: 'Verified the retried manual operation.',
          resolution: RivetMigrationResolution.completed,
        );

        final audits = await fixture.execute(
          'SELECT "attemptId", resolution FROM _rivet.recovery_audits ORDER BY id',
        );
        expect(audits.map((row) => row.toList()), [
          [recovery.attemptId, 'retry'],
          [newAttempt, 'completed'],
        ]);
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );

    test(
      'should resolve an interrupted attempt through the deployment CLI process',
      () async {
        final fixture = await pg.Connection.openFromUrl(databaseUrl!);
        addTearDown(fixture.close);
        final recovery = await _prepareManualRecovery(
          directory,
          databaseUrl,
          fixture,
          tableName: 'manual_cli',
        );

        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'rivet_generator:rivet',
            'resolve',
            '--dir',
            directory.path,
            '--connection-env',
            'DEPLOY_DATABASE_URL',
            '--migration',
            recovery.migrationId,
            '--phase',
            '0',
            '--checksum',
            recovery.checksum,
            '--attempt',
            recovery.attemptId,
            '--reason',
            'Verified from the deployment CLI test.',
            '--resolution',
            'completed',
          ],
          workingDirectory: Directory.current.path,
          environment: {
            ...Platform.environment,
            'DEPLOY_DATABASE_URL': databaseUrl,
          },
        );

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          (await fixture.execute(
            'SELECT resolution, reason FROM _rivet.recovery_audits',
          )).single,
          ['completed', 'Verified from the deployment CLI test.'],
        );
      },
      skip: databaseUrl == null ? 'RIVET_TEST_DATABASE_URL is not configured.' : false,
    );
  });
}

Future<
  ({
    RivetMigrator migrator,
    String migrationId,
    String checksum,
    String attemptId,
  })
>
_prepareManualRecovery(
  Directory directory,
  String databaseUrl,
  pg.Connection fixture, {
  required String tableName,
}) async {
  final declaration = _indexMigrationDeclaration();
  const generator = RivetMigrationGenerator();
  await generator.generateDeclaration(
    declaration: declaration,
    directory: directory,
    name: 'initial table',
  );
  await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
  await fixture.execute('DROP SCHEMA IF EXISTS recovery CASCADE');
  final migrator = RivetMigrator(
    connection: RivetConnection.url(databaseUrl, sslMode: RivetSslMode.disable),
    directory: directory,
  );
  await migrator.migrate();
  declaration['tables'] = [
    ...(declaration['tables']! as List<Object?>),
    _simpleTable(tableName),
  ];
  final migrationId = await generator.generateDeclaration(
    declaration: declaration,
    directory: directory,
    name: 'manual recovery',
  );
  await _sealRecovery(directory, migrationId!, {
    'kind': 'manual',
    'operationId': '66666666666666666666666666666666',
    'before': {'description': '$tableName absent'},
    'after': {'description': '$tableName present'},
  });
  await expectLater(migrator.migrate(), throwsA(isA<RivetMigrationException>()));
  final status = await migrator.status();
  final phase = status.migrations.last.phases.single;
  return (
    migrator: migrator,
    migrationId: migrationId,
    checksum: status.migrations.last.checksum,
    attemptId: phase.attemptId!,
  );
}

Future<void> _splitLastMigrationIntoTwoPhases(
  Directory directory, {
  String? finalStatement,
}) async {
  final journal = jsonDecode(
    File('${directory.path}/journal.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  final migrationFile = File('${directory.path}/${entry['directory']}/migration.json');
  final migration = jsonDecode(migrationFile.readAsStringSync()) as Map<String, Object?>;
  final original = (migration['phases']! as List<Object?>).single! as Map<String, Object?>;
  final statements = original['statements']! as List<Object?>;
  if (finalStatement != null) {
    final sqlFile = File('${directory.path}/${entry['directory']}/migration.sql');
    final originalSql = sqlFile.readAsStringSync();
    final lastStatement = parseRivetSqlStatements(originalSql).last;
    final bytes = utf8.encode(originalSql);
    sqlFile.writeAsStringSync(
      '${utf8.decode(bytes.sublist(0, lastStatement['startByte']))}$finalStatement\n',
    );
  }
  migration['phases'] = [
    {...original, 'statements': statements.sublist(0, statements.length - 1)},
    {...original, 'id': '1', 'statements': statements.sublist(statements.length - 1)},
  ];
  migrationFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(migration)}\n');
  await RivetArtifactSealer().seal(directory: directory, migrationId: entry['id']! as String);
}

Future<void> _waitForPhaseReceipt(pg.Connection connection, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final result = await connection.execute(
        'SELECT count(*) FROM _rivet.phase_receipts',
      );
      if (result.single.single == count) return;
    } on pg.ServerException {
      // The subprocess has not bootstrapped the reserved schema yet.
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('Timed out waiting for $count phase receipts.');
}

Map<String, Object?> _enumMigrationDeclaration() => {
  'formatVersion': 1,
  'dialect': 'rivet',
  'name': 'enum_migration',
  'tables': [
    {
      'schema': 'enum_evolution',
      'name': 'jobs',
      'columns': [
        {
          'name': 'id',
          'storage': {'kind': 'integer', 'nullable': false, 'codecVersion': 1},
          'primaryKey': true,
        },
        {
          'name': 'status',
          'storage': {
            'kind': 'enum',
            'nullable': false,
            'codecVersion': 1,
            'enum': {'schema': 'enum_evolution', 'name': 'job_status'},
          },
          'primaryKey': false,
          'default': {
            'formatVersion': 1,
            'kind': 'literal',
            'literalType': 'string',
            'value': 'queued',
          },
        },
      ],
      'indexes': <Object?>[],
      'constraints': <Object?>[],
    },
  ],
  'enums': [
    {
      'schema': 'enum_evolution',
      'name': 'job_status',
      'values': [
        {'dartName': 'queued', 'label': 'queued'},
        {'dartName': 'done', 'label': 'done'},
      ],
    },
  ],
  'requirements': <Object?>[],
};

Map<String, Object?> _indexMigrationDeclaration() => {
  'formatVersion': 1,
  'dialect': 'rivet',
  'name': 'index_migration',
  'tables': [
    {
      'schema': 'recovery',
      'name': 'users',
      'columns': [
        {
          'name': 'id',
          'storage': {'kind': 'integer', 'nullable': false, 'codecVersion': 1},
          'primaryKey': true,
        },
        {
          'name': 'name',
          'storage': {'kind': 'text', 'nullable': false, 'codecVersion': 1},
          'primaryKey': false,
        },
      ],
      'indexes': <Object?>[],
      'constraints': <Object?>[],
    },
  ],
  'enums': <Object?>[],
  'requirements': <Object?>[],
};

Map<String, Object?> _simpleTable(String name) => {
  'schema': 'recovery',
  'name': name,
  'columns': [
    {
      'name': 'id',
      'storage': {'kind': 'integer', 'nullable': false, 'codecVersion': 1},
      'primaryKey': true,
    },
  ],
  'indexes': <Object?>[],
  'constraints': <Object?>[],
};

Future<void> _sealConcurrentIndex(Directory directory, String migrationId) async {
  final journal = jsonDecode(
    File('${directory.path}/journal.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  final path = '${directory.path}/${entry['directory']}';
  final sqlPath = '$path/migration.sql';
  final sql = File(sqlPath).readAsStringSync();
  File(sqlPath).writeAsStringSync(
    sql.replaceFirst('CREATE INDEX', 'CREATE INDEX CONCURRENTLY'),
  );
  final migrationFile = File('$path/migration.json');
  final migration = jsonDecode(migrationFile.readAsStringSync()) as Map<String, Object?>;
  final phase = (migration['phases']! as List<Object?>).single! as Map<String, Object?>;
  migration['phases'] = [
    {
      ...phase,
      'mode': 'nontransactional',
      'recovery': {
        'kind': 'catalog',
        'operationId': '22222222222222222222222222222222',
        'before': {
          'schema': 'recovery',
          'table': 'users',
          'index': 'users_name_idx',
          'exists': false,
        },
        'after': {
          'schema': 'recovery',
          'table': 'users',
          'index': 'users_name_idx',
          'method': 'btree',
          'terms': [
            {'column': 'name', 'descending': false},
          ],
          'predicate': null,
          'options': <String, Object?>{},
          'unique': false,
          'valid': true,
          'ready': true,
        },
        'inspector': 'postgresql.index.v1',
      },
    },
  ];
  migrationFile.writeAsStringSync(jsonEncode(migration));
  await RivetArtifactSealer().seal(directory: directory, migrationId: migrationId);
}

Future<void> _sealRecovery(
  Directory directory,
  String migrationId,
  Map<String, Object?> recovery,
) async {
  final journal = jsonDecode(
    File('${directory.path}/journal.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  final migrationFile = File(
    '${directory.path}/${entry['directory']}/migration.json',
  );
  final migration = jsonDecode(migrationFile.readAsStringSync()) as Map<String, Object?>;
  final phase = (migration['phases']! as List<Object?>).single! as Map<String, Object?>;
  migration['phases'] = [
    {...phase, 'mode': 'nontransactional', 'recovery': recovery},
  ];
  migrationFile.writeAsStringSync(jsonEncode(migration));
  await RivetArtifactSealer().seal(directory: directory, migrationId: migrationId);
}

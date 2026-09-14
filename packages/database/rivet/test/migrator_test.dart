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
  });
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

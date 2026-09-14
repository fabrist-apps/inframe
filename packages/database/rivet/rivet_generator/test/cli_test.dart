import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;
import 'package:rivet_generator/src/cli.dart';
import 'package:test/test.dart';

void main() {
  test('generate, seal, and check should share one CLI artifact contract', () async {
    final directory = Directory.systemTemp.createTempSync('rivet_cli_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final stdoutFile = File('${directory.path}/stdout.txt');
    final stderrFile = File('${directory.path}/stderr.txt');
    final stdout = stdoutFile.openWrite();
    final stderr = stderrFile.openWrite();
    addTearDown(stdout.close);
    addTearDown(stderr.close);
    final cli = RivetCli(stdout: stdout, stderr: stderr);
    final library = Uri.file(
      '${Directory.current.path}/packages/database/rivet/test/migration_fixture.dart',
    ).toString();
    final migrations = '${directory.path}/migrations';

    expect(
      await cli.run([
        'generate',
        '--database',
        '$library#MigrationFixtureDatabase',
        '--out',
        migrations,
        '--name',
        'initial',
      ]),
      0,
    );
    final journal =
        jsonDecode(File('$migrations/journal.json').readAsStringSync()) as Map<String, Object?>;
    final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
    final migrationId = entry['id']! as String;
    final sql = File('$migrations/${entry['directory']}/migration.sql');
    sql.writeAsStringSync(
      sql.readAsStringSync().replaceFirst(
        'CREATE SCHEMA',
        '-- reviewed λ; comment\nCREATE SCHEMA',
      ),
    );

    expect(
      await cli.run(['seal', '--dir', migrations, '--migration', migrationId]),
      0,
    );
    expect(await cli.run(['check', '--dir', migrations]), 0);
    expect(
      await cli.run([
        'seal',
        '--dir',
        migrations,
        '--migration',
        'ffffffffffffffffffffffffffffffff',
      ]),
      64,
    );
  });

  test(
    'deployment commands should migrate and report status from a named environment variable',
    () async {
      final databaseUrl = Platform.environment['RIVET_TEST_DATABASE_URL']!;
      final directory = Directory.systemTemp.createTempSync('rivet_cli_deploy_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final fixture = await pg.Connection.openFromUrl(databaseUrl);
      addTearDown(fixture.close);
      await fixture.execute('DROP SCHEMA IF EXISTS _rivet CASCADE');
      await fixture.execute('DROP SCHEMA IF EXISTS auth CASCADE');
      final outputFile = File('${directory.path}/stdout.txt');
      final errorFile = File('${directory.path}/stderr.txt');
      final output = outputFile.openWrite();
      final errors = errorFile.openWrite();
      addTearDown(output.close);
      addTearDown(errors.close);
      final cli = RivetCli(
        stdout: output,
        stderr: errors,
        environment: {'DEPLOY_DATABASE_URL': databaseUrl},
      );
      final library = Uri.file(
        '${Directory.current.path}/packages/database/rivet/test/migration_fixture.dart',
      ).toString();
      final migrations = '${directory.path}/migrations';
      expect(
        await cli.run([
          'generate',
          '--database',
          '$library#MigrationFixtureDatabase',
          '--out',
          migrations,
          '--name',
          'initial',
        ]),
        0,
      );

      final migrateArguments = [
        'run',
        'rivet_generator:rivet',
        'migrate',
        '--dir',
        migrations,
        '--connection-env',
        'DEPLOY_DATABASE_URL',
      ];
      final environment = {
        ...Platform.environment,
        'DEPLOY_DATABASE_URL': databaseUrl,
      };
      final firstMigration = await Process.run(
        Platform.resolvedExecutable,
        migrateArguments,
        workingDirectory: Directory.current.path,
        environment: environment,
      );
      expect(firstMigration.exitCode, 0, reason: '${firstMigration.stderr}');
      final secondMigration = await Process.run(
        Platform.resolvedExecutable,
        migrateArguments,
        workingDirectory: Directory.current.path,
        environment: environment,
      );
      expect(secondMigration.exitCode, 0, reason: '${secondMigration.stderr}');
      final statusResult = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          'rivet_generator:rivet',
          'status',
          '--dir',
          migrations,
          '--connection-env',
          'DEPLOY_DATABASE_URL',
        ],
        workingDirectory: Directory.current.path,
        environment: environment,
      );
      expect(statusResult.exitCode, 0, reason: '${statusResult.stderr}');
      final status = jsonDecode((statusResult.stdout as String).trim()) as Map<String, Object?>;
      expect(status['databaseId'], isNotEmpty);
      final migrationsStatus = status['migrations']! as List<Object?>;
      final phases = (migrationsStatus.single! as Map<String, Object?>)['phases']! as List<Object?>;
      expect((phases.single! as Map<String, Object?>)['state'], 'completed');
    },
    skip: Platform.environment['RIVET_TEST_DATABASE_URL'] == null
        ? 'RIVET_TEST_DATABASE_URL is not configured.'
        : false,
  );

  test('deployment failures should redact credentials', () async {
    final directory = Directory.systemTemp.createTempSync('rivet_cli_redact_test_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/journal.json').writeAsStringSync('{}');
    final output = File('${directory.path}/stdout.txt').openWrite();
    final errorFile = File('${directory.path}/stderr.txt');
    final errors = errorFile.openWrite();
    addTearDown(output.close);
    addTearDown(errors.close);
    const password = 'credential-that-must-not-leak';
    final cli = RivetCli(
      stdout: output,
      stderr: errors,
      environment: const {
        'DEPLOY_DATABASE_URL': 'postgresql://operator:$password@127.0.0.1:1/missing',
      },
    );

    expect(
      await cli.run([
        'status',
        '--dir',
        directory.path,
        '--connection-env',
        'DEPLOY_DATABASE_URL',
      ]),
      64,
    );
    await errors.flush();
    expect(errorFile.readAsStringSync(), isNot(contains(password)));
  });
}

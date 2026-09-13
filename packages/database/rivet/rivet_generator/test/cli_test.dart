import 'dart:convert';
import 'dart:io';

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
}

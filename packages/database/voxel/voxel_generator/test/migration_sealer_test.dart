import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:voxel_generator/src/cli.dart';
import 'package:voxel_generator/src/migration/sealer.dart';
import 'package:voxel_generator/voxel_generator.dart';

void main() {
  group('VoxelArtifactSealer', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('voxel_sealer_test_');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    test('should reparse reviewed UTF-8 comments and quoted semicolons', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      final oldChecksum = artifacts.entry['checksum'];
      artifacts.sql.writeAsStringSync(
        artifacts.sql.readAsStringSync().replaceFirst(
          'CREATE TABLE',
          "-- café; reviewed\n/* quoted 'λ;value' */\nCREATE TABLE",
        ),
      );

      await VoxelArtifactSealer().seal(
        directory: directory,
        migrationId: migrationId,
      );

      final sealed = _artifacts(directory);
      final migration = jsonDecode(sealed.migration.readAsStringSync()) as Map<String, Object?>;
      final phase = (migration['phases']! as List<Object?>).single! as Map<String, Object?>;
      final range = (phase['statements']! as List<Object?>).single! as Map<String, Object?>;
      final bytes = sealed.sql.readAsBytesSync();
      expect(
        utf8.decode(bytes.sublist(range['startByte']! as int, range['endByte']! as int)),
        contains('café'),
      );
      expect(sealed.entry['checksum'], isNot(oldChecksum));
      await const VoxelMigrationChecker().check(directory: directory);
    });

    test('should reject ambiguous statement counts without changing metadata', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      final oldMigration = artifacts.migration.readAsStringSync();
      final oldJournal = File('${directory.path}/journal.json').readAsStringSync();
      artifacts.sql.writeAsStringSync('${artifacts.sql.readAsStringSync()}SELECT 1;\n');

      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(isA<FormatException>()),
      );

      expect(artifacts.migration.readAsStringSync(), oldMigration);
      expect(File('${directory.path}/journal.json').readAsStringSync(), oldJournal);
    });

    test('should reject malformed SQL and cross-scope recovery checks', () async {
      final migrationId = await _generate(directory);
      var artifacts = _artifacts(directory);
      artifacts.sql.writeAsStringSync("SELECT 'unterminated;");
      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(isA<FormatException>()),
      );

      directory
        ..deleteSync(recursive: true)
        ..createSync();
      final nextMigrationId = await _generate(directory);
      artifacts = _artifacts(directory);
      final migration = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      ((migration['phases']! as List<Object?>).single! as Map<String, Object?>)
        ..['mode'] = 'nontransactional'
        ..['recovery'] = {
          'kind': 'catalog',
          'operationId': '33333333333333333333333333333333',
          'before': {'description': 'users absent'},
          'after': {'description': 'users table created'},
          'checks': [
            {
              'sql': 'SELECT EXISTS (SELECT 1 FROM "other".sqlite_schema)',
              'parameters': <Object?>[],
              'expected': true,
            },
          ],
        };
      artifacts.migration.writeAsStringSync(jsonEncode(migration));
      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: nextMigrationId),
        throwsA(isA<FormatException>()),
      );
    });

    test('should seal catalog recovery with typed target-scope checks', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      final migration = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      ((migration['phases']! as List<Object?>).single! as Map<String, Object?>)
        ..['mode'] = 'nontransactional'
        ..['recovery'] = {
          'kind': 'catalog',
          'operationId': '11111111111111111111111111111111',
          'before': {'schema': 'auth', 'table': 'users', 'exists': false},
          'after': {'schema': 'auth', 'table': 'users', 'exists': true},
          'checks': [
            {
              'sql': 'SELECT NOT EXISTS (SELECT 1 FROM "auth".sqlite_schema WHERE name = ?)',
              'parameters': [
                {'type': 'string', 'value': 'users'},
              ],
              'expected': true,
            },
            {
              'sql': 'SELECT EXISTS (SELECT 1 FROM "auth".sqlite_schema WHERE name = ?)',
              'parameters': [
                {'type': 'string', 'value': 'users'},
              ],
              'expected': true,
            },
          ],
        };
      artifacts.migration.writeAsStringSync(jsonEncode(migration));

      await VoxelArtifactSealer().seal(
        directory: directory,
        migrationId: migrationId,
      );
      await const VoxelMigrationChecker().check(directory: directory);
    });

    test('should expose seal through the command line contract', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      artifacts.sql.writeAsStringSync('-- reviewed\n${artifacts.sql.readAsStringSync()}');
      final stdoutFile = File('${directory.path}/stdout.txt');
      final stderrFile = File('${directory.path}/stderr.txt');
      final stdout = stdoutFile.openWrite();
      final stderr = stderrFile.openWrite();
      addTearDown(stdout.close);
      addTearDown(stderr.close);
      final cli = VoxelCli(stdout: stdout, stderr: stderr);

      expect(
        await cli.run(['seal', '--dir', directory.path, '--migration', migrationId]),
        0,
      );
      expect(await cli.run(['check', '--dir', directory.path]), 0);
    });

    test('should preserve explicit phase ownership across reviewed multi-file SQL', () async {
      final id = await const VoxelMigrationGenerator().generateDeclaration(
        declaration: _declaration(secondScope: true),
        directory: directory,
        name: 'multi file',
      );
      final artifacts = _artifacts(directory);
      final before = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      final beforeScopes = [
        for (final phase in before['phases']! as List<Object?>)
          (phase! as Map<String, Object?>)['scopeId'],
      ];
      artifacts.sql.writeAsStringSync(
        artifacts.sql.readAsStringSync().replaceAll('CREATE TABLE', '-- reviewed\nCREATE TABLE'),
      );

      await VoxelArtifactSealer().seal(directory: directory, migrationId: id!);

      final after =
          jsonDecode(_artifacts(directory).migration.readAsStringSync()) as Map<String, Object?>;
      expect(
        [
          for (final phase in after['phases']! as List<Object?>)
            (phase! as Map<String, Object?>)['scopeId'],
        ],
        beforeScopes,
      );
    });

    test('should reject write scopes that cannot share the phase receipt', () async {
      final migrationId = await const VoxelMigrationGenerator().generateDeclaration(
        declaration: _declaration(secondScope: true),
        directory: directory,
        name: 'multi file',
      );
      final artifacts = _artifacts(directory);
      final migration = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      final phases = (migration['phases']! as List<Object?>).cast<Map<String, Object?>>();
      final firstScope = phases.first['scopeId'];
      final secondScope = phases.last['scopeId'];
      phases.first['writeScopeIds'] = [firstScope, secondScope];
      artifacts.migration.writeAsStringSync(jsonEncode(migration));

      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId!),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('exactly its receipt scope'),
          ),
        ),
      );
    });

    test('should reject duplicate or unknown declared write scopes', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      final migration = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      final phase = (migration['phases']! as List<Object?>).single! as Map<String, Object?>;
      phase['writeScopeIds'] = [phase['scopeId'], phase['scopeId']];
      artifacts.migration.writeAsStringSync(jsonEncode(migration));

      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(
          isA<FormatException>().having((error) => error.message, 'message', contains('duplicate')),
        ),
      );

      phase['writeScopeIds'] = ['ffffffffffffffffffffffffffffffff'];
      artifacts.migration.writeAsStringSync(jsonEncode(migration));
      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(
          isA<FormatException>().having((error) => error.message, 'message', contains('unknown')),
        ),
      );
    });

    test('should reject reviewed rebuild SQL that diverges from its table metadata', () async {
      final migrationId = await _generateRebuild(directory);
      final artifacts = _artifacts(directory);
      artifacts.sql.writeAsStringSync(
        artifacts.sql.readAsStringSync().replaceAll(
          '__voxel_rebuild_',
          '__reviewed_rebuild_',
        ),
      );

      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('reviewed SQL statements'),
          ),
        ),
      );
    });

    test('should allow an explicitly manual nontransactional recovery contract', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      final migration = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      ((migration['phases']! as List<Object?>).single! as Map<String, Object?>)
        ..['mode'] = 'nontransactional'
        ..['recovery'] = {
          'kind': 'manual',
          'operationId': '22222222222222222222222222222222',
          'before': {'description': 'users absent'},
          'after': {'description': 'operator verified users table'},
        };
      artifacts.migration.writeAsStringSync(jsonEncode(migration));

      await VoxelArtifactSealer().seal(
        directory: directory,
        migrationId: migrationId,
      );
      await const VoxelMigrationChecker().check(directory: directory);
    });

    test('should require settled history corrections to use a new migration', () async {
      final firstId = await _generate(directory);
      final changed = _declaration();
      final table = (changed['tables']! as List<Object?>).single! as Map<String, Object?>;
      (table['columns']! as List<Object?>).add({
        'name': 'name',
        'storage': {'kind': 'text', 'nullable': true, 'codecVersion': 1},
        'primaryKey': false,
      });
      await const VoxelMigrationGenerator().generateDeclaration(
        declaration: changed,
        directory: directory,
        name: 'add name',
      );

      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: firstId),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject snapshot records outside the versioned artifact schema', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      final entryDirectory = artifacts.migration.parent.path;
      final snapshotFile = File('$entryDirectory/snapshot.json');
      final snapshot = jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>;
      final table = (snapshot['tables']! as List<Object?>).single! as Map<String, Object?>;
      final column = (table['columns']! as List<Object?>).single! as Map<String, Object?>;
      column['storage'] = {'kind': 'unsupported_future_type'};
      snapshotFile.writeAsStringSync(jsonEncode(snapshot));

      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject the minimum 64-bit integer as non-interoperable JSON', () async {
      final migrationId = await _generate(directory);
      final artifacts = _artifacts(directory);
      final snapshotFile = File('${artifacts.migration.parent.path}/snapshot.json');
      final snapshot = jsonDecode(snapshotFile.readAsStringSync()) as Map<String, Object?>;
      (snapshot['requirements']! as List<Object?>).add({
        'unsupportedInteger': -9223372036854775808,
      });
      snapshotFile.writeAsStringSync(jsonEncode(snapshot));

      await expectLater(
        VoxelArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Future<String> _generate(Directory directory) async {
  final id = await const VoxelMigrationGenerator().generateDeclaration(
    declaration: _declaration(),
    directory: directory,
    name: 'initial',
  );
  return id!;
}

Future<String> _generateRebuild(Directory directory) async {
  const generator = VoxelMigrationGenerator();
  final initial = _declaration();
  await generator.generateDeclaration(
    declaration: initial,
    directory: directory,
    name: 'initial',
  );
  final changed = jsonDecode(jsonEncode(initial)) as Map<String, Object?>;
  final table = (changed['tables']! as List<Object?>).single! as Map<String, Object?>;
  final id = (table['columns']! as List<Object?>).single! as Map<String, Object?>;
  id['storage'] = {'kind': 'text', 'nullable': false, 'codecVersion': 1};
  return (await generator.generateDeclaration(
    declaration: changed,
    directory: directory,
    name: 'rebuild users',
    storageTransforms: {'auth.users.id': 'CAST("id" AS TEXT)'},
  ))!;
}

Map<String, Object?> _declaration({bool secondScope = false}) => {
  'formatVersion': 1,
  'dialect': 'voxel',
  'name': 'seal',
  'tables': [
    {
      'schema': 'auth',
      'name': 'users',
      'columns': [
        {
          'name': 'id',
          'storage': {'kind': 'integer', 'nullable': false, 'codecVersion': 1},
          'primaryKey': true,
        },
      ],
      'indexes': <Object?>[],
      'constraints': <Object?>[],
    },
    if (secondScope)
      {
        'schema': 'content',
        'name': 'posts',
        'columns': [
          {
            'name': 'id',
            'storage': {'kind': 'integer', 'nullable': false, 'codecVersion': 1},
            'primaryKey': true,
          },
        ],
        'indexes': <Object?>[],
        'constraints': <Object?>[],
      },
  ],
  'enums': <Object?>[],
  'requirements': <Object?>[],
};

({File migration, File sql, Map<String, Object?> entry}) _artifacts(Directory directory) {
  final journal =
      jsonDecode(File('${directory.path}/journal.json').readAsStringSync()) as Map<String, Object?>;
  final entry = (journal['entries']! as List<Object?>).last! as Map<String, Object?>;
  final path = '${directory.path}/${entry['directory']}';
  return (migration: File('$path/migration.json'), sql: File('$path/migration.sql'), entry: entry);
}

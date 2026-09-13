import 'dart:convert';
import 'dart:io';

import 'package:rivet_generator/rivet_generator.dart';
import 'package:rivet_generator/src/migration/sealer.dart';
import 'package:test/test.dart';

void main() {
  group('RivetArtifactSealer', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('rivet_sealer_test_');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    test('should reparse reviewed comments, quotes, dollar strings, and UTF-8', () async {
      final migrationId = await _generateInitial(directory);
      final artifacts = _artifacts(directory);
      final oldChecksum = artifacts.entry['checksum'];
      artifacts.sql.writeAsStringSync(
        '-- café; remains part of statement one\n'
        'CREATE SCHEMA IF NOT EXISTS "auth";\n'
        r'''CREATE TABLE "auth"."users" ("note" text DEFAULT E'λ\';value');'''
        '\n'
        r'''DO $$ BEGIN RAISE NOTICE 'inside;dollar'; END $$;'''
        '\n',
      );

      await RivetArtifactSealer().seal(directory: directory, migrationId: migrationId);

      final sealed = _artifacts(directory);
      final migration = jsonDecode(sealed.migration.readAsStringSync()) as Map<String, Object?>;
      final phases = (migration['phases']! as List<Object?>).cast<Map<String, Object?>>();
      final ranges = (phases.single['statements']! as List<Object?>).cast<Map<String, Object?>>();
      final bytes = sealed.sql.readAsBytesSync();
      expect(ranges, hasLength(3));
      expect(
        utf8.decode(bytes.sublist(ranges[1]['startByte']! as int, ranges[1]['endByte']! as int)),
        contains(r"E'λ\';value'"),
      );
      expect(sealed.entry['checksum'], isNot(oldChecksum));
      await const RivetMigrationChecker().check(directory: directory);
    });

    test('should reject ambiguous statement counts without changing metadata', () async {
      final migrationId = await _generateInitial(directory);
      final artifacts = _artifacts(directory);
      final oldMigration = artifacts.migration.readAsStringSync();
      final oldJournal = File('${directory.path}/journal.json').readAsStringSync();
      artifacts.sql.writeAsStringSync('${artifacts.sql.readAsStringSync()}SELECT 1;\n');

      await expectLater(
        RivetArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(isA<FormatException>()),
      );

      expect(artifacts.migration.readAsStringSync(), oldMigration);
      expect(File('${directory.path}/journal.json').readAsStringSync(), oldJournal);
    });

    test('should reject malformed SQL and writable recovery checks', () async {
      final migrationId = await _generateInitial(directory);
      var artifacts = _artifacts(directory);
      artifacts.sql.writeAsStringSync("SELECT 'unterminated;");
      await expectLater(
        RivetArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(isA<FormatException>()),
      );

      directory
        ..deleteSync(recursive: true)
        ..createSync();
      final nextMigrationId = await _generateInitial(directory);
      artifacts = _artifacts(directory);
      final migration = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      final phase = ((migration['phases']! as List<Object?>).single! as Map<String, Object?>)
        ..['mode'] = 'nontransactional'
        ..['recovery'] = {
          'kind': 'catalog',
          'operationId': '33333333333333333333333333333333',
          'before': {'description': 'before'},
          'after': {'description': 'after'},
          'checks': [
            {
              'sql': 'UPDATE auth.users SET name = name RETURNING true',
              'parameters': <Object?>[],
              'expected': true,
            },
          ],
        };
      artifacts.migration.writeAsStringSync(jsonEncode(migration));
      expect(phase['mode'], 'nontransactional');
      await expectLater(
        RivetArtifactSealer().seal(
          directory: directory,
          migrationId: nextMigrationId,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should seal a concurrent index only with structural recovery metadata', () async {
      final migrationId = await _generateConcurrentIndexMigration(directory);
      final artifacts = _artifacts(directory);
      artifacts.sql.writeAsStringSync(
        artifacts.sql.readAsStringSync().replaceFirst(
          'CREATE INDEX',
          '-- reviewed\nCREATE INDEX CONCURRENTLY',
        ),
      );
      final migration = jsonDecode(artifacts.migration.readAsStringSync()) as Map<String, Object?>;
      final phase = ((migration['phases']! as List<Object?>).single! as Map<String, Object?>)
        ..['mode'] = 'nontransactional'
        ..['recovery'] = {
          'kind': 'catalog',
          'operationId': '11111111111111111111111111111111',
          'before': {
            'schema': 'auth',
            'table': 'users',
            'index': 'users_name_idx',
            'exists': false,
          },
          'after': {
            'schema': 'auth',
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
        };
      artifacts.migration.writeAsStringSync(jsonEncode(migration));

      await RivetArtifactSealer().seal(directory: directory, migrationId: migrationId);
      expect(phase['mode'], 'nontransactional');
      await const RivetMigrationChecker().check(directory: directory);
    });

    test('should reject a comment-prefixed concurrent index in a transactional phase', () async {
      final migrationId = await _generateConcurrentIndexMigration(directory);
      final artifacts = _artifacts(directory);
      artifacts.sql.writeAsStringSync(
        artifacts.sql.readAsStringSync().replaceFirst(
          'CREATE INDEX',
          '/* reviewed */\nCREATE INDEX CONCURRENTLY',
        ),
      );

      await expectLater(
        RivetArtifactSealer().seal(directory: directory, migrationId: migrationId),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Future<String> _generateInitial(Directory directory) async {
  final id = await const RivetMigrationGenerator().generateDeclaration(
    declaration: _declaration(indexed: false),
    directory: directory,
    name: 'initial',
  );
  return id!;
}

Future<String> _generateConcurrentIndexMigration(Directory directory) async {
  await _generateInitial(directory);
  final id = await const RivetMigrationGenerator().generateDeclaration(
    declaration: _declaration(indexed: true),
    directory: directory,
    name: 'add index',
  );
  return id!;
}

Map<String, Object?> _declaration({required bool indexed}) => {
  'formatVersion': 1,
  'dialect': 'rivet',
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
        {
          'name': 'name',
          'storage': {'kind': 'text', 'nullable': false, 'codecVersion': 1},
          'primaryKey': false,
        },
      ],
      'indexes': [
        if (indexed)
          {
            'name': 'users_name_idx',
            'unique': false,
            'terms': [
              {'column': 'name', 'descending': false},
            ],
            'options': <String, Object?>{},
            'platforms': ['postgresql'],
          },
      ],
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

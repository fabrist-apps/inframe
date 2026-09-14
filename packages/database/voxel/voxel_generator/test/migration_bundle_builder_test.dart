import 'dart:convert';
import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:test/test.dart';
import 'package:voxel_generator/src/migration_bundle_builder.dart';
import 'package:voxel_generator/voxel_generator.dart';

void main() {
  test('should bundle checked artifacts in journal order with exact SQL', () async {
    final fixture = await _fixture();
    addTearDown(() => fixture.directory.deleteSync(recursive: true));
    final readerWriter = TestReaderWriter(rootPackage: 'voxel_generator');
    final builder = VoxelMigrationBundleBuilder(
      readDeclaration: (_, _, _) async => fixture.declaration,
      resolvePackageRoot: (_) async => Directory.current,
    );

    await testBuilder(
      builder,
      fixture.assets,
      readerWriter: readerWriter,
      outputs: {
        'voxel_generator|lib/accounts.voxel_migrations.dart': decodedMatches(
          allOf([
            contains('abstract final class AccountsDatabaseVoxelMigrations'),
            contains('VoxelMigrationBundle('),
            contains(r'''sql: 'CREATE TABLE "auth"."users" (\n'''),
            contains(fixture.migrationId),
          ]),
        ),
      },
    );
  });

  test('should fail before emitting a bundle for a model mismatch or missing artifact', () async {
    final fixture = await _fixture();
    addTearDown(() => fixture.directory.deleteSync(recursive: true));
    final mismatched = jsonDecode(jsonEncode(fixture.declaration)) as Map<String, Object?>;
    ((mismatched['tables']! as List<Object?>).single! as Map<String, Object?>)['name'] = 'members';
    final mismatchResult = await testBuilder(
      VoxelMigrationBundleBuilder(
        readDeclaration: (_, _, _) async => mismatched,
        resolvePackageRoot: (_) async => Directory.current,
      ),
      fixture.assets,
      readerWriter: TestReaderWriter(rootPackage: 'voxel_generator'),
    );
    expect(mismatchResult.succeeded, isFalse);
    expect(mismatchResult.errors.single, contains('current composed Voxel schema'));

    final incomplete = Map<String, Object>.from(fixture.assets)
      ..removeWhere((id, _) => id.endsWith('migration.sql'));
    final missingResult = await testBuilder(
      VoxelMigrationBundleBuilder(
        readDeclaration: (_, _, _) async => fixture.declaration,
        resolvePackageRoot: (_) async => Directory.current,
      ),
      incomplete,
      readerWriter: TestReaderWriter(rootPackage: 'voxel_generator'),
    );
    expect(missingResult.succeeded, isFalse);
    expect(missingResult.errors.single, contains('Missing journaled Voxel artifact'));

    final duplicateJournal = Map<String, Object>.from(fixture.assets);
    final journalKey = duplicateJournal.keys.singleWhere((id) => id.endsWith('journal.json'));
    duplicateJournal[journalKey] = (duplicateJournal[journalKey]! as String).replaceFirst(
      '"formatVersion": 1',
      '"formatVersion": 1, "formatVersion": 1',
    );
    final duplicateResult = await testBuilder(
      VoxelMigrationBundleBuilder(
        readDeclaration: (_, _, _) async => fixture.declaration,
        resolvePackageRoot: (_) async => Directory.current,
      ),
      duplicateJournal,
      readerWriter: TestReaderWriter(rootPackage: 'voxel_generator'),
    );
    expect(duplicateResult.succeeded, isFalse);
    expect(duplicateResult.errors.single, contains('Duplicate JSON key `formatVersion`'));
  });
}

Future<
  ({
    Directory directory,
    Map<String, Object?> declaration,
    Map<String, Object> assets,
    String migrationId,
  })
>
_fixture() async {
  final directory = Directory.systemTemp.createTempSync('voxel_bundle_builder_test_');
  final declaration = <String, Object?>{
    'formatVersion': 1,
    'dialect': 'voxel',
    'name': 'accounts',
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
    ],
    'enums': <Object?>[],
    'requirements': <Object?>[],
  };
  final migrationId = (await const VoxelMigrationGenerator().generateDeclaration(
    declaration: declaration,
    directory: directory,
    name: 'initial',
    source: const {
      'library': 'package:example/database.dart',
      'class': 'AccountsDatabase',
    },
  ))!;
  final journal = File('${directory.path}/journal.json').readAsStringSync();
  final entry =
      ((jsonDecode(journal) as Map<String, Object?>)['entries']! as List<Object?>).single!
          as Map<String, Object?>;
  final artifactDirectory = '${entry['directory']}';
  final assets = <String, Object>{
    'voxel_generator|migrations/accounts/journal.json': journal,
    for (final name in const ['migration.json', 'snapshot.json', 'migration.sql'])
      'voxel_generator|migrations/accounts/$artifactDirectory/$name': File(
        '${directory.path}/$artifactDirectory/$name',
      ).readAsBytesSync(),
  };
  return (
    directory: directory,
    declaration: declaration,
    assets: assets,
    migrationId: migrationId,
  );
}

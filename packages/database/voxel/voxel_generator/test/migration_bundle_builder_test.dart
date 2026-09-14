import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
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
            contains('extension AccountsDatabaseVoxelOpen on AccountsDatabase'),
            contains('Future<VoxelDb> open('),
            contains('Future<VoxelMigrationStatus> migrationStatus('),
            contains('}) => VoxelDatabaseRuntime.migrationStatus('),
            contains('Future<void> resolveMigration({'),
            contains('required String migrationId,'),
            contains('required String phaseId,'),
            contains('required String expectedChecksum,'),
            contains('required String attemptId,'),
            contains('required String reason,'),
            contains('required VoxelMigrationResolution resolution,'),
            contains('}) => VoxelDatabaseRuntime.resolveMigration('),
            contains('migrationId: migrationId,'),
            contains('phaseId: phaseId,'),
            contains('expectedChecksum: expectedChecksum,'),
            contains('attemptId: attemptId,'),
            contains('reason: reason,'),
            contains('resolution: resolution,'),
            predicate<String>(
              (source) => RegExp('storage: storage,').allMatches(source).length == 3,
              'forwards storage through open, status, and resolve',
            ),
            predicate<String>(
              (source) => RegExp('migrations: migrations,').allMatches(source).length == 3,
              'forwards migration options through open, status, and resolve',
            ),
            contains('bundle: AccountsDatabaseVoxelMigrations.bundle'),
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

  test('should reject unsafe journal paths before materializing artifacts', () async {
    final fixture = await _fixture();
    addTearDown(() => fixture.directory.deleteSync(recursive: true));
    final assets = Map<String, Object>.from(fixture.assets);
    final journalKey = assets.keys.singleWhere((id) => id.endsWith('journal.json'));
    final journal = jsonDecode(assets[journalKey]! as String) as Map<String, Object?>;
    final entry = (journal['entries']! as List<Object?>).single! as Map<String, Object?>;
    final escapedName = 'voxel_bundle_escape_$pid';
    entry['directory'] = '../$escapedName';
    assets[journalKey] = jsonEncode(journal);
    final escaped = Directory('${Directory.systemTemp.path}/$escapedName');
    if (escaped.existsSync()) escaped.deleteSync(recursive: true);
    addTearDown(() {
      if (escaped.existsSync()) escaped.deleteSync(recursive: true);
    });

    final result = await testBuilder(
      VoxelMigrationBundleBuilder(
        readDeclaration: (_, _, _) async => fixture.declaration,
        resolvePackageRoot: (_) async => Directory.current,
      ),
      assets,
      readerWriter: TestReaderWriter(rootPackage: 'voxel_generator'),
    );

    expect(result.succeeded, isFalse);
    expect(result.errors.single, contains('unsafe migration directory'));
    expect(escaped.existsSync(), isFalse);
  });

  test('should register imported Dart model files as bundle dependencies', () async {
    final fixture = await _fixture();
    addTearDown(() => fixture.directory.deleteSync(recursive: true));
    final assets = Map<String, Object>.from(fixture.assets)
      ..['voxel_generator|lib/database.dart'] =
          "import 'package:voxel/review_dependency.dart'; final modelVersion = dependencyVersion;"
      ..['voxel|lib/review_dependency.dart'] = 'const dependencyVersion = 1;';
    final readerWriter = TestReaderWriter(rootPackage: 'voxel_generator');

    await testBuilder(
      VoxelMigrationBundleBuilder(
        readDeclaration: (_, _, _) async => fixture.declaration,
        resolvePackageRoot: (_) async => Directory.current,
      ),
      assets,
      readerWriter: readerWriter,
    );

    expect(
      readerWriter.testing.assetsRead,
      contains(AssetId('voxel', 'lib/review_dependency.dart')),
    );
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
      'library': 'package:voxel_generator/database.dart',
      'class': 'AccountsDatabase',
    },
  ))!;
  final journal = File('${directory.path}/journal.json').readAsStringSync();
  final entry =
      ((jsonDecode(journal) as Map<String, Object?>)['entries']! as List<Object?>).single!
          as Map<String, Object?>;
  final artifactDirectory = '${entry['directory']}';
  final assets = <String, Object>{
    'voxel_generator|lib/database.dart': 'const modelVersion = 1;',
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

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:voxel_generator/src/generator_utils.dart';
import 'package:voxel_generator/src/migration/checker.dart';
import 'package:voxel_generator/src/schema_probe.dart';

// This builder is public only through the build_runner entry point.
// ignore_for_file: public_member_api_docs

final class VoxelMigrationBundleBuilder implements Builder {
  const VoxelMigrationBundleBuilder({
    this.readDeclaration,
    this.resolvePackageRoot,
  });

  final Future<Map<String, Object?>> Function(
    String library,
    String className,
    Directory workingDirectory,
  )?
  readDeclaration;

  final Future<Directory> Function(String package)? resolvePackageRoot;

  @override
  Map<String, List<String>> get buildExtensions => const {
    'migrations/{{}}/journal.json': ['lib/{{}}.voxel_migrations.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final journalBytes = await buildStep.readAsBytes(buildStep.inputId);
    final journal = jsonDecode(utf8.decode(journalBytes));
    if (journal is! Map<String, Object?>) {
      throw const FormatException('journal.json must contain one JSON object.');
    }
    final checker = VoxelArtifactChecker()..validateJournal(journal);
    final source = journal['source'];
    if (source is! Map<String, Object?> ||
        source['library'] is! String ||
        source['class'] is! String) {
      throw const FormatException(
        'A bundled Voxel journal must record its generated schema library and class.',
      );
    }
    final className = source['class']! as String;
    if (!RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$').hasMatch(className)) {
      throw FormatException('Invalid bundled database class `$className`.');
    }
    final packageRoot = await (resolvePackageRoot ?? _packageRoot)(buildStep.inputId.package);
    await _trackModelInputs(buildStep, source['library']! as String);
    final migrationDirectory = await _materializeArtifacts(
      buildStep,
      journal,
      journalBytes,
    );
    try {
      final declaration = readDeclaration == null
          ? await _readBuildDeclaration(
              buildStep,
              source['library']! as String,
              className,
            )
          : await readDeclaration!(
              source['library']! as String,
              className,
              packageRoot,
            );
      await checker.check(
        directory: migrationDirectory,
        declaration: declaration,
      );

      final migrations = <String>[];
      for (final rawEntry in journal['entries']! as List<Object?>) {
        final entry = rawEntry! as Map<String, Object?>;
        final path = '${migrationDirectory.path}/${entry['directory']}';
        final metadata = jsonDecode(File('$path/migration.json').readAsStringSync());
        final snapshot = jsonDecode(File('$path/snapshot.json').readAsStringSync());
        final sql = File('$path/migration.sql').readAsStringSync();
        migrations.add('''
VoxelBundledMigration(
  directory: ${literal(entry['directory']! as String)},
  sql: ${literal(sql)},
  metadata: ${_dartLiteral(metadata)},
  snapshot: ${_dartLiteral(snapshot)},
)''');
      }
      final output = StringBuffer()
        ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
        ..writeln()
        ..writeln("import 'package:voxel/voxel.dart';")
        ..writeln("import '${source['library']}';")
        ..writeln()
        ..writeln('/// Checked migration history for `$className`.')
        ..writeln('abstract final class ${className}VoxelMigrations {')
        ..writeln('  /// Exact artifacts validated against the current composed schema.')
        ..writeln('  static const bundle = VoxelMigrationBundle(')
        ..writeln('    databaseId: ${literal(journal['databaseId']! as String)},')
        ..writeln('    migrations: [${migrations.join(',')}],')
        ..writeln('  );')
        ..writeln('}')
        ..writeln()
        ..writeln('/// Opens [$className] through its checked migration bundle.')
        ..writeln('extension ${className}VoxelOpen on $className {')
        ..writeln('  /// Opens and owns a fully initialized Voxel database.')
        ..writeln('  Future<VoxelDb> open({')
        ..writeln('    VoxelStorage? storage,')
        ..writeln('    Map<String, VoxelStorage> schemaStorage = const {},')
        ..writeln('    VoxelEncryption? encryption,')
        ..writeln('    Map<String, VoxelEncryption?> schemaEncryption = const {},')
        ..writeln('    VoxelMigrationOptions migrations = const VoxelMigrationOptions(),')
        ..writeln('  }) => VoxelDatabaseRuntime.open(')
        ..writeln('    schema: schema,')
        ..writeln('    bundle: ${className}VoxelMigrations.bundle,')
        ..writeln('    storage: storage,')
        ..writeln('    schemaStorage: schemaStorage,')
        ..writeln('    encryption: encryption,')
        ..writeln('    schemaEncryption: schemaEncryption,')
        ..writeln('    migrations: migrations,')
        ..writeln('  );')
        ..writeln()
        ..writeln('  /// Reads checked migration and phase state without changing database files.')
        ..writeln('  Future<VoxelMigrationStatus> migrationStatus({')
        ..writeln('    VoxelStorage? storage,')
        ..writeln('    Map<String, VoxelStorage> schemaStorage = const {},')
        ..writeln('    VoxelEncryption? encryption,')
        ..writeln('    Map<String, VoxelEncryption?> schemaEncryption = const {},')
        ..writeln('    VoxelMigrationOptions migrations = const VoxelMigrationOptions(),')
        ..writeln('  }) => VoxelDatabaseRuntime.migrationStatus(')
        ..writeln('    schema: schema,')
        ..writeln('    bundle: ${className}VoxelMigrations.bundle,')
        ..writeln('    storage: storage,')
        ..writeln('    schemaStorage: schemaStorage,')
        ..writeln('    encryption: encryption,')
        ..writeln('    schemaEncryption: schemaEncryption,')
        ..writeln('    migrations: migrations,')
        ..writeln('  );')
        ..writeln()
        ..writeln('  /// Records an audited decision for one interrupted migration attempt.')
        ..writeln('  Future<void> resolveMigration({')
        ..writeln('    required String migrationId,')
        ..writeln('    required String phaseId,')
        ..writeln('    required String expectedChecksum,')
        ..writeln('    required String attemptId,')
        ..writeln('    required String reason,')
        ..writeln('    required VoxelMigrationResolution resolution,')
        ..writeln('    VoxelStorage? storage,')
        ..writeln('    Map<String, VoxelStorage> schemaStorage = const {},')
        ..writeln('    VoxelEncryption? encryption,')
        ..writeln('    Map<String, VoxelEncryption?> schemaEncryption = const {},')
        ..writeln('    VoxelMigrationOptions migrations = const VoxelMigrationOptions(),')
        ..writeln('  }) => VoxelDatabaseRuntime.resolveMigration(')
        ..writeln('    schema: schema,')
        ..writeln('    bundle: ${className}VoxelMigrations.bundle,')
        ..writeln('    migrationId: migrationId,')
        ..writeln('    phaseId: phaseId,')
        ..writeln('    expectedChecksum: expectedChecksum,')
        ..writeln('    attemptId: attemptId,')
        ..writeln('    reason: reason,')
        ..writeln('    resolution: resolution,')
        ..writeln('    storage: storage,')
        ..writeln('    schemaStorage: schemaStorage,')
        ..writeln('    encryption: encryption,')
        ..writeln('    schemaEncryption: schemaEncryption,')
        ..writeln('    migrations: migrations,')
        ..writeln('  );')
        ..writeln('}');
      await buildStep.writeAsString(buildStep.allowedOutputs.single, output.toString());
    } finally {
      migrationDirectory.deleteSync(recursive: true);
    }
  }

  Future<void> _trackModelInputs(BuildStep buildStep, String sourceLibrary) async {
    final sourceId = AssetId.resolve(Uri.parse(sourceLibrary), from: buildStep.inputId);
    await buildStep.resolver.libraryFor(sourceId);
    await for (final library in buildStep.resolver.libraries) {
      for (final fragment in library.fragments) {
        final uri = fragment.source.uri;
        if (uri.scheme != 'package') continue;
        final id = AssetId.resolve(uri);
        if (!buildStep.allowedOutputs.contains(id) && await buildStep.canRead(id)) {
          await buildStep.readAsBytes(id);
        }
      }
    }
  }

  // A subprocess cannot see build_runner's pending source outputs. Evaluate the
  // same assets the resolver sees in an isolated package tree, never the checkout.
  Future<Map<String, Object?>> _readBuildDeclaration(
    BuildStep buildStep,
    String sourceLibrary,
    String className,
  ) async {
    final directory = Directory.systemTemp.createTempSync('voxel_schema_');
    try {
      final packages = <String, Map<String, Object?>>{};
      final roots = <String, Directory>{};
      final buildRoot = await _packageRoot(buildStep.inputId.package);
      final copied = <AssetId>{};
      Future<void> copy(AssetId id) async {
        if (!copied.add(id) || buildStep.allowedOutputs.contains(id)) return;
        var input = id;
        // Nested workspace packages may be generated as assets of the enclosing
        // package. Their package: URI aliases do not expose those pending outputs.
        if (id.package != buildStep.inputId.package) {
          final packageUri = await Isolate.resolvePackageUri(Uri.parse('package:${id.package}/'));
          if (packageUri != null && packageUri.isScheme('file')) {
            final root = roots[id.package] ??= Directory.fromUri(packageUri).parent;
            final uri = root.uri.resolve(id.path);
            if (uri.path.startsWith(buildRoot.uri.path)) {
              final candidate = AssetId(
                buildStep.inputId.package,
                uri.path.substring(buildRoot.uri.path.length),
              );
              if (await buildStep.canRead(candidate)) input = candidate;
            }
          }
        }
        final content = await buildStep.readAsString(input);
        File('${directory.path}/${id.package}/${id.path}')
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
        // Missing generated parts are absent from analyzer library fragments.
        // Read their declared URIs explicitly through the build asset graph.
        final unit = parseString(content: content, throwIfDiagnostics: false).unit;
        for (final part in unit.directives.whereType<PartDirective>()) {
          final uri = part.uri.stringValue;
          if (uri != null) await copy(AssetId.resolve(Uri.parse(uri), from: id));
        }
      }

      await for (final library in buildStep.resolver.libraries) {
        for (final fragment in library.fragments) {
          final uri = fragment.source.uri;
          if (uri.scheme != 'package') continue;
          final id = AssetId.resolve(uri);
          await copy(id);
          packages.putIfAbsent(
            id.package,
            () => {
              'name': id.package,
              'rootUri': '../${id.package}/',
              'packageUri': 'lib/',
              'languageVersion':
                  '${library.languageVersion.package.major}.${library.languageVersion.package.minor}',
            },
          );
        }
      }
      File('${directory.path}/.dart_tool/package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'configVersion': 2,
            'packages': packages.values.toList(),
          }),
        );
      return await readVoxelSchemaDeclaration(
        sourceLibrary,
        className,
        workingDirectory: directory,
      );
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  Future<Directory> _packageRoot(String package) async {
    final resolved = await Isolate.resolvePackageUri(Uri.parse('package:$package/'));
    if (resolved == null || !resolved.isScheme('file')) {
      throw StateError('Could not resolve package root for `$package`.');
    }
    return Directory.fromUri(resolved).parent;
  }

  Future<Directory> _materializeArtifacts(
    BuildStep buildStep,
    Map<String, Object?> journal,
    List<int> journalBytes,
  ) async {
    final sourceDirectory = buildStep.inputId.pathSegments
        .take(buildStep.inputId.pathSegments.length - 1)
        .join('/');
    final directory = Directory.systemTemp.createTempSync('voxel_bundle_');
    try {
      File('${directory.path}/journal.json').writeAsBytesSync(journalBytes);
      for (final rawEntry in journal['entries']! as List<Object?>) {
        final entry = rawEntry! as Map<String, Object?>;
        for (final file in const ['migration.json', 'snapshot.json', 'migration.sql']) {
          final id = AssetId(
            buildStep.inputId.package,
            '$sourceDirectory/${entry['directory']}/$file',
          );
          if (!await buildStep.canRead(id)) {
            throw FormatException('Missing journaled Voxel artifact `${id.path}`.');
          }
          final bytes = await buildStep.readAsBytes(id);
          File('${directory.path}/${entry['directory']}/$file')
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes);
        }
      }
      return directory;
    } on Object {
      directory.deleteSync(recursive: true);
      rethrow;
    }
  }
}

String _dartLiteral(Object? value) => switch (value) {
  null => 'null',
  final bool value => '$value',
  final num value when value.isFinite => '$value',
  final String value => literal(value),
  final List<Object?> value => '<Object?>[${value.map(_dartLiteral).join(',')}]',
  final Map<String, Object?> value =>
    '<String, Object?>{${(value.entries.toList()..sort((left, right) => left.key.compareTo(right.key))).map((entry) => '${literal(entry.key)}:${_dartLiteral(entry.value)}').join(',')}}',
  _ => throw FormatException('Migration artifacts contain a non-JSON value `$value`.'),
};

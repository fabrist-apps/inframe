import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
          ? await readVoxelSchemaDeclaration(
              source['library']! as String,
              className,
              workingDirectory: packageRoot,
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
        ..writeln()
        ..writeln('/// Checked migration history for `$className`.')
        ..writeln('abstract final class ${className}VoxelMigrations {')
        ..writeln('  /// Exact artifacts validated against the current composed schema.')
        ..writeln('  static const bundle = VoxelMigrationBundle(')
        ..writeln('    databaseId: ${literal(journal['databaseId']! as String)},')
        ..writeln('    migrations: [${migrations.join(',')}],')
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

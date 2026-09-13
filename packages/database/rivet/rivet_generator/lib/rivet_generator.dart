import 'dart:io';

import 'package:rivet/rivet.dart';
import 'package:rivet_generator/src/migration/artifact_generator.dart';

export 'src/migration/canonical_json.dart' show canonicalJson;

/// Generates and validates Rivet migration artifacts without a database.
final class RivetMigrationGenerator {
  /// Creates an offline migration generator.
  const RivetMigrationGenerator({this.createId});

  /// Overrides secure random identity generation for deterministic tests.
  final String Function()? createId;

  /// Generates the next migration for [schema] in [directory].
  Future<String?> generate({
    required RivetDatabaseSchema schema,
    required Directory directory,
    required String name,
  }) => RivetArtifactGenerator(createId: createId).generate(
    schema: schema,
    directory: directory,
    name: name,
  );

  /// Generates artifacts from a descriptor emitted by generated application
  /// code. This is the JSON boundary used by the command-line probe.
  Future<String?> generateDeclaration({
    required Map<String, Object?> declaration,
    required Directory directory,
    required String name,
  }) => RivetArtifactGenerator(createId: createId).generateDeclaration(
    declaration: declaration,
    directory: directory,
    name: name,
  );
}

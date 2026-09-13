import 'dart:io';

import 'package:rivet/rivet.dart';
import 'package:rivet_generator/src/migration/artifact_generator.dart';
import 'package:rivet_generator/src/migration/checker.dart';

export 'src/migration/canonical_json.dart' show canonicalJson;

/// Validates Rivet migration artifacts and optional current schema agreement.
final class RivetMigrationChecker {
  /// Creates an offline artifact checker.
  const RivetMigrationChecker();

  /// Checks every journaled artifact in [directory].
  Future<void> check({
    required Directory directory,
    RivetDatabaseSchema? schema,
  }) => RivetArtifactChecker().check(
    directory: directory,
    declaration: schema?.toJson(),
  );
}

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
    Map<String, String>? source,
    Map<String, String> enumLabelTransforms = const {},
  }) => RivetArtifactGenerator(createId: createId).generateDeclaration(
    declaration: declaration,
    directory: directory,
    name: name,
    source: source,
    enumLabelTransforms: enumLabelTransforms,
  );
}

import 'dart:io';

import 'package:voxel/voxel.dart';
import 'package:voxel_generator/src/migration/artifact_generator.dart';
import 'package:voxel_generator/src/migration/checker.dart';

export 'src/migration/canonical_json.dart' show canonicalJson;

/// Validates Voxel migration artifacts and optional current schema agreement.
final class VoxelMigrationChecker {
  /// Creates an offline artifact checker.
  const VoxelMigrationChecker();

  /// Checks every journaled artifact in [directory].
  Future<void> check({
    required Directory directory,
    VoxelDatabaseSchema? schema,
  }) => VoxelArtifactChecker().check(
    directory: directory,
    declaration: schema == null ? null : voxelMigrationSchemaToJson(schema),
  );
}

/// Generates and validates Voxel migration artifacts without a database.
final class VoxelMigrationGenerator {
  /// Creates an offline migration generator.
  const VoxelMigrationGenerator({this.createId});

  /// Overrides secure random identity generation for deterministic tests.
  final String Function()? createId;

  /// Generates the next migration for [schema] in [directory].
  Future<String?> generate({
    required VoxelDatabaseSchema schema,
    required Directory directory,
    required String name,
    Map<String, String> storageTransforms = const {},
  }) => VoxelArtifactGenerator(createId: createId).generate(
    schema: schema,
    directory: directory,
    name: name,
    storageTransforms: storageTransforms,
  );

  /// Generates artifacts from a descriptor emitted by generated application
  /// code. This is the JSON boundary used by the command-line probe.
  Future<String?> generateDeclaration({
    required Map<String, Object?> declaration,
    required Directory directory,
    required String name,
    Map<String, String>? source,
    Map<String, String> storageTransforms = const {},
  }) => VoxelArtifactGenerator(createId: createId).generateDeclaration(
    declaration: declaration,
    directory: directory,
    name: name,
    source: source,
    storageTransforms: storageTransforms,
  );
}

/// Checked migration history embedded in generated application code.
final class VoxelMigrationBundle {
  /// Creates a bundle in journal order.
  const VoxelMigrationBundle({
    required this.databaseId,
    required this.migrations,
  });

  /// Stable identity shared by every migration artifact in this history.
  final String databaseId;

  /// Checked artifacts in their explicit journal order.
  final List<VoxelBundledMigration> migrations;
}

/// One checked migration and its exact source artifacts.
final class VoxelBundledMigration {
  /// Creates an immutable generated migration record.
  const VoxelBundledMigration({
    required this.directory,
    required this.sql,
    required this.metadata,
    required this.snapshot,
  });

  /// Source directory recorded by the journal.
  final String directory;

  /// Exact UTF-8 migration SQL after review and sealing.
  final String sql;

  /// Complete `migration.json`, including phases and integrity metadata.
  final Map<String, Object?> metadata;

  /// Complete resulting `snapshot.json`.
  final Map<String, Object?> snapshot;

  /// Stable migration identity.
  String get id => metadata['id']! as String;

  /// Stable parent identity, or null for the first migration.
  String? get parentId => metadata['parentId'] as String?;

  /// Integrity checksum covering this record's source artifacts.
  String get checksum => metadata['checksum']! as String;
}

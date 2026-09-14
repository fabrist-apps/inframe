/// A read-only view of checked migration artifacts and their durable state.
final class VoxelMigrationStatus {
  /// Creates a status snapshot in journal order.
  VoxelMigrationStatus({
    required this.databaseId,
    required List<VoxelMigrationStatusEntry> migrations,
  }) : migrations = List.unmodifiable(migrations);

  /// Stable identity shared by the artifacts and durable history.
  final String databaseId;

  /// Journal-ordered migration states.
  final List<VoxelMigrationStatusEntry> migrations;
}

/// Status for one journaled migration.
final class VoxelMigrationStatusEntry {
  /// Creates one immutable migration status entry.
  VoxelMigrationStatusEntry({
    required this.id,
    required this.checksum,
    required this.ordinal,
    required List<VoxelMigrationPhaseStatus> phases,
  }) : phases = List.unmodifiable(phases);

  /// Stable migration identity.
  final String id;

  /// Checked artifact checksum.
  final String checksum;

  /// Zero-based journal position.
  final int ordinal;

  /// Ordered states for every phase, including platform-skipped phases.
  final List<VoxelMigrationPhaseStatus> phases;
}

/// Status for one migration phase and its durable attempt evidence.
final class VoxelMigrationPhaseStatus {
  /// Creates one immutable phase status.
  VoxelMigrationPhaseStatus({
    required this.id,
    required this.scopeId,
    required this.state,
    required this.attemptId,
    required this.completionRecorded,
    required Map<String, Object?>? evidence,
  }) : evidence = evidence == null ? null : _freezeMap(evidence);

  /// Migration-local phase identity.
  final String id;

  /// Stable identity of the physical database scope containing the receipt.
  final String scopeId;

  /// Current receipt-derived state.
  final VoxelMigrationPhaseState state;

  /// Nontransactional attempt identity, when the phase has started.
  final String? attemptId;

  /// Whether durable phase history, rather than inspection alone, records completion.
  final bool completionRecorded;

  /// Immutable recovery evidence currently stored for the attempt.
  final Map<String, Object?>? evidence;
}

/// Receipt-derived lifecycle of a migration phase.
enum VoxelMigrationPhaseState {
  /// No durable receipt exists.
  pending,

  /// A nontransactional attempt may have been interrupted.
  started,

  /// Available checks or manual metadata cannot establish either safe state.
  uncertain,

  /// The phase does not apply to the current runtime platform.
  skipped,

  /// A receipt or exact postcondition establishes completion.
  completed,
}

/// Operator decision for an interrupted migration attempt.
enum VoxelMigrationResolution {
  /// Certifies that the intended effect is complete.
  completed,

  /// Certifies that the prior effect is safe to attempt again.
  retry,
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) => Map.unmodifiable({
  for (final entry in source.entries) entry.key: _freezeValue(entry.value),
});

Object? _freezeValue(Object? value) => switch (value) {
  Map<String, Object?>() => _freezeMap(value),
  List<Object?>() => List<Object?>.unmodifiable(value.map(_freezeValue)),
  _ => value,
};

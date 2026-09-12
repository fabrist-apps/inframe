/// Resource limits applied to each Runnel physical connection.
final class RunnelLimits {
  /// Creates connection resource limits.
  const RunnelLimits({
    this.maxPendingCommands = 1024,
    this.maxPendingBytes = 16 * 1024 * 1024,
    this.maxFrameBytes = 16 * 1024 * 1024,
    this.maxNestingDepth = 64,
  });

  /// Accepted but unsettled commands, including locally buffered commands.
  final int maxPendingCommands;

  /// Encoded bytes reserved until a command settles.
  final int maxPendingBytes;

  /// Maximum complete incoming top-level frame size.
  final int maxFrameBytes;

  /// Maximum aggregate nesting, with a top-level aggregate at depth one.
  final int maxNestingDepth;

  /// Rejects non-positive resource limits.
  void validate() {
    if (maxPendingCommands <= 0 ||
        maxPendingBytes <= 0 ||
        maxFrameBytes <= 0 ||
        maxNestingDepth <= 0) {
      throw ArgumentError('Runnel limits must be positive.');
    }
  }
}

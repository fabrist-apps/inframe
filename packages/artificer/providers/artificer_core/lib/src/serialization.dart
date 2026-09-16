/// Domain persistence format shared by messages and results.
abstract final class DomainSchema {
  /// Rejects incompatible persisted versions instead of silently misreading them.
  static void check(int version) {
    if (version != 1) throw const FormatException('Unsupported domain schema version.');
  }
}

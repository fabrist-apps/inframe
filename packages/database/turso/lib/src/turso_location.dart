/// Identifies where an embedded Turso database stores its data.
sealed class TursoLocation {
  const TursoLocation();

  /// Stores a database at a native filesystem [path].
  factory TursoLocation.file(String path) = TursoFileLocation;

  /// Stores a database in browser origin-private file storage under [name].
  factory TursoLocation.browser(String name) = TursoBrowserLocation;

  /// Creates a database that is discarded when it closes.
  factory TursoLocation.memory() = TursoMemoryLocation;
}

/// A native filesystem database location.
final class TursoFileLocation extends TursoLocation {
  /// Creates a validated native filesystem location.
  TursoFileLocation(this.path) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Must not be empty.');
    }
    final uri = Uri.tryParse(path);
    if (uri != null && _networkSchemes.contains(uri.scheme)) {
      throw ArgumentError.value(path, 'path', 'Network database URLs are not supported.');
    }
  }

  /// The caller-owned native filesystem path.
  final String path;
}

const _networkSchemes = {'http', 'https', 'libsql', 'ws', 'wss'};

/// A browser origin-private filesystem database location.
final class TursoBrowserLocation extends TursoLocation {
  /// Creates a validated browser storage location.
  TursoBrowserLocation(this.name) {
    if (name.trim().isEmpty || name.contains('/') || name.contains(r'\')) {
      throw ArgumentError.value(
        name,
        'name',
        'Must be nonempty and contain no path separators.',
      );
    }
  }

  /// The browser storage name.
  final String name;
}

/// An in-memory database location.
final class TursoMemoryLocation extends TursoLocation {
  /// Creates an in-memory location.
  const TursoMemoryLocation();
}

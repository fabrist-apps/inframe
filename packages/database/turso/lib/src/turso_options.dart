import 'dart:typed_data';

/// Version-matched browser bridge configuration.
final class TursoWebOptions {
  /// Creates browser options using the hosted bridge [moduleUri].
  const TursoWebOptions({required this.moduleUri});

  /// URI of the package's browser bridge module.
  final Uri moduleUri;
}

/// Encryption algorithms exposed by the v1 API.
enum TursoCipher {
  /// AEGIS-256 with a 32-byte key.
  aegis256,

  /// AES-256-GCM with a 32-byte key.
  aes256gcm,
}

/// Application-supplied encryption configuration.
final class TursoEncryption {
  /// Creates encryption configuration with a raw [key].
  TursoEncryption({required this.cipher, required Uint8List key}) : _key = Uint8List.fromList(key) {
    if (key.length != 32) {
      throw ArgumentError('Must contain exactly 32 bytes.', 'key');
    }
  }

  /// The requested upstream cipher.
  final TursoCipher cipher;

  final Uint8List _key;

  /// A defensive copy of the raw key bytes.
  Uint8List get key => Uint8List.fromList(_key);
}

/// Features available in the opened backend.
final class TursoCapabilities {
  /// Creates a capability report for the actual backend build.
  const TursoCapabilities({
    required this.fts,
    required this.vectorFunctions,
    required this.vectorIndexes,
  });

  /// Whether native full-text search is available.
  final bool fts;

  /// Whether verified vector SQL functions are available.
  final bool vectorFunctions;

  /// Whether verified vector indexing is available.
  final bool vectorIndexes;
}

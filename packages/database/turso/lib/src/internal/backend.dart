import 'package:turso/src/internal/parameters.dart';
import 'package:turso/src/turso_options.dart';

/// One platform-owned database execution context.
abstract interface class TursoBackend {
  /// Features verified for this backend instance.
  TursoCapabilities get capabilities;

  /// Runs a query and returns its transport-safe result.
  Future<List<Object?>> query(String sql, SqlParameterSnapshot parameters);

  /// Runs a command and returns its affected row count.
  Future<BigInt> execute(String sql, SqlParameterSnapshot parameters);

  /// Releases all resources owned by this backend.
  Future<void> close();

  /// Stops the backend after an unrecoverable connection failure.
  Future<void> retire();
}

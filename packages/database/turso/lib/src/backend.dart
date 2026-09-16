import 'package:turso/src/parameters.dart';
import 'package:turso/src/turso_options.dart';
import 'package:turso/src/turso_result.dart';

/// One platform-owned database execution context.
abstract interface class TursoBackend {
  /// Features verified for this backend instance.
  TursoCapabilities get capabilities;

  /// Runs a query and returns its buffered result.
  Future<TursoQueryResult> query(String sql, SqlParameters parameters);

  /// Runs a command and returns its affected row count.
  Future<BigInt> execute(String sql, SqlParameters parameters);

  /// Releases all resources owned by this backend.
  Future<void> close();

  /// Stops the backend after an unrecoverable connection failure.
  Future<void> retire();
}

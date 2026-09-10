/// Base class for failures produced by the Turso driver or engine.
sealed class TursoException implements Exception {
  /// Creates an exception with a safe diagnostic [message].
  const TursoException(this.message);

  /// A diagnostic that never includes application encryption keys.
  final String message;

  @override
  String toString() => message;
}

/// A SQL or storage failure reported by upstream Turso.
final class TursoDatabaseException extends TursoException {
  /// Creates an upstream database failure.
  const TursoDatabaseException(super.message, {this.code});

  /// The upstream status code when available.
  final int? code;
}

/// A native worker, FFI, or browser integration failure.
final class TursoPlatformException extends TursoException {
  /// Creates a platform integration failure.
  const TursoPlatformException(super.message);
}

/// An unsupported platform or feature request.
final class TursoUnsupportedException extends TursoException {
  /// Creates an unsupported-operation failure.
  const TursoUnsupportedException(super.message);
}

/// A transaction failure accompanied by a rollback failure.
final class TursoTransactionException extends TursoException {
  /// Creates a combined transaction failure.
  const TursoTransactionException({
    required this.primaryError,
    required this.primaryStackTrace,
    required this.rollbackError,
    required this.rollbackStackTrace,
  }) : super('The transaction and its rollback both failed.');

  /// The failure that caused the rollback.
  final Object primaryError;

  /// Stack trace for [primaryError].
  final StackTrace primaryStackTrace;

  /// The rollback failure.
  final Object rollbackError;

  /// Stack trace for [rollbackError].
  final StackTrace rollbackStackTrace;
}

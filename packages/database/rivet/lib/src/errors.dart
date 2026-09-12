/// Base class for failures reported by Rivet.
sealed class RivetException implements Exception {
  const RivetException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// A PostgreSQL operation failed.
final class RivetDatabaseException extends RivetException {
  const RivetDatabaseException(super.message, [super.cause]);
}

/// A value could not be encoded or decoded by its column codec.
final class RivetConversionException extends RivetException {
  const RivetConversionException({
    required this.table,
    required this.column,
    required String message,
    Object? cause,
  }) : super('$table.$column: $message', cause);

  final String table;
  final String column;
}

/// A single-row terminal observed the wrong number of rows.
final class RivetCardinalityException extends RivetException {
  const RivetCardinalityException({required this.expected, required this.actual})
    : super('Expected $expected row, but received $actual.');

  final String expected;
  final int actual;
}

/// A query cannot be represented by the supported root-read grammar.
final class RivetUnsupportedQueryException extends RivetException {
  const RivetUnsupportedQueryException(super.message);
}

/// An executor was used outside its valid lifetime.
final class RivetExecutorClosedException extends RivetException {
  const RivetExecutorClosedException(super.message);
}

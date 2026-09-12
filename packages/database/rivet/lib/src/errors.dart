// Error boundaries are documented on each exception type; their data fields retain direct names.
// ignore_for_file: public_member_api_docs

/// Base class for failures reported by Rivet.
sealed class RivetException implements Exception {
  const RivetException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      '${switch (this) {
        RivetDatabaseException() => 'RivetDatabaseException',
        RivetConversionException() => 'RivetConversionException',
        RivetCardinalityException() => 'RivetCardinalityException',
        RivetUnsupportedQueryException() => 'RivetUnsupportedQueryException',
        RivetExecutorClosedException() => 'RivetExecutorClosedException',
        AfterCommitException() => 'AfterCommitException',
      }}: $message';
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

final class AfterCommitFailure {
  const AfterCommitFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class AfterCommitException extends RivetException {
  AfterCommitException(this.failures, {required this.alreadyCommitted})
    : super(
        '${failures.length} after-commit callback${failures.length == 1 ? '' : 's'} failed; '
        'alreadyCommitted=$alreadyCommitted.',
      );

  final List<AfterCommitFailure> failures;
  final bool alreadyCommitted;
}

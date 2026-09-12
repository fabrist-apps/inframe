// Error boundaries are documented on each exception type; their data fields retain direct names.
// ignore_for_file: public_member_api_docs

/// Base class for failures reported by Voxel.
sealed class VoxelException implements Exception {
  const VoxelException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      '${switch (this) {
        VoxelDatabaseException() => 'VoxelDatabaseException',
        VoxelConversionException() => 'VoxelConversionException',
        VoxelCardinalityException() => 'VoxelCardinalityException',
        VoxelUnsupportedQueryException() => 'VoxelUnsupportedQueryException',
        VoxelMissingValueException() => 'VoxelMissingValueException',
        VoxelEmptyUpdateException() => 'VoxelEmptyUpdateException',
        VoxelExecutorClosedException() => 'VoxelExecutorClosedException',
        AfterCommitException() => 'AfterCommitException',
      }}: $message';
}

/// A Turso operation failed.
final class VoxelDatabaseException extends VoxelException {
  const VoxelDatabaseException(super.message, [super.cause]);
}

/// A value could not be encoded or decoded by its column codec.
final class VoxelConversionException extends VoxelException {
  const VoxelConversionException({
    required this.table,
    required this.column,
    required String message,
    Object? cause,
  }) : super('$table.$column: $message', cause);

  final String table;
  final String column;
}

/// A single-row terminal observed the wrong number of rows.
final class VoxelCardinalityException extends VoxelException {
  const VoxelCardinalityException({required this.expected, required this.actual})
    : super('Expected $expected row, but received $actual.');

  final String expected;
  final int actual;
}

/// A query cannot be represented by the supported root-read grammar.
final class VoxelUnsupportedQueryException extends VoxelException {
  const VoxelUnsupportedQueryException(super.message);
}

/// A required mutation field was absent when execution began.
final class VoxelMissingValueException extends VoxelException {
  const VoxelMissingValueException({required this.table, required this.column})
    : super('Required mutation value $table.$column is absent.');

  final String table;
  final String column;
}

/// An update had no explicit or runtime-hook assignments.
final class VoxelEmptyUpdateException extends VoxelException {
  const VoxelEmptyUpdateException(super.message);
}

/// An executor was used outside its valid lifetime.
final class VoxelExecutorClosedException extends VoxelException {
  const VoxelExecutorClosedException(super.message);
}

final class AfterCommitFailure {
  const AfterCommitFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class AfterCommitException extends VoxelException {
  AfterCommitException(this.failures, {required this.alreadyCommitted})
    : super(
        '${failures.length} after-commit callback${failures.length == 1 ? '' : 's'} failed; '
        'alreadyCommitted=$alreadyCommitted.',
      );

  final List<AfterCommitFailure> failures;
  final bool alreadyCommitted;
}

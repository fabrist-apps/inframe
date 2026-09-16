import 'dart:async';

import 'package:turso/src/backend.dart';
import 'package:turso/src/parameters.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_result.dart';

/// Owns callback-scoped scheduling, failure tracking, and transaction completion.
///
/// The database reserves its root queue while [run] executes. Accepted operations
/// run in order; ending the callback expires the handle before draining the queue.
/// A callback failure skips queued work. Any accepted operation failure prevents
/// commit, even when the callback catches or ignores its returned future.
final class ManagedTransaction implements TursoTransaction {
  /// Reserves backend execution and reports unusable connections to their owner.
  ManagedTransaction(this._backend, this._runBackendOperation, this._retire);

  final Future<void> Function(TursoPlatformException failure) _retire;

  final TursoBackend _backend;
  final Future<T> Function<T>(Future<T> Function() operation) _runBackendOperation;
  Future<void> _tail = Future<void>.value();
  _OperationFailure? _firstFailure;
  var _accepting = true;
  var _abortQueued = false;

  /// Begins, drains the callback's work, then commits or rolls back.
  Future<T> run<T>(Future<T> Function(TursoTransaction tx) action) async {
    await _runBackendOperation(() => _backend.execute('BEGIN DEFERRED', emptySqlParameters));
    late T result;
    _OperationFailure? failure;

    try {
      result = await action(this);
    } on Object catch (error, stackTrace) {
      failure = _OperationFailure(error, stackTrace);
    }

    _finishCallback(abortQueued: failure != null);
    await _tail;
    failure ??= _firstFailure;
    if (failure != null) {
      await _rollbackAndThrow(failure.error, failure.stackTrace);
    }

    try {
      await _runBackendOperation(() => _backend.execute('COMMIT', emptySqlParameters));
    } on Object catch (error, stackTrace) {
      await _rollbackAndThrow(error, stackTrace);
    }
    return result;
  }

  Future<Never> _rollbackAndThrow(Object primaryError, StackTrace primaryStackTrace) async {
    try {
      await _runBackendOperation(() => _backend.execute('ROLLBACK', emptySqlParameters));
    } on Object catch (rollbackError, rollbackStackTrace) {
      await _retire(
        const TursoPlatformException(
          'The Turso connection was retired after a failed rollback; an interrupted write may have committed.',
        ),
      );
      Error.throwWithStackTrace(
        TursoTransactionException(
          primaryError: primaryError,
          primaryStackTrace: primaryStackTrace,
          rollbackError: rollbackError,
          rollbackStackTrace: rollbackStackTrace,
        ),
        primaryStackTrace,
      );
    }
    Error.throwWithStackTrace(primaryError, primaryStackTrace);
  }

  @override
  Future<TursoQueryResult> query(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => _submit(() {
    validateSql(sql);
    final snapshot = SqlParameters.snapshot(parameters, namedParameters);
    return _enqueue(() => _runBackendOperation(() => _backend.query(sql, snapshot)));
  });

  @override
  Future<TursoExecuteResult> execute(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => _submit(() {
    validateSql(sql);
    final snapshot = SqlParameters.snapshot(parameters, namedParameters);
    return _enqueue(() async {
      final rowsAffected = await _runBackendOperation(() => _backend.execute(sql, snapshot));
      return TursoExecuteResult(rowsAffected: rowsAffected);
    });
  });

  Future<T> _submit<T>(Future<T> Function() prepare) {
    final submitted = Future<T>.sync(() {
      _ensureAccepting();
      try {
        return prepare();
      } on Object catch (error, stackTrace) {
        // Validation is part of an accepted operation, even before it is queued.
        _firstFailure ??= _OperationFailure(error, stackTrace);
        rethrow;
      }
    });
    // The transaction reports accepted failures even when the caller ignores them.
    unawaited(submitted.then<void>((_) {}, onError: (_, _) {}));
    return submitted;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      if (_abortQueued) {
        completer.completeError(
          StateError('The transaction callback failed before this operation started.'),
        );
        return;
      }
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        _firstFailure ??= _OperationFailure(error, stackTrace);
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _ensureAccepting() {
    if (!_accepting) throw StateError('The transaction handle has expired.');
  }

  void _finishCallback({required bool abortQueued}) {
    _accepting = false;
    _abortQueued = abortQueued;
  }
}

final class _OperationFailure {
  const _OperationFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

/// Operations reserved by an active transaction.
abstract interface class TursoTransaction {
  /// Runs one SQL statement and buffers its complete result.
  Future<TursoQueryResult> query(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  });

  /// Runs one SQL statement and discards rows it returns.
  Future<TursoExecuteResult> execute(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  });
}

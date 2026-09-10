import 'dart:async';
import 'dart:typed_data';

import 'package:turso/src/internal/backend.dart';
import 'package:turso/src/internal/backend_native.dart'
    if (dart.library.js_interop) 'package:turso/src/internal/backend_web.dart'
    as platform;
import 'package:turso/src/internal/parameters.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';
import 'package:turso/src/turso_result.dart';

/// One serialized embedded Turso connection.
final class TursoDatabase {
  TursoDatabase._(this._backend);

  final TursoBackend _backend;
  final Object _transactionZoneKey = Object();
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;
  TursoPlatformException? _retirementFailure;

  /// Opens a database at [location].
  ///
  /// The caller owns native paths, their parent directories, browser asset
  /// hosting, schema creation, and encryption-key storage. A requested
  /// [encryption] configuration fails explicitly when the backend rejects it;
  /// opening never retries as plaintext. Browser and memory locations on web
  /// require version-matched [web] options.
  static Future<TursoDatabase> open(
    TursoLocation location, {
    TursoEncryption? encryption,
    TursoWebOptions? web,
  }) async {
    final backend = await platform.openBackend(location, encryption: encryption, web: web);
    return TursoDatabase._(backend);
  }

  /// Features verified for this opened backend.
  TursoCapabilities get capabilities => _backend.capabilities;

  /// Runs one SQL statement and buffers its complete result.
  ///
  /// Supply either positional [parameters] or [namedParameters] with full
  /// placeholder spelling, such as `{':id': 42}`. Supported values are NULL,
  /// text, finite numbers, signed 64-bit [BigInt] values, and [Uint8List].
  Future<TursoQueryResult> query(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => Future<TursoQueryResult>.sync(() {
    _ensureOutsideTransactionCallback();
    validateSql(sql);
    final snapshot = snapshotParameters(parameters, namedParameters);
    return _enqueue(() async {
      final wireResult = await _runBackendOperation(() => _backend.query(sql, snapshot));
      return _decodeQueryResult(wireResult);
    });
  });

  /// Runs one SQL statement and discards rows it returns.
  ///
  /// Use [query] when the statement has a `RETURNING` clause whose rows the
  /// caller needs.
  Future<TursoExecuteResult> execute(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => Future<TursoExecuteResult>.sync(() {
    _ensureOutsideTransactionCallback();
    validateSql(sql);
    final snapshot = snapshotParameters(parameters, namedParameters);
    return _enqueue(() async {
      final rowsAffected = await _runBackendOperation(() => _backend.execute(sql, snapshot));
      return TursoExecuteResult(rowsAffected: rowsAffected);
    });
  });

  /// Runs [action] inside one deferred transaction.
  ///
  /// The returned future completes with the callback result after commit.
  /// Callback failures roll back when the connection remains usable. Use only
  /// the supplied transaction handle inside [action].
  Future<T> transaction<T>(Future<T> Function(TursoTransaction tx) action) => Future<T>.sync(() {
    _ensureOutsideTransactionCallback();
    return _enqueue(() => _runTransaction(action));
  });

  /// Drains accepted work and releases the database.
  ///
  /// New root operations fail once shutdown starts. Repeated calls return the
  /// same shutdown future.
  Future<void> close() {
    if (_insideTransactionCallback) {
      return Future<void>.error(
        StateError('The parent database cannot close inside its transaction callback.'),
      );
    }
    final existing = _closeFuture;
    if (existing != null) return existing;

    final completer = Completer<void>();
    _closeFuture = completer.future;
    unawaited(
      _tail
          .then((_) => _backend.close())
          .then(
            completer.complete,
            onError: completer.completeError,
          ),
    );
    return completer.future;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_closeFuture != null) {
      return Future<T>.error(StateError('The database is closing or closed.'));
    }
    final retirementFailure = _retirementFailure;
    if (retirementFailure != null) return Future<T>.error(retirementFailure);
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        final retirementFailure = _retirementFailure;
        if (retirementFailure != null) throw retirementFailure;
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  bool get _insideTransactionCallback => Zone.current[_transactionZoneKey] == true;

  void _ensureOutsideTransactionCallback() {
    if (_insideTransactionCallback) {
      throw StateError(
        'Use the transaction handle inside its callback instead of the parent database.',
      );
    }
  }

  Future<T> _runTransaction<T>(Future<T> Function(TursoTransaction tx) action) async {
    await _runBackendOperation(() => _backend.execute('BEGIN DEFERRED', const []));
    final transaction = _ManagedTransaction(_backend, _runBackendOperation);
    late T result;
    Object? primaryError;
    StackTrace? primaryStackTrace;

    try {
      result = await runZoned(
        () => action(transaction),
        zoneValues: {_transactionZoneKey: true},
      );
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }

    transaction.finishCallback(abortQueued: primaryError != null);
    await transaction.drain();
    final operationFailure = transaction.firstFailure;
    if (primaryError == null && operationFailure != null) {
      primaryError = operationFailure.error;
      primaryStackTrace = operationFailure.stackTrace;
    }

    if (primaryError != null) {
      await _rollbackAndThrow(primaryError, primaryStackTrace!);
    }

    try {
      await _runBackendOperation(() => _backend.execute('COMMIT', const []));
    } on Object catch (error, stackTrace) {
      await _rollbackAndThrow(error, stackTrace);
    }
    return result;
  }

  Future<Never> _rollbackAndThrow(Object primaryError, StackTrace primaryStackTrace) async {
    try {
      await _runBackendOperation(() => _backend.execute('ROLLBACK', const []));
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

  Future<T> _runBackendOperation<T>(Future<T> Function() operation) async {
    final retirementFailure = _retirementFailure;
    if (retirementFailure != null) throw retirementFailure;
    try {
      return await operation();
    } on TursoPlatformException catch (error, stackTrace) {
      await _retire(error);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _retire(TursoPlatformException failure) async {
    _retirementFailure ??= failure;
    try {
      await _backend.retire();
    } on Object {
      // Preserve the failure that made the connection unusable.
    }
  }
}

TursoQueryResult _decodeQueryResult(List<Object?> wireResult) {
  final wireColumns = wireResult[0]! as List<Object?>;
  final columns = [for (final wireColumn in wireColumns) _decodeColumn(wireColumn)];
  final wireRows = wireResult[1]! as List<Object?>;
  final rows = [
    for (final wireRow in wireRows)
      TursoRow(columns, (wireRow! as List<Object?>).map(_decodeValue).toList()),
  ];
  return TursoQueryResult(columns: columns, rows: rows);
}

TursoColumn _decodeColumn(Object? wireColumn) {
  final fields = wireColumn! as List<Object?>;
  return TursoColumn(name: fields[0]! as String, declaredType: fields[1] as String?);
}

Object? _decodeValue(Object? wireValue) {
  if (wireValue is! List<Object?>) return wireValue;
  return switch (wireValue[0]) {
    'integer' => BigInt.parse(wireValue[1]! as String),
    'blob' => Uint8List.fromList((wireValue[1]! as List<Object?>).cast<int>()),
    _ => throw StateError('Unknown native value encoding: ${wireValue[0]}.'),
  };
}

final class _ManagedTransaction implements TursoTransaction {
  _ManagedTransaction(this._backend, this._runBackendOperation);

  final TursoBackend _backend;
  final Future<T> Function<T>(Future<T> Function() operation) _runBackendOperation;
  Future<void> _tail = Future<void>.value();
  _OperationFailure? _firstFailure;
  var _accepting = true;
  var _abortQueued = false;

  _OperationFailure? get firstFailure => _firstFailure;

  @override
  Future<TursoQueryResult> query(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => Future<TursoQueryResult>.sync(() {
    _ensureAccepting();
    validateSql(sql);
    final snapshot = snapshotParameters(parameters, namedParameters);
    return _enqueue(() async {
      final wireResult = await _runBackendOperation(() => _backend.query(sql, snapshot));
      return _decodeQueryResult(wireResult);
    });
  });

  @override
  Future<TursoExecuteResult> execute(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => Future<TursoExecuteResult>.sync(() {
    _ensureAccepting();
    validateSql(sql);
    final snapshot = snapshotParameters(parameters, namedParameters);
    return _enqueue(() async {
      final rowsAffected = await _runBackendOperation(() => _backend.execute(sql, snapshot));
      return TursoExecuteResult(rowsAffected: rowsAffected);
    });
  });

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
    unawaited(completer.future.then<void>((_) {}, onError: (_, _) {}));
    return completer.future;
  }

  void _ensureAccepting() {
    if (!_accepting) throw StateError('The transaction handle has expired.');
  }

  void finishCallback({required bool abortQueued}) {
    _accepting = false;
    _abortQueued = abortQueued;
  }

  Future<void> drain() => _tail;
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

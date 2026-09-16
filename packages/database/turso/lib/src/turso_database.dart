import 'dart:async';
import 'dart:typed_data';

import 'package:turso/src/backend.dart';
import 'package:turso/src/native/backend.dart'
    if (dart.library.js_interop) 'package:turso/src/web/backend.dart'
    as platform;
import 'package:turso/src/parameters.dart';
import 'package:turso/src/transaction.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';
import 'package:turso/src/turso_result.dart';

export 'package:turso/src/transaction.dart' show TursoTransaction;

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
  /// require version-matched [web] options. ATTACH and DETACH are available
  /// through [query] and [execute]. The caller enables foreign-key enforcement
  /// with `PRAGMA foreign_keys=ON` on each connection when needed.
  static Future<TursoDatabase> open(
    TursoLocation location, {
    TursoEncryption? encryption,
    TursoWebOptions? web,
  }) async {
    final backend = await platform.openBackend(location, encryption: encryption, web: web);
    return TursoDatabase._(backend);
  }

  /// Reports whether [location] identifies an existing browser OPFS file.
  ///
  /// This read-only check does not create a file, open a database connection,
  /// or acquire the driver's exclusive file ownership. Callers must coordinate
  /// it with any migration or recovery work whose result depends on the answer.
  static Future<bool> browserFileExists(
    TursoBrowserLocation location, {
    required TursoWebOptions web,
  }) => platform.browserFileExists(location, webOptions: web);

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
    final snapshot = SqlParameters.snapshot(parameters, namedParameters);
    return _enqueue(() => _runBackendOperation(() => _backend.query(sql, snapshot)));
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
    final snapshot = SqlParameters.snapshot(parameters, namedParameters);
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
    return _enqueue(
      () => ManagedTransaction(_backend, _runBackendOperation, _retire).run(
        (tx) => runZoned(() => action(tx), zoneValues: {_transactionZoneKey: true}),
      ),
    );
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
    return _closeFuture ??= _tail.then((_) => _backend.close());
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

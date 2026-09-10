import 'dart:async';
import 'dart:typed_data';

import 'package:turso/src/internal/backend.dart';
import 'package:turso/src/internal/backend_native.dart'
    if (dart.library.js_interop) 'package:turso/src/internal/backend_web.dart'
    as platform;
import 'package:turso/src/internal/parameters.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';
import 'package:turso/src/turso_result.dart';

/// One serialized embedded Turso connection.
final class TursoDatabase {
  TursoDatabase._(this._backend);

  final TursoBackend _backend;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;

  /// Opens a database at [location].
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
  Future<TursoQueryResult> query(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => Future<TursoQueryResult>.sync(() {
    final snapshot = snapshotParameters(parameters, namedParameters);
    return _enqueue(() async {
      final wireResult = await _backend.query(sql, snapshot);
      return _decodeQueryResult(wireResult);
    });
  });

  /// Runs one SQL statement and discards rows it returns.
  Future<TursoExecuteResult> execute(
    String sql, {
    List<Object?> parameters = const [],
    Map<String, Object?> namedParameters = const {},
  }) => Future<TursoExecuteResult>.sync(() {
    final snapshot = snapshotParameters(parameters, namedParameters);
    return _enqueue(() async {
      final rowsAffected = await _backend.execute(sql, snapshot);
      return TursoExecuteResult(rowsAffected: rowsAffected);
    });
  });

  /// Runs [action] inside one deferred transaction.
  Future<T> transaction<T>(Future<T> Function(TursoTransaction tx) action) async {
    throw UnimplementedError();
  }

  /// Drains accepted work and releases the database.
  Future<void> close() {
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
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
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

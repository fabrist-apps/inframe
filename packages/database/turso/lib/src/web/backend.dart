import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:turso/src/backend.dart';
import 'package:turso/src/parameters.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';
import 'package:turso/src/turso_result.dart';
import 'package:web/web.dart' as web;

/// Opens the web backend selected by conditional import.
Future<TursoBackend> openBackend(
  TursoLocation location, {
  TursoEncryption? encryption,
  TursoWebOptions? web,
}) async {
  if (location is TursoFileLocation) {
    throw const TursoUnsupportedException('File locations are unavailable on Flutter web.');
  }
  if (web == null) {
    throw ArgumentError.notNull('web');
  }

  final path = switch (location) {
    TursoBrowserLocation(:final name) => name,
    TursoMemoryLocation() => ':memory:',
    TursoFileLocation() => throw StateError('Validated above.'),
  };
  return _WebBackend.open(
    web.moduleUri,
    path: path,
    persistent: location is TursoBrowserLocation,
    encryption: encryption,
  );
}

/// Checks for a browser file without creating it or acquiring a sync access handle.
Future<bool> browserFileExists(
  TursoBrowserLocation location, {
  required TursoWebOptions webOptions,
}) async {
  final worker = web.Worker(
    webOptions.moduleUri.toString().toJS,
    web.WorkerOptions(type: 'module', name: 'Turso OPFS inspection'),
  );
  final backend = _WebBackend._(worker);
  try {
    final result = await backend._request('exists', {'path': location.path});
    final inspection = result! as Map<Object?, Object?>;
    _verifyBridgeVersion(inspection['upstreamVersion']! as String);
    return inspection['exists']! as bool;
  } finally {
    backend._closed = true;
    worker.terminate();
  }
}

/// Owns one browser bridge worker and its request lifecycle.
final class _WebBackend implements TursoBackend {
  _WebBackend._(this._worker) {
    _worker.onmessage = _handleMessage.toJS;
    _worker.onerror = _handleWorkerFailure.toJS;
    _worker.onmessageerror = _handleWorkerFailure.toJS;
  }

  final web.Worker _worker;
  final Map<int, Completer<Object?>> _pending = {};
  var _nextRequestId = 0;
  var _closed = false;
  TursoPlatformException? _workerFailure;

  @override
  late final TursoCapabilities capabilities;

  static Future<_WebBackend> open(
    Uri moduleUri, {
    required String path,
    required bool persistent,
    required TursoEncryption? encryption,
  }) async {
    final worker = web.Worker(
      moduleUri.toString().toJS,
      web.WorkerOptions(type: 'module', name: 'Turso database'),
    );
    final backend = _WebBackend._(worker);
    try {
      final result = await backend._request('open', {
        'path': path,
        'persistent': persistent,
        'encryption': encryption == null
            ? null
            : {
                'cipher': encryption.cipher.name,
                'key': encryption.key.toList(growable: false),
              },
      });
      final handshake = result! as Map<Object?, Object?>;
      _verifyBridgeVersion(handshake['upstreamVersion']! as String);
      final advertised = handshake['capabilities']! as Map<Object?, Object?>;
      backend.capabilities = TursoCapabilities(
        fts: advertised['fts']! as bool,
        vectorFunctions: advertised['vectorFunctions']! as bool,
        vectorIndexes: advertised['vectorIndexes']! as bool,
      );
      return backend;
    } on Object {
      worker.terminate();
      rethrow;
    }
  }

  @override
  Future<TursoQueryResult> query(String sql, SqlParameters parameters) async {
    final result = await _request('query', {
      'sql': sql,
      'parameters': _encodeParameters(parameters),
    });
    return _decodeQueryResult(result! as List<Object?>);
  }

  @override
  Future<BigInt> execute(String sql, SqlParameters parameters) async {
    final result = await _request('execute', {
      'sql': sql,
      'parameters': _encodeParameters(parameters),
    });
    return BigInt.parse(result! as String);
  }

  Future<Object?> _request(String operation, Object? payload) {
    final failure = _workerFailure;
    if (failure != null) return Future<Object?>.error(failure);
    if (_closed) return Future<Object?>.error(StateError('The browser worker is closed.'));

    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _worker.postMessage({'id': id, 'operation': operation, 'payload': payload}.jsify());
    return completer.future;
  }

  void _handleMessage(web.MessageEvent event) {
    final reply = event.data.dartify()! as Map<Object?, Object?>;
    final id = (reply['id']! as num).toInt();
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (reply['ok'] == true) {
      completer.complete(reply['result']);
    } else {
      completer.completeError(_decodeWebError(reply['error']! as Map<Object?, Object?>));
    }
  }

  void _handleWorkerFailure(web.Event _) {
    if (_workerFailure != null) return;
    _workerFailure = const TursoPlatformException(
      'The Turso browser worker stopped unexpectedly; an interrupted write may have committed.',
    );
    unawaited(retire());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      if (_workerFailure == null) {
        final id = _nextRequestId++;
        final completer = Completer<Object?>();
        _pending[id] = completer;
        _worker.postMessage({'id': id, 'operation': 'close', 'payload': null}.jsify());
        await completer.future;
      }
    } finally {
      _worker.terminate();
    }
  }

  @override
  Future<void> retire() async {
    _closed = true;
    final failure = _workerFailure ??= const TursoPlatformException(
      'The Turso browser worker was retired.',
    );
    for (final pending in _pending.values) {
      pending.completeError(failure);
    }
    _pending.clear();
    _worker.terminate();
  }
}

void _verifyBridgeVersion(String version) {
  if (version != '0.8.0-pre.10') {
    throw TursoPlatformException('Expected Turso web 0.8.0-pre.10, but loaded $version.');
  }
}

Map<String, Object?> _encodeParameters(SqlParameters parameters) => switch (parameters) {
  NamedParameters(:final values) => {
    'named': true,
    'values': [
      for (final entry in values.entries) [entry.key, _encodeValue(entry.value)],
    ],
  },
  PositionalParameters(:final values) => {
    'named': false,
    'values': [for (final value in values) _encodeValue(value)],
  },
};

TursoQueryResult _decodeQueryResult(List<Object?> result) {
  final columns = [
    for (final column in (result[0]! as List<Object?>).cast<List<Object?>>())
      TursoColumn(name: column[0]! as String, declaredType: column[1] as String?),
  ];
  final rows = [
    for (final row in (result[1]! as List<Object?>).cast<List<Object?>>())
      TursoRow(columns, row.map(_decodeValue).toList()),
  ];
  return TursoQueryResult(columns: columns, rows: rows);
}

Object? _decodeValue(Object? value) {
  if (value is! List<Object?>) return value;
  return switch (value[0]) {
    'integer' => BigInt.parse(value[1]! as String),
    'blob' => Uint8List.fromList((value[1]! as List<Object?>).cast<int>()),
    _ => throw StateError('Unknown browser value encoding: ${value[0]}.'),
  };
}

Object? _encodeValue(Object? value) => switch (value) {
  BigInt() => ['integer', value.toString()],
  Uint8List() => ['blob', value.toList(growable: false)],
  _ => value,
};

Object _decodeWebError(Map<Object?, Object?> error) => switch (error['kind']) {
  'argument' => ArgumentError(error['message']! as String),
  'unsupported' => TursoUnsupportedException(error['message']! as String),
  'database' => TursoDatabaseException(
    error['message']! as String,
    code: error['code'] as int?,
  ),
  _ => TursoPlatformException(error['message']! as String),
};

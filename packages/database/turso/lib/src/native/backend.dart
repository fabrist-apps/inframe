import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:turso/src/backend.dart';
import 'package:turso/src/native/connection.dart';
import 'package:turso/src/parameters.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';
import 'package:turso/src/turso_result.dart';

/// Opens the native backend selected by conditional import.
Future<TursoBackend> openBackend(
  TursoLocation location, {
  TursoEncryption? encryption,
  TursoWebOptions? web,
}) {
  if (location is TursoBrowserLocation) {
    throw const TursoUnsupportedException('Browser locations require Flutter web.');
  }
  if (web != null) {
    throw ArgumentError.value(web, 'web', 'Native databases do not accept browser options.');
  }
  return NativeBackend.open(location, encryption: encryption);
}

/// Native runtimes cannot inspect browser storage.
Future<bool> browserFileExists(
  TursoBrowserLocation location, {
  required TursoWebOptions webOptions,
}) => throw const TursoUnsupportedException('Browser file inspection requires Flutter web.');

/// Owns one native Turso connection in a dedicated isolate.
final class NativeBackend implements TursoBackend {
  NativeBackend._(
    this._isolate,
    this._receivePort,
    this._subscription,
    this._statusPort,
    this._statusSubscription,
    this._workerPort,
    this.capabilities,
  );

  static const _closeTimeout = Duration(seconds: 5);

  final Isolate _isolate;
  final ReceivePort _receivePort;
  final StreamSubscription<Object?> _subscription;
  final ReceivePort _statusPort;
  final StreamSubscription<Object?> _statusSubscription;
  final SendPort _workerPort;
  final Map<int, Completer<Object?>> _pending = {};
  var _nextRequestId = 0;
  var _closed = false;
  TursoPlatformException? _workerFailure;

  @override
  final TursoCapabilities capabilities;

  /// Opens [location] in a dedicated native isolate.
  static Future<NativeBackend> open(
    TursoLocation location, {
    TursoEncryption? encryption,
  }) async {
    final path = switch (location) {
      TursoFileLocation(:final path) => path,
      TursoMemoryLocation() => ':memory:',
      TursoBrowserLocation() => throw const TursoUnsupportedException(
        'Browser locations require Flutter web.',
      ),
    };

    final receivePort = ReceivePort('Turso native replies');
    final statusPort = ReceivePort('Turso native status');
    final ready = Completer<_Ready>();
    late final StreamSubscription<Object?> subscription;
    late final StreamSubscription<Object?> statusSubscription;
    NativeBackend? backend;
    var failedBeforeBackend = false;
    subscription = receivePort.listen((message) {
      if (!ready.isCompleted) {
        ready.complete(message! as _Ready);
        return;
      }
      backend?._handleReply(message! as _Reply);
    });

    statusSubscription = statusPort.listen((_) {
      if (!ready.isCompleted) {
        ready.complete((
          port: null,
          error: const TursoPlatformException(
            'The Turso native worker stopped during initialization.',
          ),
        ));
        return;
      }
      final owner = backend;
      if (owner == null) {
        failedBeforeBackend = true;
      } else {
        owner._handleWorkerFailure();
      }
    });

    late final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _runNativeWorker,
        (
          replyPort: receivePort.sendPort,
          path: path,
          cipher: encryption?.cipher.name,
          key: encryption?.key,
        ),
        debugName: 'Turso native database',
        onError: statusPort.sendPort,
        onExit: statusPort.sendPort,
      );
    } on Object {
      await subscription.cancel();
      await statusSubscription.cancel();
      receivePort.close();
      statusPort.close();
      rethrow;
    }

    final handshake = await ready.future;
    if (handshake.error != null) {
      await subscription.cancel();
      await statusSubscription.cancel();
      receivePort.close();
      statusPort.close();
      isolate.kill();
      Error.throwWithStackTrace(handshake.error!, StackTrace.current);
    }

    backend = NativeBackend._(
      isolate,
      receivePort,
      subscription,
      statusPort,
      statusSubscription,
      handshake.port!,
      const TursoCapabilities(fts: true, vectorFunctions: true, vectorIndexes: false),
    );
    if (failedBeforeBackend) backend._handleWorkerFailure();
    return backend;
  }

  @override
  Future<TursoQueryResult> query(String sql, SqlParameters parameters) =>
      _request(_Query(_nextRequestId++, sql, parameters));

  @override
  Future<BigInt> execute(String sql, SqlParameters parameters) =>
      _request(_Execute(_nextRequestId++, sql, parameters));

  Future<T> _request<T>(_Command<T> command) async {
    final failure = _workerFailure;
    if (failure != null) throw failure;
    if (_closed) throw StateError('The native worker is closed.');
    final completer = Completer<Object?>();
    _pending[command.requestId] = completer;
    _workerPort.send(command);
    return (await completer.future) as T;
  }

  void _handleReply(_Reply reply) {
    final completer = _pending.remove(reply.requestId);
    if (completer == null) return;
    if (reply.error == null) {
      completer.complete(reply.result);
    } else {
      completer.completeError(reply.error!);
    }
  }

  void _handleWorkerFailure() {
    if (_workerFailure != null || (_closed && _pending.isEmpty)) return;
    _workerFailure = const TursoPlatformException(
      'The Turso native worker stopped unexpectedly; an interrupted write may have committed.',
    );
    unawaited(retire());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _closeWorker();
    } finally {
      await _disposeWorker(const TursoPlatformException('The native worker stopped.'));
    }
  }

  @override
  Future<void> retire() async {
    final workerCanClose = _workerFailure == null;
    _closed = true;
    final failure = _workerFailure ??= const TursoPlatformException(
      'The Turso native worker was retired; an interrupted write may have committed.',
    );
    try {
      if (workerCanClose) {
        await _closeWorker();
      }
    } finally {
      await _disposeWorker(failure);
    }
  }

  Future<void> _closeWorker() async {
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    _workerPort.send(_Close(requestId));
    await completer.future.timeout(
      _closeTimeout,
      onTimeout: () => throw const TursoPlatformException(
        'The Turso native worker did not close within five seconds.',
      ),
    );
  }

  Future<void> _disposeWorker(TursoPlatformException failure) async {
    await _subscription.cancel();
    await _statusSubscription.cancel();
    _receivePort.close();
    _statusPort.close();
    _isolate.kill();
    for (final pending in _pending.values) {
      pending.completeError(failure);
    }
    _pending.clear();
  }
}

typedef _Start = ({SendPort replyPort, String path, String? cipher, Uint8List? key});
typedef _Ready = ({SendPort? port, Object? error});
typedef _Reply = ({int requestId, Object? result, Object? error});

sealed class _Command<T> {
  const _Command(this.requestId);
  final int requestId;
  T run(NativeConnection connection);
}

final class _Query extends _Command<TursoQueryResult> {
  const _Query(super.requestId, this.sql, this.parameters);
  final String sql;
  final SqlParameters parameters;
  @override
  TursoQueryResult run(NativeConnection connection) => connection.query(sql, parameters);
}

final class _Execute extends _Command<BigInt> {
  const _Execute(super.requestId, this.sql, this.parameters);
  final String sql;
  final SqlParameters parameters;
  @override
  BigInt run(NativeConnection connection) => connection.execute(sql, parameters);
}

final class _Close extends _Command<void> {
  const _Close(super.requestId);
  @override
  void run(NativeConnection connection) => connection.close();
}

void _runNativeWorker(_Start start) {
  final sensitiveValues = _sensitiveKeyRepresentations(start.key);
  ReceivePort? requests;
  NativeConnection? connection;
  try {
    connection = NativeConnection.open(path: start.path, cipher: start.cipher, key: start.key);
    requests = ReceivePort('Turso native requests');
    start.replyPort.send((port: requests.sendPort, error: null));
    requests.listen((message) {
      final command = message! as _Command<Object?>;
      try {
        final result = command.run(connection!);
        start.replyPort.send((requestId: command.requestId, result: result, error: null));
        if (command is _Close) requests!.close();
      } on Object catch (error) {
        start.replyPort.send((
          requestId: command.requestId,
          result: null,
          error: _sanitizeError(error, sensitiveValues),
        ));
      }
    });
  } on Object catch (error) {
    try {
      connection?.close();
    } on Object {
      // Preserve and report the failure that interrupted initialization.
    }
    requests?.close();
    start.replyPort.send((port: null, error: _sanitizeError(error, sensitiveValues)));
  } finally {
    start.key?.fillRange(0, start.key!.length, 0);
  }
}

Set<String> _sensitiveKeyRepresentations(Uint8List? key) {
  if (key == null) return const {};
  final hex = key.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return {hex, hex.toUpperCase(), base64Encode(key), key.join(',')};
}

Object _sanitizeError(Object error, Set<String> sensitiveValues) {
  String redact(String message) {
    var redacted = message;
    for (final value in sensitiveValues) {
      redacted = redacted.replaceAll(value, '[REDACTED]');
    }
    return redacted;
  }

  return switch (error) {
    TursoDatabaseException(:final message, :final code) => TursoDatabaseException(
      redact(message),
      code: code,
    ),
    TursoUnsupportedException(:final message) => TursoUnsupportedException(redact(message)),
    ArgumentError() => ArgumentError(redact(error.toString())),
    StateError() => StateError(redact(error.toString())),
    _ => TursoPlatformException(redact(error.toString())),
  };
}

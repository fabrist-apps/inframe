import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:turso/src/internal/backend.dart';
import 'package:turso/src/internal/parameters.dart';
import 'package:turso/src/native/turso_bindings_generated.dart' as bindings;
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_location.dart';
import 'package:turso/src/turso_options.dart';

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
    final ready = Completer<List<Object?>>();
    late final StreamSubscription<Object?> subscription;
    late final StreamSubscription<Object?> statusSubscription;
    NativeBackend? backend;
    var failedBeforeBackend = false;
    subscription = receivePort.listen((message) {
      final reply = message! as List<Object?>;
      if (!ready.isCompleted) {
        ready.complete(reply);
        return;
      }
      backend?._handleReply(reply);
    });

    statusSubscription = statusPort.listen((_) {
      if (!ready.isCompleted) {
        ready.complete([
          false,
          'platform',
          'The Turso native worker stopped during initialization.',
          null,
        ]);
        return;
      }
      final owner = backend;
      if (owner == null) {
        failedBeforeBackend = true;
      } else {
        owner._handleWorkerFailure();
      }
    });

    final encodedKey = encryption == null ? null : base64Encode(encryption.key);
    late final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _runNativeWorker,
        <Object?>[
          receivePort.sendPort,
          path,
          encryption?.cipher.name,
          encodedKey,
        ],
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
    if (handshake[0] != true) {
      await subscription.cancel();
      await statusSubscription.cancel();
      receivePort.close();
      statusPort.close();
      isolate.kill();
      Error.throwWithStackTrace(_decodeWorkerError(handshake), StackTrace.current);
    }

    backend = NativeBackend._(
      isolate,
      receivePort,
      subscription,
      statusPort,
      statusSubscription,
      handshake[1]! as SendPort,
      const TursoCapabilities(fts: true, vectorFunctions: true, vectorIndexes: false),
    );
    if (failedBeforeBackend) backend._handleWorkerFailure();
    return backend;
  }

  @override
  Future<List<Object?>> query(String sql, SqlParameterSnapshot parameters) async {
    final result = await _request('query', [sql, parameters.named, parameters.values]);
    return result! as List<Object?>;
  }

  @override
  Future<BigInt> execute(String sql, SqlParameterSnapshot parameters) async {
    final result = await _request('execute', [sql, parameters.named, parameters.values]);
    return BigInt.parse(result! as String);
  }

  Future<Object?> _request(String operation, Object? payload) {
    final failure = _workerFailure;
    if (failure != null) return Future<Object?>.error(failure);
    if (_closed) return Future<Object?>.error(StateError('The native worker is closed.'));
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    _workerPort.send([requestId, operation, payload]);
    return completer.future;
  }

  void _handleReply(List<Object?> reply) {
    final requestId = reply[0]! as int;
    final completer = _pending.remove(requestId);
    if (completer == null) return;
    if (reply[1] == true) {
      completer.complete(reply[2]);
    } else {
      completer.completeError(_decodeWorkerError(reply.sublist(1)));
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
    _workerPort.send([requestId, 'close', null]);
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

void _runNativeWorker(List<Object?> start) {
  final replyPort = start[0]! as SendPort;
  final key = start[3] == null ? null : base64Decode(start[3]! as String);
  final sensitiveValues = _sensitiveKeyRepresentations(key);
  ReceivePort? requests;
  _NativeDatabase? database;
  try {
    database = _NativeDatabase.open(
      path: start[1]! as String,
      cipher: start[2] as String?,
      key: key,
    );
    requests = ReceivePort('Turso native requests');
    replyPort.send([true, requests.sendPort]);
    requests.listen((message) {
      final request = message! as List<Object?>;
      final requestId = request[0]! as int;
      try {
        final result = switch (request[1]) {
          'query' => database!.query(
            (request[2]! as List<Object?>)[0]! as String,
            (request[2]! as List<Object?>)[2]! as List<Object?>,
            named: (request[2]! as List<Object?>)[1]! as bool,
          ),
          'execute' => database!.execute(
            (request[2]! as List<Object?>)[0]! as String,
            (request[2]! as List<Object?>)[2]! as List<Object?>,
            named: (request[2]! as List<Object?>)[1]! as bool,
          ),
          'close' => null,
          _ => throw StateError('Unknown native request: ${request[1]}.'),
        };
        if (request[1] == 'close') {
          database!.close();
          replyPort.send([requestId, true, null]);
          requests!.close();
        } else {
          replyPort.send([requestId, true, result]);
        }
      } on Object catch (error) {
        replyPort.send([requestId, ..._encodeWorkerError(error, sensitiveValues)]);
      }
    });
  } on Object catch (error) {
    try {
      database?.close();
    } on Object {
      // Preserve and report the failure that interrupted initialization.
    }
    requests?.close();
    replyPort.send(_encodeWorkerError(error, sensitiveValues));
  }
}

Set<String> _sensitiveKeyRepresentations(Uint8List? key) {
  if (key == null) return const {};
  final hex = _encodeHex(key);
  return {hex, hex.toUpperCase(), base64Encode(key), key.join(',')};
}

List<Object?> _encodeWorkerError(Object error, Set<String> sensitiveValues) {
  final (kind, message, code) = switch (error) {
    TursoDatabaseException(:final message, :final code) => ('database', message, code),
    TursoUnsupportedException(:final message) => ('unsupported', message, null),
    ArgumentError() => ('argument', error.toString(), null),
    StateError() => ('state', error.toString(), null),
    _ => ('platform', error.toString(), null),
  };
  return [false, kind, _redact(message, sensitiveValues), code];
}

String _redact(String message, Set<String> sensitiveValues) {
  var redacted = message;
  for (final sensitiveValue in sensitiveValues) {
    redacted = redacted.replaceAll(sensitiveValue, '[REDACTED]');
  }
  return redacted;
}

Object _decodeWorkerError(List<Object?> reply) => switch (reply[1]) {
  'database' => TursoDatabaseException(reply[2]! as String, code: reply[3] as int?),
  'unsupported' => TursoUnsupportedException(reply[2]! as String),
  'argument' => ArgumentError(reply[2]! as String),
  'state' => StateError(reply[2]! as String),
  _ => TursoPlatformException(reply[2]! as String),
};

final class _NativeDatabase {
  _NativeDatabase._(this._database, this._connection);

  factory _NativeDatabase.open({
    required String path,
    required String? cipher,
    required Uint8List? key,
  }) {
    final version = bindings.turso_version().cast<Utf8>().toDartString();
    if (version != '0.8.0-pre.10') {
      throw TursoPlatformException(
        'Expected Turso 0.8.0-pre.10, but loaded $version.',
      );
    }

    final setup = calloc<bindings.turso_config_t>();
    final errorOut = calloc<Pointer<Char>>();
    Pointer<bindings.turso_database_t> database = nullptr;
    Pointer<bindings.turso_connection_t> connection = nullptr;
    try {
      final setupStatus = bindings.turso_setup(setup, errorOut);
      _checkStatic(setupStatus, errorOut);

      final pathPointer = path.toNativeUtf8();
      final experimentalFeaturesPointer = (key == null ? 'index_method' : 'encryption,index_method')
          .toNativeUtf8();
      final cipherPointer = cipher == null ? nullptr : cipher.toNativeUtf8();
      final hexKey = key == null ? null : _encodeHex(key);
      final hexKeyPointer = hexKey == null ? nullptr : hexKey.toNativeUtf8();
      final config = calloc<bindings.turso_database_config_t>();
      final databaseOut = calloc<Pointer<bindings.turso_database_t>>();
      try {
        config.ref
          ..async_io = 0
          ..path = pathPointer.cast()
          ..experimental_features = experimentalFeaturesPointer.cast()
          ..vfs = nullptr
          ..encryption_cipher = cipherPointer.cast()
          ..encryption_hexkey = hexKeyPointer.cast()
          ..page_codec = nullptr
          ..open_flags = 0;
        _checkStatic(
          bindings.turso_database_new(config, databaseOut, errorOut),
          errorOut,
        );
        database = databaseOut.value;
      } finally {
        if (hexKey != null) {
          hexKeyPointer
              .cast<Uint8>()
              .asTypedList(hexKey.length + 1)
              .fillRange(
                0,
                hexKey.length + 1,
                0,
              );
        }
        calloc
          ..free(pathPointer)
          ..free(experimentalFeaturesPointer)
          ..free(cipherPointer)
          ..free(hexKeyPointer)
          ..free(config)
          ..free(databaseOut);
      }

      _checkStatic(bindings.turso_database_open(database, errorOut), errorOut);
      final connectionOut = calloc<Pointer<bindings.turso_connection_t>>();
      try {
        _checkStatic(
          bindings.turso_database_connect(database, connectionOut, errorOut),
          errorOut,
        );
        connection = connectionOut.value;
      } finally {
        calloc.free(connectionOut);
      }
      return _NativeDatabase._(database, connection);
    } on Object {
      if (connection != nullptr) bindings.turso_connection_deinit(connection);
      if (database != nullptr) bindings.turso_database_deinit(database);
      rethrow;
    } finally {
      calloc
        ..free(setup)
        ..free(errorOut);
    }
  }

  final Pointer<bindings.turso_database_t> _database;
  final Pointer<bindings.turso_connection_t> _connection;
  var _closed = false;

  List<Object?> query(String sql, List<Object?> parameters, {required bool named}) {
    final statement = _prepare(sql, parameters, named: named);
    try {
      final columnCount = bindings.turso_statement_column_count(statement);
      final columns = [
        for (var index = 0; index < columnCount; index++)
          [
            _readOwnedString(bindings.turso_statement_column_name(statement, index)) ??
                (throw const TursoDatabaseException('Upstream omitted a result column name.')),
            _readOwnedString(bindings.turso_statement_column_decltype(statement, index)),
          ],
      ];
      final rows = <Object?>[];
      while (true) {
        final status = bindings.turso_statement_step(statement, nullptr);
        if (status == bindings.turso_status_code_t.TURSO_ROW) {
          rows.add([
            for (var index = 0; index < columnCount; index++) _readValue(statement, index),
          ]);
          continue;
        }
        if (status == bindings.turso_status_code_t.TURSO_IO) {
          _runIo(statement);
          continue;
        }
        if (status == bindings.turso_status_code_t.TURSO_DONE) break;
        _throwStatus(status, nullptr);
      }
      return [columns, rows];
    } finally {
      _finalize(statement);
    }
  }

  String execute(String sql, List<Object?> parameters, {required bool named}) {
    final statement = _prepare(sql, parameters, named: named);
    final rowsChanged = calloc<Uint64>();
    try {
      while (true) {
        final status = bindings.turso_statement_execute(statement, rowsChanged, nullptr);
        if (status == bindings.turso_status_code_t.TURSO_IO) {
          _runIo(statement);
          continue;
        }
        if (status == bindings.turso_status_code_t.TURSO_DONE) return rowsChanged.value.toString();
        _throwStatus(status, nullptr);
      }
    } finally {
      calloc.free(rowsChanged);
      _finalize(statement);
    }
  }

  Pointer<bindings.turso_statement_t> _prepare(
    String sql,
    List<Object?> parameters, {
    required bool named,
  }) {
    final sqlPointer = sql.toNativeUtf8();
    final statementOut = calloc<Pointer<bindings.turso_statement_t>>();
    final tailIndex = calloc<Size>();
    final errorOut = calloc<Pointer<Char>>();
    try {
      final status = bindings.turso_connection_prepare_first(
        _connection,
        sqlPointer.cast(),
        statementOut,
        tailIndex,
        errorOut,
      );
      _check(status, errorOut);
      final statement = statementOut.value;
      if (statement == nullptr) {
        throw ArgumentError.value(sql, 'sql', 'Must contain one SQL statement.');
      }
      try {
        _rejectTrailingStatement(sql, tailIndex.value);
        _bind(statement, parameters, named: named);
      } on Object {
        _finalize(statement);
        rethrow;
      }
      return statement;
    } finally {
      calloc
        ..free(sqlPointer)
        ..free(statementOut)
        ..free(tailIndex)
        ..free(errorOut);
    }
  }

  void _rejectTrailingStatement(String sql, int tailByteIndex) {
    final sqlBytes = utf8.encode(sql);
    if (tailByteIndex >= sqlBytes.length) return;

    final tail = utf8.decode(sqlBytes.sublist(tailByteIndex));
    final tailPointer = tail.toNativeUtf8();
    final trailingOut = calloc<Pointer<bindings.turso_statement_t>>();
    final trailingTail = calloc<Size>();
    final errorOut = calloc<Pointer<Char>>();
    try {
      final status = bindings.turso_connection_prepare_first(
        _connection,
        tailPointer.cast(),
        trailingOut,
        trailingTail,
        errorOut,
      );
      _check(status, errorOut);
      if (trailingOut.value != nullptr) {
        _finalize(trailingOut.value);
        throw ArgumentError.value(sql, 'sql', 'Must contain exactly one SQL statement.');
      }
    } finally {
      calloc
        ..free(tailPointer)
        ..free(trailingOut)
        ..free(trailingTail)
        ..free(errorOut);
    }
  }

  void _bind(
    Pointer<bindings.turso_statement_t> statement,
    List<Object?> parameters, {
    required bool named,
  }) {
    final expectedCount = bindings.turso_statement_parameters_count(statement);
    if (!named) {
      if (parameters.length != expectedCount) {
        throw ArgumentError(
          'Expected $expectedCount positional parameters, got ${parameters.length}.',
        );
      }
      for (var index = 0; index < parameters.length; index++) {
        _bindAt(statement, index + 1, parameters[index]);
      }
      return;
    }

    final supplied = <String, Object?>{
      for (final entry in parameters.cast<List<Object?>>()) entry[0]! as String: entry[1],
    };
    final expected = <String>[];
    for (var index = 1; index <= expectedCount; index++) {
      final name = _readOwnedString(bindings.turso_statement_parameter_name(statement, index));
      if (name == null) {
        throw ArgumentError('Named parameters cannot bind an unnamed SQL placeholder.');
      }
      expected.add(name);
    }
    if (supplied.keys.toSet().length != supplied.length ||
        supplied.keys.toSet().difference(expected.toSet()).isNotEmpty ||
        expected.toSet().difference(supplied.keys.toSet()).isNotEmpty) {
      throw ArgumentError('Named parameters must exactly match: ${expected.toSet().join(', ')}.');
    }
    for (var index = 0; index < expected.length; index++) {
      _bindAt(statement, index + 1, supplied[expected[index]]);
    }
  }

  void _bindAt(Pointer<bindings.turso_statement_t> statement, int position, Object? value) {
    final status = switch (value) {
      null => bindings.turso_statement_bind_positional_null(statement, position),
      BigInt() => bindings.turso_statement_bind_positional_int(statement, position, value.toInt()),
      double() => bindings.turso_statement_bind_positional_double(statement, position, value),
      String() => _bindText(statement, position, value),
      Uint8List() => _bindBlob(statement, position, value),
      _ => throw StateError('An unnormalized parameter reached the native worker.'),
    };
    if (status != bindings.turso_status_code_t.TURSO_OK) _throwStatus(status, nullptr);
  }

  bindings.turso_status_code_t _bindText(
    Pointer<bindings.turso_statement_t> statement,
    int position,
    String value,
  ) {
    final bytes = utf8.encode(value);
    final pointer = calloc<Uint8>(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    try {
      return bindings.turso_statement_bind_positional_text(
        statement,
        position,
        pointer.cast(),
        bytes.length,
      );
    } finally {
      calloc.free(pointer);
    }
  }

  bindings.turso_status_code_t _bindBlob(
    Pointer<bindings.turso_statement_t> statement,
    int position,
    Uint8List value,
  ) {
    final pointer = calloc<Uint8>(value.length);
    pointer.asTypedList(value.length).setAll(0, value);
    try {
      return bindings.turso_statement_bind_positional_blob(
        statement,
        position,
        pointer.cast(),
        value.length,
      );
    } finally {
      calloc.free(pointer);
    }
  }

  Object? _readValue(Pointer<bindings.turso_statement_t> statement, int index) {
    final kind = bindings.turso_statement_row_value_kind(statement, index);
    return switch (kind) {
      bindings.turso_type_t.TURSO_TYPE_NULL => null,
      bindings.turso_type_t.TURSO_TYPE_INTEGER => [
        'integer',
        bindings.turso_statement_row_value_int(statement, index).toString(),
      ],
      bindings.turso_type_t.TURSO_TYPE_REAL => bindings.turso_statement_row_value_double(
        statement,
        index,
      ),
      bindings.turso_type_t.TURSO_TYPE_TEXT => _readBorrowedBytes(statement, index, text: true),
      bindings.turso_type_t.TURSO_TYPE_BLOB => [
        'blob',
        _readBorrowedBytes(statement, index, text: false),
      ],
      _ => throw const TursoDatabaseException('Upstream returned an unknown SQL value type.'),
    };
  }

  Object _readBorrowedBytes(
    Pointer<bindings.turso_statement_t> statement,
    int index, {
    required bool text,
  }) {
    final length = bindings.turso_statement_row_value_bytes_count(statement, index);
    if (length < 0) throw const TursoDatabaseException('Upstream returned an invalid byte length.');
    final pointer = bindings.turso_statement_row_value_bytes_ptr(statement, index);
    final bytes = Uint8List.fromList(pointer.cast<Uint8>().asTypedList(length));
    return text ? utf8.decode(bytes) : bytes.toList(growable: false);
  }

  void _runIo(Pointer<bindings.turso_statement_t> statement) {
    final status = bindings.turso_statement_run_io(statement, nullptr);
    if (status != bindings.turso_status_code_t.TURSO_OK &&
        status != bindings.turso_status_code_t.TURSO_DONE) {
      _throwStatus(status, nullptr);
    }
  }

  void _finalize(Pointer<bindings.turso_statement_t> statement) {
    try {
      while (true) {
        final status = bindings.turso_statement_finalize(statement, nullptr);
        if (status == bindings.turso_status_code_t.TURSO_IO) {
          _runIo(statement);
          continue;
        }
        break;
      }
    } finally {
      bindings.turso_statement_deinit(statement);
    }
  }

  String? _readOwnedString(Pointer<Char> pointer) {
    if (pointer == nullptr) return null;
    try {
      return pointer.cast<Utf8>().toDartString();
    } finally {
      bindings.turso_str_deinit(pointer);
    }
  }

  Never _throwStatus(
    bindings.turso_status_code_t status,
    Pointer<Pointer<Char>> errorOut,
  ) {
    final message = errorOut == nullptr || errorOut.value == nullptr
        ? 'Upstream Turso failed with status ${status.name}.'
        : _readOwnedString(errorOut.value)!;
    throw TursoDatabaseException(message, code: status.value);
  }

  void _check(bindings.turso_status_code_t status, Pointer<Pointer<Char>> errorOut) {
    if (status != bindings.turso_status_code_t.TURSO_OK) _throwStatus(status, errorOut);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final errorOut = calloc<Pointer<Char>>();
    Object? failure;
    StackTrace? failureStack;
    try {
      final status = bindings.turso_connection_close(_connection, errorOut);
      if (status != bindings.turso_status_code_t.TURSO_OK) _throwStatus(status, errorOut);
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      calloc.free(errorOut);
      bindings.turso_connection_deinit(_connection);
      bindings.turso_database_deinit(_database);
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }
}

String _encodeHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void _checkStatic(
  bindings.turso_status_code_t status,
  Pointer<Pointer<Char>> errorOut,
) {
  if (status == bindings.turso_status_code_t.TURSO_OK) return;
  final errorPointer = errorOut.value;
  final message = errorPointer == nullptr
      ? 'Upstream Turso failed with status ${status.name}.'
      : errorPointer.cast<Utf8>().toDartString();
  if (errorPointer != nullptr) {
    bindings.turso_str_deinit(errorPointer);
    errorOut.value = nullptr;
  }
  throw TursoDatabaseException(message, code: status.value);
}

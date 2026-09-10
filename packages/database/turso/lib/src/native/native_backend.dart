import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:turso/src/internal/backend.dart';
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
    this._workerPort,
    this.capabilities,
  );

  final Isolate _isolate;
  final ReceivePort _receivePort;
  final StreamSubscription<Object?> _subscription;
  final SendPort _workerPort;
  final Map<int, Completer<Object?>> _pending = {};
  var _nextRequestId = 0;
  var _closed = false;

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
    final ready = Completer<List<Object?>>();
    late final StreamSubscription<Object?> subscription;
    NativeBackend? backend;
    subscription = receivePort.listen((message) {
      final reply = message! as List<Object?>;
      if (!ready.isCompleted) {
        ready.complete(reply);
        return;
      }
      backend?._handleReply(reply);
    });

    final encodedKey = encryption == null ? null : base64Encode(encryption.key);
    final isolate = await Isolate.spawn(
      _runNativeWorker,
      <Object?>[
        receivePort.sendPort,
        path,
        encryption?.cipher.name,
        encodedKey,
      ],
      debugName: 'Turso native database',
    );

    final handshake = await ready.future;
    if (handshake[0] != true) {
      await subscription.cancel();
      receivePort.close();
      isolate.kill();
      Error.throwWithStackTrace(_decodeWorkerError(handshake), StackTrace.current);
    }

    return backend = NativeBackend._(
      isolate,
      receivePort,
      subscription,
      handshake[1]! as SendPort,
      const TursoCapabilities(fts: false, vectorFunctions: false, vectorIndexes: false),
    );
  }

  @override
  Future<List<Object?>> query(String sql, List<Object?> parameters) async {
    final result = await _request('query', [sql, parameters]);
    return result! as List<Object?>;
  }

  @override
  Future<BigInt> execute(String sql, List<Object?> parameters) async {
    final result = await _request('execute', [sql, parameters]);
    return BigInt.parse(result! as String);
  }

  Future<Object?> _request(String operation, Object? payload) {
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

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      final requestId = _nextRequestId++;
      final completer = Completer<Object?>();
      _pending[requestId] = completer;
      _workerPort.send([requestId, 'close', null]);
      await completer.future;
    } finally {
      await _subscription.cancel();
      _receivePort.close();
      _isolate.kill();
      for (final pending in _pending.values) {
        pending.completeError(const TursoPlatformException('The native worker stopped.'));
      }
      _pending.clear();
    }
  }
}

void _runNativeWorker(List<Object?> start) {
  final replyPort = start[0]! as SendPort;
  ReceivePort? requests;
  _NativeDatabase? database;
  try {
    database = _NativeDatabase.open(
      path: start[1]! as String,
      cipher: start[2] as String?,
      key: start[3] == null ? null : base64Decode(start[3]! as String),
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
            (request[2]! as List<Object?>)[1]! as List<Object?>,
          ),
          'execute' => database!.execute(
            (request[2]! as List<Object?>)[0]! as String,
            (request[2]! as List<Object?>)[1]! as List<Object?>,
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
        replyPort.send([requestId, ..._encodeWorkerError(error)]);
      }
    });
  } on Object catch (error) {
    database?.close();
    requests?.close();
    replyPort.send(_encodeWorkerError(error));
  }
}

List<Object?> _encodeWorkerError(Object error) => switch (error) {
  TursoDatabaseException(:final message, :final code) => [false, 'database', message, code],
  TursoUnsupportedException(:final message) => [false, 'unsupported', message, null],
  ArgumentError() => [false, 'argument', error.toString(), null],
  StateError() => [false, 'state', error.toString(), null],
  _ => [false, 'platform', error.toString(), null],
};

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
    if (cipher != null || key != null) {
      throw const TursoUnsupportedException(
        'Encryption is unavailable in this native build.',
      );
    }

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
      final config = calloc<bindings.turso_database_config_t>();
      final databaseOut = calloc<Pointer<bindings.turso_database_t>>();
      try {
        config.ref
          ..async_io = 0
          ..path = pathPointer.cast()
          ..experimental_features = nullptr
          ..vfs = nullptr
          ..encryption_cipher = nullptr
          ..encryption_hexkey = nullptr
          ..page_codec = nullptr
          ..open_flags = 0;
        _checkStatic(
          bindings.turso_database_new(config, databaseOut, errorOut),
          errorOut,
        );
        database = databaseOut.value;
      } finally {
        calloc
          ..free(pathPointer)
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

  List<Object?> query(String sql, List<Object?> parameters) {
    final statement = _prepare(sql, parameters);
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

  String execute(String sql, List<Object?> parameters) {
    final statement = _prepare(sql, parameters);
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

  Pointer<bindings.turso_statement_t> _prepare(String sql, List<Object?> parameters) {
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
        _bind(statement, parameters);
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

  void _bind(Pointer<bindings.turso_statement_t> statement, List<Object?> parameters) {
    final expectedCount = bindings.turso_statement_parameters_count(statement);
    final isNamed = parameters.isNotEmpty && parameters.first is List<Object?>;
    if (!isNamed) {
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

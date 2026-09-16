import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:turso/src/native/error.dart';
import 'package:turso/src/native/statement.dart';
import 'package:turso/src/native/turso_bindings_generated.dart' as bindings;
import 'package:turso/src/parameters.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_result.dart';

/// Owns the native database and connection handles on the worker isolate.
final class NativeConnection {
  NativeConnection._(this._database, this._connection);

  /// Opens and connects, releasing partially initialized handles on failure.
  factory NativeConnection.open({
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

    return using((arena) {
      final setup = arena<bindings.turso_config_t>();
      final errorOut = arena<Pointer<Char>>();
      Pointer<bindings.turso_database_t> database = nullptr;
      Pointer<bindings.turso_connection_t> connection = nullptr;
      try {
        checkStatus(bindings.turso_setup(setup, errorOut), errorOut);
        final hexKey = key == null ? null : _encodeHex(key);
        final hexKeyPointer = hexKey?.toNativeUtf8(allocator: arena) ?? nullptr;
        final config = arena<bindings.turso_database_config_t>();
        final databaseOut = arena<Pointer<bindings.turso_database_t>>();
        config.ref
          ..async_io = 0
          ..path = path.toNativeUtf8(allocator: arena).cast()
          ..experimental_features =
              (key == null ? 'attach,index_method' : 'attach,encryption,index_method')
                  .toNativeUtf8(allocator: arena)
                  .cast()
          ..vfs = nullptr
          ..encryption_cipher = (cipher?.toNativeUtf8(allocator: arena) ?? nullptr).cast()
          ..encryption_hexkey = hexKeyPointer.cast()
          ..page_codec = nullptr
          ..open_flags = 0;
        try {
          checkStatus(bindings.turso_database_new(config, databaseOut, errorOut), errorOut);
          database = databaseOut.value;
        } finally {
          // Turso copies configuration during creation; erase our temporary key before release.
          if (hexKey != null) {
            hexKeyPointer
                .cast<Uint8>()
                .asTypedList(hexKey.length + 1)
                .fillRange(0, hexKey.length + 1, 0);
          }
        }
        checkStatus(bindings.turso_database_open(database, errorOut), errorOut);
        final connectionOut = arena<Pointer<bindings.turso_connection_t>>();
        checkStatus(bindings.turso_database_connect(database, connectionOut, errorOut), errorOut);
        connection = connectionOut.value;
        return NativeConnection._(database, connection);
      } on Object {
        if (connection != nullptr) bindings.turso_connection_deinit(connection);
        if (database != nullptr) bindings.turso_database_deinit(database);
        rethrow;
      }
    });
  }

  final Pointer<bindings.turso_database_t> _database;
  final Pointer<bindings.turso_connection_t> _connection;
  var _closed = false;

  /// Buffers one query and releases its statement.
  TursoQueryResult query(String sql, SqlParameters parameters) =>
      NativeStatement.prepare(_connection, sql, parameters).query();

  /// Executes one command and releases its statement.
  BigInt execute(String sql, SqlParameters parameters) =>
      NativeStatement.prepare(_connection, sql, parameters).execute();

  /// Closes once and releases both native handles, even if close fails.
  void close() {
    if (_closed) return;
    _closed = true;
    final errorOut = calloc<Pointer<Char>>();
    try {
      checkStatus(bindings.turso_connection_close(_connection, errorOut), errorOut);
    } finally {
      calloc.free(errorOut);
      bindings.turso_connection_deinit(_connection);
      bindings.turso_database_deinit(_database);
    }
  }
}

String _encodeHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

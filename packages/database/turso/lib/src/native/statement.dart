import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:turso/src/native/error.dart';
import 'package:turso/src/native/turso_bindings_generated.dart' as bindings;
import 'package:turso/src/parameters.dart';
import 'package:turso/src/turso_exception.dart';
import 'package:turso/src/turso_result.dart';

/// Owns a prepared statement until query or execute finalizes it.
final class NativeStatement {
  NativeStatement._(this._statement);

  /// Prepares and binds exactly one statement.
  factory NativeStatement.prepare(
    Pointer<bindings.turso_connection_t> connection,
    String sql,
    SqlParameters parameters,
  ) {
    return using((arena) {
      final sqlPointer = sql.toNativeUtf8(allocator: arena);
      final statementOut = arena<Pointer<bindings.turso_statement_t>>();
      final tailIndex = arena<Size>();
      final errorOut = arena<Pointer<Char>>();
      final status = bindings.turso_connection_prepare_first(
        connection,
        sqlPointer.cast(),
        statementOut,
        tailIndex,
        errorOut,
      );
      checkStatus(status, errorOut);
      final statement = statementOut.value;
      if (statement == nullptr) {
        throw ArgumentError.value(sql, 'sql', 'Must contain one SQL statement.');
      }
      try {
        _rejectTrailingStatement(connection, sql, tailIndex.value);
        _bind(statement, parameters);
      } on Object {
        _finalize(statement);
        rethrow;
      }
      return NativeStatement._(statement);
    });
  }

  final Pointer<bindings.turso_statement_t> _statement;

  /// Buffers the result and finalizes this statement, including on failure.
  TursoQueryResult query() {
    final statement = _statement;
    try {
      final columnCount = bindings.turso_statement_column_count(statement);
      final columns = [
        for (var index = 0; index < columnCount; index++)
          TursoColumn(
            name:
                readOwnedString(bindings.turso_statement_column_name(statement, index)) ??
                (throw const TursoDatabaseException('Upstream omitted a result column name.')),
            declaredType: readOwnedString(
              bindings.turso_statement_column_decltype(statement, index),
            ),
          ),
      ];
      final rows = <TursoRow>[];
      while (true) {
        final status = bindings.turso_statement_step(statement, nullptr);
        if (status == bindings.turso_status_code_t.TURSO_ROW) {
          rows.add(
            TursoRow(columns, [
              for (var index = 0; index < columnCount; index++) _readValue(statement, index),
            ]),
          );
          continue;
        }
        if (status == bindings.turso_status_code_t.TURSO_IO) {
          _runIo(statement);
          continue;
        }
        if (status == bindings.turso_status_code_t.TURSO_DONE) break;
        throwStatus(status, nullptr);
      }
      return TursoQueryResult(columns: columns, rows: rows);
    } finally {
      _finalize(statement);
    }
  }

  /// Executes and finalizes this statement, including on failure.
  BigInt execute() {
    final statement = _statement;
    final rowsChanged = calloc<Uint64>();
    try {
      while (true) {
        final status = bindings.turso_statement_execute(statement, rowsChanged, nullptr);
        if (status == bindings.turso_status_code_t.TURSO_IO) {
          _runIo(statement);
          continue;
        }
        if (status == bindings.turso_status_code_t.TURSO_DONE) {
          return BigInt.from(rowsChanged.value);
        }
        throwStatus(status, nullptr);
      }
    } finally {
      calloc.free(rowsChanged);
      _finalize(statement);
    }
  }

  static void _rejectTrailingStatement(
    Pointer<bindings.turso_connection_t> connection,
    String sql,
    int tailByteIndex,
  ) {
    final sqlBytes = utf8.encode(sql);
    if (tailByteIndex >= sqlBytes.length) return;

    final tail = utf8.decode(sqlBytes.sublist(tailByteIndex));
    using((arena) {
      final tailPointer = tail.toNativeUtf8(allocator: arena);
      final trailingOut = arena<Pointer<bindings.turso_statement_t>>();
      final trailingTail = arena<Size>();
      final errorOut = arena<Pointer<Char>>();
      final status = bindings.turso_connection_prepare_first(
        connection,
        tailPointer.cast(),
        trailingOut,
        trailingTail,
        errorOut,
      );
      checkStatus(status, errorOut);
      if (trailingOut.value != nullptr) {
        _finalize(trailingOut.value);
        throw ArgumentError.value(sql, 'sql', 'Must contain exactly one SQL statement.');
      }
    });
  }

  static void _bind(
    Pointer<bindings.turso_statement_t> statement,
    SqlParameters parameters,
  ) {
    final expectedCount = bindings.turso_statement_parameters_count(statement);
    if (parameters is PositionalParameters) {
      final values = parameters.values;
      if (values.length != expectedCount) {
        throw ArgumentError(
          'Expected $expectedCount positional parameters, got ${values.length}.',
        );
      }
      for (var index = 0; index < values.length; index++) {
        _bindAt(statement, index + 1, values[index]);
      }
      return;
    }

    final supplied = (parameters as NamedParameters).values;
    final expected = <String>[];
    for (var index = 1; index <= expectedCount; index++) {
      final name = readOwnedString(bindings.turso_statement_parameter_name(statement, index));
      if (name == null) {
        throw ArgumentError('Named parameters cannot bind an unnamed SQL placeholder.');
      }
      expected.add(name);
    }
    final expectedNames = expected.toSet();
    if (supplied.length != expectedNames.length || !expectedNames.containsAll(supplied.keys)) {
      throw ArgumentError('Named parameters must exactly match: ${expectedNames.join(', ')}.');
    }
    for (var index = 0; index < expected.length; index++) {
      _bindAt(statement, index + 1, supplied[expected[index]]);
    }
  }

  static void _bindAt(Pointer<bindings.turso_statement_t> statement, int position, Object? value) {
    final status = switch (value) {
      null => bindings.turso_statement_bind_positional_null(statement, position),
      BigInt() => bindings.turso_statement_bind_positional_int(statement, position, value.toInt()),
      double() => bindings.turso_statement_bind_positional_double(statement, position, value),
      String() => _bindBytes(statement, position, utf8.encode(value), text: true),
      Uint8List() => _bindBytes(statement, position, value, text: false),
      _ => throw StateError('An unnormalized parameter reached the native worker.'),
    };
    if (status != bindings.turso_status_code_t.TURSO_OK) throwStatus(status, nullptr);
  }

  static bindings.turso_status_code_t _bindBytes(
    Pointer<bindings.turso_statement_t> statement,
    int position,
    Uint8List bytes, {
    required bool text,
  }) {
    final pointer = calloc<Uint8>(bytes.length);
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      final bind = text
          ? bindings.turso_statement_bind_positional_text
          : bindings.turso_statement_bind_positional_blob;
      return bind(statement, position, pointer.cast(), bytes.length);
    } finally {
      calloc.free(pointer);
    }
  }

  static Object? _readValue(Pointer<bindings.turso_statement_t> statement, int index) {
    final kind = bindings.turso_statement_row_value_kind(statement, index);
    return switch (kind) {
      bindings.turso_type_t.TURSO_TYPE_NULL => null,
      bindings.turso_type_t.TURSO_TYPE_INTEGER => BigInt.from(
        bindings.turso_statement_row_value_int(statement, index),
      ),
      bindings.turso_type_t.TURSO_TYPE_REAL => bindings.turso_statement_row_value_double(
        statement,
        index,
      ),
      bindings.turso_type_t.TURSO_TYPE_TEXT => _readBorrowedBytes(statement, index, text: true),
      bindings.turso_type_t.TURSO_TYPE_BLOB => _readBorrowedBytes(statement, index, text: false),
      _ => throw const TursoDatabaseException('Upstream returned an unknown SQL value type.'),
    };
  }

  static Object _readBorrowedBytes(
    Pointer<bindings.turso_statement_t> statement,
    int index, {
    required bool text,
  }) {
    final length = bindings.turso_statement_row_value_bytes_count(statement, index);
    if (length < 0) throw const TursoDatabaseException('Upstream returned an invalid byte length.');
    final pointer = bindings.turso_statement_row_value_bytes_ptr(statement, index);
    final bytes = Uint8List.fromList(pointer.cast<Uint8>().asTypedList(length));
    return text ? utf8.decode(bytes) : bytes;
  }

  static void _runIo(Pointer<bindings.turso_statement_t> statement) {
    final status = bindings.turso_statement_run_io(statement, nullptr);
    if (status != bindings.turso_status_code_t.TURSO_OK &&
        status != bindings.turso_status_code_t.TURSO_DONE) {
      throwStatus(status, nullptr);
    }
  }

  static void _finalize(Pointer<bindings.turso_statement_t> statement) {
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
}

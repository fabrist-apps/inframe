import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:turso/src/native/turso_bindings_generated.dart' as bindings;
import 'package:turso/src/turso_exception.dart';

/// Copies an upstream-owned string and releases its allocation.
String? readOwnedString(Pointer<Char> pointer) {
  if (pointer == nullptr) return null;
  try {
    return pointer.cast<Utf8>().toDartString();
  } finally {
    bindings.turso_str_deinit(pointer);
  }
}

/// Throws a database error and consumes the optional upstream error string.
Never throwStatus(
  bindings.turso_status_code_t status,
  Pointer<Pointer<Char>> errorOut,
) {
  final message = errorOut == nullptr || errorOut.value == nullptr
      ? 'Upstream Turso failed with status ${status.name}.'
      : readOwnedString(errorOut.value)!;
  if (errorOut != nullptr) errorOut.value = nullptr;
  throw TursoDatabaseException(message, code: status.value);
}

/// Requires successful completion and consumes any upstream failure message.
void checkStatus(bindings.turso_status_code_t status, Pointer<Pointer<Char>> errorOut) {
  if (status != bindings.turso_status_code_t.TURSO_OK) throwStatus(status, errorOut);
}

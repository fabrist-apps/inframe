// Native signatures are named so the platform calls remain reviewable.
// ignore_for_file: avoid_private_typedef_functions

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// An exclusively owned operating-system lock on a persistent sidecar file.
///
/// Ownership belongs to this instance's native file handle. The sidecar file
/// remains after [release] so its existence is never mistaken for ownership.
final class NativeMigrationLock {
  NativeMigrationLock._(this._releaseHandle);

  final void Function() _releaseHandle;
  var _released = false;

  /// Attempts to acquire [path] immediately.
  ///
  /// Returns `null` when another handle owns the lock. Other native failures
  /// throw [NativeMigrationLockException], while unsupported native platforms
  /// throw [UnsupportedError]. Every contended attempt closes its handle before
  /// returning.
  static NativeMigrationLock? tryAcquire(String path) {
    if (Platform.isWindows) return _WindowsMigrationLock.tryAcquire(path);
    if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid || Platform.isIOS) {
      return _UnixMigrationLock.tryAcquire(path);
    }
    throw UnsupportedError(
      'Native migration locks are unavailable on ${Platform.operatingSystem}.',
    );
  }

  /// Releases this lock by closing its native handle.
  ///
  /// Repeated calls have no effect.
  void release() {
    if (_released) return;
    _released = true;
    _releaseHandle();
  }
}

/// A native file or lock operation failed unexpectedly.
final class NativeMigrationLockException implements Exception {
  /// Creates an error for a failed native [operation].
  const NativeMigrationLockException(this.operation, this.path, this.errorCode);

  /// The native operation that failed.
  final String operation;

  /// The sidecar path involved in the operation.
  final String path;

  /// The platform error code captured immediately after the failure.
  final int errorCode;

  @override
  String toString() =>
      'NativeMigrationLockException: $operation failed for "$path" '
      '(error $errorCode).';
}

abstract final class _UnixMigrationLock {
  static const _openReadWrite = 0x0002;
  static const _openCreateLinux = 0x0040;
  static const _openCreateDarwin = 0x0200;
  static const _openCloseOnExecLinux = 0x80000;
  static const _openCloseOnExecDarwin = 0x1000000;
  static const _ownerReadWrite = 0x0180; // 0600
  static const _lockExclusive = 2;
  static const _lockNonBlocking = 4;
  static const _wouldBlockLinux = 11;
  static const _wouldBlockDarwin = 35;

  static final DynamicLibrary _libc = DynamicLibrary.process();
  static final _UnixOpenDart _open = _libc.lookupFunction<_UnixOpenNative, _UnixOpenDart>('open');
  static final _UnixFlockDart _flock = _libc.lookupFunction<_UnixFlockNative, _UnixFlockDart>(
    'flock',
  );
  static final _UnixCloseDart _close = _libc.lookupFunction<_UnixCloseNative, _UnixCloseDart>(
    'close',
  );
  static final _UnixErrnoDart _errnoLocation = _libc
      .lookupFunction<_UnixErrnoNative, _UnixErrnoDart>(
        Platform.isAndroid
            ? '__errno'
            : Platform.isMacOS || Platform.isIOS
            ? '__error'
            : '__errno_location',
      );

  static NativeMigrationLock? tryAcquire(String path) {
    final nativePath = path.toNativeUtf8();
    final isDarwin = Platform.isMacOS || Platform.isIOS;
    final openFlags =
        _openReadWrite |
        (isDarwin ? _openCreateDarwin : _openCreateLinux) |
        (isDarwin ? _openCloseOnExecDarwin : _openCloseOnExecLinux);
    final descriptor = _open(nativePath, openFlags, _ownerReadWrite);
    final openError = descriptor < 0 ? _errno : null;
    calloc.free(nativePath);
    if (descriptor < 0) {
      throw NativeMigrationLockException('open', path, openError!);
    }

    if (_flock(descriptor, _lockExclusive | _lockNonBlocking) == 0) {
      return NativeMigrationLock._(() {
        if (_close(descriptor) != 0) {
          throw NativeMigrationLockException('close', path, _errno);
        }
      });
    }

    final lockError = _errno;
    final closed = _close(descriptor) == 0;
    final closeError = closed ? null : _errno;
    if (!closed) {
      throw NativeMigrationLockException('close', path, closeError!);
    }
    final wouldBlock = isDarwin ? _wouldBlockDarwin : _wouldBlockLinux;
    if (lockError == wouldBlock) return null;
    throw NativeMigrationLockException('flock', path, lockError);
  }

  static int get _errno => _errnoLocation().value;
}

typedef _UnixOpenNative = Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Uint32,)>);
typedef _UnixOpenDart = int Function(Pointer<Utf8>, int, int);
typedef _UnixFlockNative = Int32 Function(Int32, Int32);
typedef _UnixFlockDart = int Function(int, int);
typedef _UnixCloseNative = Int32 Function(Int32);
typedef _UnixCloseDart = int Function(int);
typedef _UnixErrnoNative = Pointer<Int32> Function();
typedef _UnixErrnoDart = Pointer<Int32> Function();

abstract final class _WindowsMigrationLock {
  static const _genericRead = 0x80000000;
  static const _genericWrite = 0x40000000;
  static const _shareRead = 0x00000001;
  static const _shareWrite = 0x00000002;
  static const _shareDelete = 0x00000004;
  static const _openAlways = 4;
  static const _fileAttributeNormal = 0x00000080;
  static const _lockFailImmediately = 0x00000001;
  static const _lockExclusive = 0x00000002;
  static const _lockViolation = 33;

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _CreateFileDart _createFile = _kernel32
      .lookupFunction<_CreateFileNative, _CreateFileDart>('CreateFileW');
  static final _LockFileDart _lockFile = _kernel32.lookupFunction<_LockFileNative, _LockFileDart>(
    'LockFileEx',
  );
  static final _UnlockFileDart _unlockFile = _kernel32
      .lookupFunction<_UnlockFileNative, _UnlockFileDart>('UnlockFileEx');
  static final _CloseHandleDart _closeHandle = _kernel32
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  static final _GetLastErrorDart _getLastError = _kernel32
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  static NativeMigrationLock? tryAcquire(String path) {
    final nativePath = _toUtf16(path);
    final handle = _createFile(
      nativePath,
      _genericRead | _genericWrite,
      _shareRead | _shareWrite | _shareDelete,
      nullptr,
      _openAlways,
      _fileAttributeNormal,
      nullptr,
    );
    final invalidHandle = handle.address == Pointer<Void>.fromAddress(-1).address;
    final openError = invalidHandle ? _getLastError() : null;
    calloc.free(nativePath);
    if (invalidHandle) {
      throw NativeMigrationLockException('CreateFileW', path, openError!);
    }

    // OVERLAPPED is 32 bytes on the package's supported Windows x64 target.
    // Zero offsets lock the first byte, which is enough for cooperative owners.
    final overlapped = calloc<Uint64>(4).cast<Void>();
    if (_lockFile(
          handle,
          _lockExclusive | _lockFailImmediately,
          0,
          1,
          0,
          overlapped,
        ) !=
        0) {
      return NativeMigrationLock._(() {
        final unlocked = _unlockFile(handle, 0, 1, 0, overlapped) != 0;
        final unlockError = unlocked ? null : _getLastError();
        calloc.free(overlapped);
        final closed = _closeHandle(handle) != 0;
        if (!unlocked) {
          throw NativeMigrationLockException(
            'UnlockFileEx',
            path,
            unlockError!,
          );
        }
        if (!closed) {
          throw NativeMigrationLockException(
            'CloseHandle',
            path,
            _getLastError(),
          );
        }
      });
    }

    final lockError = _getLastError();
    calloc.free(overlapped);
    final closed = _closeHandle(handle) != 0;
    final closeError = closed ? null : _getLastError();
    if (!closed) {
      throw NativeMigrationLockException('CloseHandle', path, closeError!);
    }
    if (lockError == _lockViolation) return null;
    throw NativeMigrationLockException('LockFileEx', path, lockError);
  }

  static Pointer<Uint16> _toUtf16(String value) {
    final result = calloc<Uint16>(value.codeUnits.length + 1);
    result.asTypedList(value.codeUnits.length).setAll(0, value.codeUnits);
    return result;
  }
}

typedef _CreateFileNative = Pointer<Void> Function(
  Pointer<Uint16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Uint32,
  Uint32,
  Pointer<Void>,
);
typedef _CreateFileDart = Pointer<Void> Function(
  Pointer<Uint16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
);
typedef _LockFileNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Uint32,
  Uint32,
  Uint32,
  Pointer<Void>,
);
typedef _LockFileDart = int Function(Pointer<Void>, int, int, int, int, Pointer<Void>);
typedef _UnlockFileNative = Int32 Function(Pointer<Void>, Uint32, Uint32, Uint32, Pointer<Void>);
typedef _UnlockFileDart = int Function(Pointer<Void>, int, int, int, Pointer<Void>);
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

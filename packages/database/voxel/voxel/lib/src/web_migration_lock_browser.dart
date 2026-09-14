// Internal Web Locks adapter.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:js_interop';

import 'package:voxel/src/web_migration_lock_core.dart';

VoxelWebLockRequester createVoxelBrowserLockRequester() {
  final manager = _browserLockManager;
  if (manager == null) {
    throw UnsupportedError('Voxel browser migrations require the Web Locks API.');
  }
  return _BrowserLockRequester(manager);
}

@JS('navigator.locks')
external _LockManager? get _browserLockManager;

extension type _LockManager._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(
    String name,
    _LockOptions options,
    JSFunction callback,
  );
}

extension type _LockOptions._(JSObject _) implements JSObject {
  external factory _LockOptions({
    String mode,
    bool ifAvailable,
    bool steal,
    _AbortSignal signal,
  });
}

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();

  external _AbortSignal get signal;

  external void abort();
}

extension type _AbortSignal._(JSObject _) implements JSObject {}

extension type _Lock._(JSObject _) implements JSObject {}

final class _BrowserLockRequester implements VoxelWebLockRequester {
  const _BrowserLockRequester(this._manager);

  final _LockManager _manager;

  @override
  VoxelWebLockAttempt request(String name, {required bool ifAvailable}) {
    return _BrowserLockAttempt.start(_manager, name, ifAvailable: ifAvailable);
  }
}

final class _BrowserLockAttempt implements VoxelWebLockAttempt {
  _BrowserLockAttempt._(this._controller);

  static _BrowserLockAttempt start(
    _LockManager manager,
    String name, {
    required bool ifAvailable,
  }) {
    final controller = _AbortController();
    final attempt = _BrowserLockAttempt._(controller);
    final options = _LockOptions(
      mode: 'exclusive',
      ifAvailable: ifAvailable,
      steal: false,
      signal: controller.signal,
    );
    final request = manager.request(
      name,
      options,
      ((_Lock? lock) => attempt._hold(lock).toJS).toJS,
    );
    attempt._settlement = request.toDart.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!attempt._acquired.isCompleted) {
          attempt._acquired.completeError(error, stackTrace);
        }
      },
    );
    return attempt;
  }

  final _AbortController _controller;
  final Completer<VoxelWebHeldLock?> _acquired = Completer();
  final Completer<void> _release = Completer();
  late final Future<void> _settlement;
  var _cancelled = false;

  @override
  Future<VoxelWebHeldLock?> get acquired => _acquired.future;

  Future<JSAny?> _hold(_Lock? lock) async {
    if (_cancelled || lock == null) {
      if (!_acquired.isCompleted) _acquired.complete(null);
      return null;
    }
    final held = _BrowserHeldLock(_release, () => _settlement);
    _acquired.complete(held);
    await _release.future;
    return null;
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    _controller.abort();
    if (!_release.isCompleted) _release.complete();
    try {
      await _settlement;
    } on Object {
      // An aborted pending request rejects after it has left the lock queue.
    }
  }
}

final class _BrowserHeldLock implements VoxelWebHeldLock {
  _BrowserHeldLock(this._release, this._settlement);

  final Completer<void> _release;
  final Future<void> Function() _settlement;
  Future<void>? _releaseFuture;

  @override
  Future<void> release() => _releaseFuture ??= _releaseAndWait();

  Future<void> _releaseAndWait() async {
    if (!_release.isCompleted) _release.complete();
    await _settlement();
  }
}

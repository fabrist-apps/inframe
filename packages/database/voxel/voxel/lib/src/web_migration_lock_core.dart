// Internal browser migration-lock coordination.
// ignore_for_file: one_member_abstracts, public_member_api_docs

import 'dart:async';
import 'dart:convert';

typedef VoxelWebElapsed = Duration Function();
typedef VoxelWebStartTimeout = VoxelWebTimeout Function(Duration duration);
typedef VoxelWebLockName = String Function(String canonicalPath);

abstract interface class VoxelWebTimeout {
  Future<void> get elapsed;

  void cancel();
}

abstract interface class VoxelWebLockRequester {
  VoxelWebLockAttempt request(String name, {required bool ifAvailable});
}

abstract interface class VoxelWebLockAttempt {
  Future<VoxelWebHeldLock?> get acquired;

  Future<void> cancel();
}

abstract interface class VoxelWebHeldLock {
  Future<void> release();
}

final class VoxelWebMigrationDeadline {
  VoxelWebMigrationDeadline._(this.timeout, this._elapsed, this._startedAt);

  factory VoxelWebMigrationDeadline.start(
    Duration timeout, {
    VoxelWebElapsed? elapsed,
  }) {
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }
    if (elapsed != null) {
      return VoxelWebMigrationDeadline._(timeout, elapsed, elapsed());
    }
    final stopwatch = Stopwatch()..start();
    return VoxelWebMigrationDeadline._(
      timeout,
      () => stopwatch.elapsed,
      Duration.zero,
    );
  }

  final Duration timeout;
  final VoxelWebElapsed _elapsed;
  final Duration _startedAt;
  var _setsStarted = 0;

  bool get isImmediate => timeout == Duration.zero;

  Duration get remaining {
    final value = timeout - (_elapsed() - _startedAt);
    return value.isNegative ? Duration.zero : value;
  }

  bool beginSet() => _setsStarted++ == 0;
}

final class VoxelWebMigrationLease {
  VoxelWebMigrationLease._(this.paths, this._locks);

  final List<String> paths;
  final List<VoxelWebHeldLock> _locks;
  Future<void>? _releaseFuture;

  Future<void> release() => _releaseFuture ??= _releaseAll(_locks);
}

final class VoxelWebMigrationCoordinator {
  VoxelWebMigrationCoordinator({
    required this._requester,
    required this._lockName,
    VoxelWebStartTimeout? startTimeout,
  }) : _startTimeout = startTimeout ?? _TimerWebTimeout.new;

  final VoxelWebLockRequester _requester;
  final VoxelWebLockName _lockName;
  final VoxelWebStartTimeout _startTimeout;

  Future<VoxelWebMigrationLease> acquire(
    Iterable<String> canonicalPaths,
    VoxelWebMigrationDeadline deadline,
  ) async {
    final originalPaths = canonicalPaths.toList(growable: false);
    if (originalPaths.any((path) => path.isEmpty)) {
      throw ArgumentError.value(
        originalPaths,
        'canonicalPaths',
        'must contain only nonempty persistent paths',
      );
    }
    final paths = originalPaths.toSet().toList()..sort();
    if (paths.length != originalPaths.length) {
      throw ArgumentError.value(
        originalPaths,
        'canonicalPaths',
        'contains duplicate persistent paths',
      );
    }

    final isFirstSet = deadline.beginSet();
    if (!isFirstSet && deadline.remaining == Duration.zero) {
      throw TimeoutException(
        'Timed out reacquiring Voxel browser migration coordination.',
        deadline.timeout,
      );
    }

    final locks = <VoxelWebHeldLock>[];
    try {
      for (final path in paths) {
        locks.add(await _acquire(path, deadline));
      }
      return VoxelWebMigrationLease._(
        List.unmodifiable(paths),
        List.unmodifiable(locks),
      );
    } on Object {
      try {
        await _releaseAll(locks);
      } on Object {
        // Preserve the acquisition failure.
      }
      rethrow;
    }
  }

  Future<VoxelWebHeldLock> _acquire(
    String path,
    VoxelWebMigrationDeadline deadline,
  ) async {
    final attempt = _requester.request(
      _lockName(path),
      ifAvailable: deadline.isImmediate,
    );
    if (deadline.isImmediate) {
      final VoxelWebHeldLock? lock;
      try {
        lock = await attempt.acquired;
      } on Object {
        await attempt.cancel();
        rethrow;
      }
      if (lock != null) return lock;
      await attempt.cancel();
      throw TimeoutException(
        'Timed out acquiring Voxel browser migration coordination.',
        deadline.timeout,
      );
    }

    final remaining = deadline.remaining;
    if (remaining == Duration.zero) {
      await attempt.cancel();
      throw TimeoutException(
        'Timed out acquiring Voxel browser migration coordination.',
        deadline.timeout,
      );
    }

    final timeout = _startTimeout(remaining);
    final Object? result;
    try {
      result = await Future.any<Object?>([
        attempt.acquired,
        timeout.elapsed.then<Object?>((_) => _timedOut),
      ]);
    } on Object {
      timeout.cancel();
      await attempt.cancel();
      rethrow;
    }
    if (!identical(result, _timedOut)) {
      timeout.cancel();
      final lock = result as VoxelWebHeldLock?;
      if (lock != null) return lock;
    }
    await attempt.cancel();
    throw TimeoutException(
      'Timed out acquiring Voxel browser migration coordination.',
      deadline.timeout,
    );
  }
}

String voxelWebMigrationLockName(String origin, String canonicalPath) {
  String encode(String value) => base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  return 'voxel:migration:v1:${encode(origin)}:${encode(canonicalPath)}';
}

const _timedOut = Object();

final class _TimerWebTimeout implements VoxelWebTimeout {
  _TimerWebTimeout(Duration duration) {
    _timer = Timer(duration, _completer.complete);
  }

  final Completer<void> _completer = Completer();
  late final Timer _timer;

  @override
  Future<void> get elapsed => _completer.future;

  @override
  void cancel() => _timer.cancel();
}

Future<void> _releaseAll(Iterable<VoxelWebHeldLock> locks) async {
  Object? firstFailure;
  StackTrace? firstStackTrace;
  for (final lock in locks.toList().reversed) {
    try {
      await lock.release();
    } on Object catch (error, stackTrace) {
      firstFailure ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstFailure != null) {
    Error.throwWithStackTrace(firstFailure, firstStackTrace!);
  }
}

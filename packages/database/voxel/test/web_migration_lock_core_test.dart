import 'dart:async';

import 'package:test/test.dart';
import 'package:voxel/src/web_migration_lock_core.dart';

void main() {
  group('VoxelWebMigrationCoordinator', () {
    test('should acquire canonical paths in sorted order and release in reverse', () async {
      final events = <String>[];
      final requester = _FakeRequester(events: events);
      final coordinator = VoxelWebMigrationCoordinator(
        requester: requester,
        lockName: (path) => 'lock:$path',
      );

      final lease = await coordinator.acquire(
        const ['z/database.db', 'a/database.db'],
        VoxelWebMigrationDeadline.start(const Duration(seconds: 1)),
      );
      await lease.release();

      expect(events, [
        'request:lock:a/database.db:false',
        'request:lock:z/database.db:false',
        'release:lock:z/database.db',
        'settled:lock:z/database.db',
        'release:lock:a/database.db',
        'settled:lock:a/database.db',
      ]);
    });

    test('should make one immediate request for a zero deadline', () async {
      final events = <String>[];
      final requester = _FakeRequester(events: events, unavailable: {'lock:b.db'});
      final coordinator = VoxelWebMigrationCoordinator(
        requester: requester,
        lockName: (path) => 'lock:$path',
      );

      await expectLater(
        coordinator.acquire(
          const ['a.db', 'b.db'],
          VoxelWebMigrationDeadline.start(Duration.zero),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(events, [
        'request:lock:a.db:true',
        'request:lock:b.db:true',
        'cancel:lock:b.db',
        'settled:lock:b.db',
        'release:lock:a.db',
        'settled:lock:a.db',
      ]);
    });

    test('should abort a pending request and await settlement before failing', () async {
      var elapsed = Duration.zero;
      final events = <String>[];
      final requester = _FakeRequester(events: events, pending: {'lock:b.db'});
      final deadline = VoxelWebMigrationDeadline.start(
        const Duration(seconds: 5),
        elapsed: () => elapsed,
      );
      var timeoutCount = 0;
      final coordinator = VoxelWebMigrationCoordinator(
        requester: requester,
        lockName: (path) => 'lock:$path',
        startTimeout: (duration) {
          timeoutCount++;
          return _FakeTimeout(
            onElapsed: timeoutCount == 2
                ? () {
                    elapsed += duration;
                    events.add('deadline');
                  }
                : null,
          );
        },
      );

      await expectLater(
        coordinator.acquire(const ['a.db', 'b.db'], deadline),
        throwsA(isA<TimeoutException>()),
      );

      expect(events, [
        'request:lock:a.db:false',
        'request:lock:b.db:false',
        'deadline',
        'cancel:lock:b.db',
        'settled:lock:b.db',
        'release:lock:a.db',
        'settled:lock:a.db',
      ]);
    });

    test('should preserve one deadline across reacquisition', () async {
      var elapsed = Duration.zero;
      final events = <String>[];
      final requester = _FakeRequester(events: events);
      final coordinator = VoxelWebMigrationCoordinator(
        requester: requester,
        lockName: (path) => path,
      );
      final deadline = VoxelWebMigrationDeadline.start(
        const Duration(seconds: 10),
        elapsed: () => elapsed,
      );

      final first = await coordinator.acquire(const ['a.db'], deadline);
      await first.release();
      elapsed = const Duration(seconds: 10);

      await expectLater(
        coordinator.acquire(const ['a.db'], deadline),
        throwsA(isA<TimeoutException>()),
      );
      expect(events, [
        'request:a.db:false',
        'release:a.db',
        'settled:a.db',
      ]);
    });

    test('should not retry a zero-deadline set during reacquisition', () async {
      final requester = _FakeRequester(events: []);
      final coordinator = VoxelWebMigrationCoordinator(
        requester: requester,
        lockName: (path) => path,
      );
      final deadline = VoxelWebMigrationDeadline.start(Duration.zero);

      final first = await coordinator.acquire(const ['a.db'], deadline);
      await first.release();
      await expectLater(
        coordinator.acquire(const ['a.db', 'b.db'], deadline),
        throwsA(isA<TimeoutException>()),
      );

      expect(requester.requestCount, 1);
    });

    test('should reject duplicate canonical paths before requesting locks', () async {
      final requester = _FakeRequester(events: []);
      final coordinator = VoxelWebMigrationCoordinator(
        requester: requester,
        lockName: (path) => path,
      );

      await expectLater(
        coordinator.acquire(
          const ['same.db', 'same.db'],
          VoxelWebMigrationDeadline.start(Duration.zero),
        ),
        throwsArgumentError,
      );
      expect(requester.requestCount, 0);
    });

    test('should reject an empty canonical path before requesting locks', () async {
      final requester = _FakeRequester(events: []);
      final coordinator = VoxelWebMigrationCoordinator(
        requester: requester,
        lockName: (path) => path,
      );

      await expectLater(
        coordinator.acquire(
          const [''],
          VoxelWebMigrationDeadline.start(Duration.zero),
        ),
        throwsArgumentError,
      );
      expect(requester.requestCount, 0);
    });

    test('should namespace lock names by origin and canonical path', () {
      expect(
        voxelWebMigrationLockName('https://example.test', 'apps/data.db'),
        'voxel:migration:v1:aHR0cHM6Ly9leGFtcGxlLnRlc3Q:YXBwcy9kYXRhLmRi',
      );
    });
  });
}

final class _FakeTimeout implements VoxelWebTimeout {
  _FakeTimeout({void Function()? onElapsed}) {
    if (onElapsed != null) {
      onElapsed();
      _completer.complete();
    }
  }

  final Completer<void> _completer = Completer();

  @override
  Future<void> get elapsed => _completer.future;

  @override
  void cancel() {}
}

final class _FakeRequester implements VoxelWebLockRequester {
  _FakeRequester({
    required this.events,
    this.unavailable = const {},
    this.pending = const {},
  });

  final List<String> events;
  final Set<String> unavailable;
  final Set<String> pending;
  int requestCount = 0;

  @override
  VoxelWebLockAttempt request(String name, {required bool ifAvailable}) {
    requestCount++;
    events.add('request:$name:$ifAvailable');
    return _FakeAttempt(
      name,
      events,
      unavailable: unavailable.contains(name),
      pending: pending.contains(name),
    );
  }
}

final class _FakeAttempt implements VoxelWebLockAttempt {
  _FakeAttempt(
    this.name,
    this.events, {
    required bool unavailable,
    required bool pending,
  }) : _acquired = pending
           ? Completer<VoxelWebHeldLock?>().future
           : Future.value(unavailable ? null : _FakeHeldLock(name, events));

  final String name;
  final List<String> events;
  final Future<VoxelWebHeldLock?> _acquired;

  @override
  Future<VoxelWebHeldLock?> get acquired => _acquired;

  @override
  Future<void> cancel() async {
    events.add('cancel:$name');
    events.add('settled:$name');
  }
}

final class _FakeHeldLock implements VoxelWebHeldLock {
  _FakeHeldLock(this.name, this.events);

  final String name;
  final List<String> events;
  Future<void>? _releaseFuture;

  @override
  Future<void> release() => _releaseFuture ??= Future<void>.sync(() {
    events.add('release:$name');
    events.add('settled:$name');
  });
}

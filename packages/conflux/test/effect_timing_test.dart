import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

import 'support/fake_clock.dart';

void main() {
  group('Effect timing', () {
    test('should release a failed clock wait before returning its defect', () async {
      final clock = _FailingClock();

      final exit = await Effect.sleep(Duration.zero).runFutureExit(clock: clock);

      expect((exit as Failed<void, Never>).cause, isA<Defect<Never>>());
      expect(clock.wait.cancellations, 1);
    });

    test('should await failed wait cleanup and preserve both defects', () async {
      final cleanupStarted = Completer<void>();
      final cleanupGate = Completer<void>();
      final cleanupError = StateError('cleanup failed');
      final clock = _FailingClock(
        onCancel: () async {
          cleanupStarted.complete();
          await cleanupGate.future;
          throw cleanupError;
        },
      );
      var finished = false;
      final running = Effect.sleep(Duration.zero).runFutureExit(clock: clock);
      unawaited(running.then((_) => finished = true));

      await cleanupStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      cleanupGate.complete();
      final exit = await running;

      final cause = (exit as Failed<void, Never>).cause as Sequential<Never>;
      expect(cause.causes, hasLength(2));
      expect((cause.causes.first as Defect<Never>).error, same(clock.wait.error));
      expect((cause.causes.last as Defect<Never>).error, same(cleanupError));
      expect(clock.wait.cancellations, 1);
    });

    test('should lazily sleep and remove its wait when interrupted', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      final effect = Effect.sleep(const Duration(seconds: 5));

      expect(clock.activeWaits, 0);
      final fiber = runtime.fork(effect);
      await Future<void>.delayed(Duration.zero);
      expect(clock.activeWaits, 1);

      final exit = await fiber.interrupt('stop');

      expect(exit, isA<Failed<void, Never>>());
      expect((exit as Failed<void, Never>).cause, isA<Interrupted<Never>>());
      expect(clock.activeWaits, 0);
    });

    test('should start a delayed Effect only after the wait', () async {
      final clock = FakeClock();
      var started = false;
      final fiber = Runtime(clock: clock).fork(
        Effect.sync((_) {
          started = true;
          return 42;
        }).delay(const Duration(seconds: 5)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(started, isFalse);
      clock.advance(const Duration(seconds: 5));
      final exit = await fiber.join();

      expect((exit as Succeeded<int, Never>).value, 42);
      expect(started, isTrue);
      expect(clock.activeWaits, 0);
    });

    test('should measure elapsed time monotonically', () async {
      final clock = FakeClock();
      final effect = Effect.sync((_) {
        clock
          ..adjustWall(const Duration(days: 2))
          ..advanceMonotonic(const Duration(seconds: 3));
        return 42;
      }).timed();

      final exit = await Runtime(clock: clock).run(effect);
      final result = (exit as Succeeded<({Duration elapsed, int value}), Never>).value;

      expect(result.value, 42);
      expect(result.elapsed, const Duration(seconds: 3));
    });

    test('should cancel the timeout wait after ordinary completion', () async {
      final clock = FakeClock();
      var fallbackCalls = 0;

      final exit = await Runtime(clock: clock).run(
        Effect.succeed<int, String>(42).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            fallbackCalls += 1;
            return 'timeout';
          },
        ),
      );

      expect((exit as Succeeded<int, String>).value, 42);
      expect(fallbackCalls, 0);
      expect(clock.activeWaits, 0);
    });

    test('should await child cleanup before returning a timeout', () async {
      final clock = FakeClock();
      final started = Completer<void>();
      final pending = Completer<void>();
      final cleanupStarted = Completer<void>();
      final cleanupGate = Completer<void>();
      final runtime = Runtime(clock: clock);
      final fiber = runtime.fork(
        Effect.tryFuture<void, String>(
              () {
                started.complete();
                return pending.future;
              },
              onError: (error, _) => '$error',
            )
            .onCancel(
              Effect.tryFuture<void, Never>(
                () {
                  cleanupStarted.complete();
                  return cleanupGate.future;
                },
                onError: Error.throwWithStackTrace,
              ),
            )
            .timeout(const Duration(seconds: 5), onTimeout: () => 'timeout'),
      );
      await started.future;

      clock.advance(const Duration(seconds: 5));
      await cleanupStarted.future;
      var completed = false;
      unawaited(fiber.join().whenComplete(() => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      cleanupGate.complete();
      final exit = await fiber.join();

      final cause = (exit as Failed<void, String>).cause;
      expect((cause as Expected<String>).error, 'timeout');
      expect(completed, isTrue);
      expect(clock.activeWaits, 0);
    });

    test('should retain cleanup defects after a timeout', () async {
      final clock = FakeClock();
      final started = Completer<void>();
      final pending = Completer<void>();
      final fiber = Runtime(clock: clock).fork(
        Effect.tryFuture<void, String>(
              () {
                started.complete();
                return pending.future;
              },
              onError: (error, _) => '$error',
            )
            .onCancel(
              Effect.sync((_) => throw StateError('cleanup')),
            )
            .timeout(const Duration(seconds: 5), onTimeout: () => 'timeout'),
      );
      await started.future;

      clock.advance(const Duration(seconds: 5));
      final cause = (await fiber.join() as Failed<void, String>).cause;

      expect(cause, isA<Sequential<String>>());
      final failures = (cause as Sequential<String>).causes;
      expect((failures.first as Expected<String>).error, 'timeout');
      expect(failures.last, isA<Defect<String>>());
    });

    test('should prevent delayed work after parent cancellation', () async {
      final clock = FakeClock();
      var started = false;
      final fiber = Runtime(clock: clock).fork(
        Effect.sync((_) => started = true).delay(const Duration(seconds: 5)),
      );
      await Future<void>.delayed(Duration.zero);

      final exit = await fiber.interrupt('parent stopped');
      clock.advance(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);

      expect((exit as Failed<bool, Never>).cause, isA<Interrupted<Never>>());
      expect(started, isFalse);
      expect(clock.activeWaits, 0);
    });

    test('should interrupt timeout children when the parent is cancelled', () async {
      final clock = FakeClock();
      final started = Completer<void>();
      final pending = Completer<void>();
      final fiber = Runtime(clock: clock).fork(
        Effect.tryFuture<void, String>(
          () {
            started.complete();
            return pending.future;
          },
          onError: (error, _) => '$error',
        ).timeout(const Duration(seconds: 5), onTimeout: () => 'timeout'),
      );
      await started.future;

      final exit = await fiber.interrupt('parent stopped');

      expect((exit as Failed<void, String>).cause, isA<Interrupted<String>>());
      expect(clock.activeWaits, 0);
    });

    test('should reject negative timing durations', () {
      expect(
        () => Effect.sleep(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => Effect.succeed<int, String>(1).delay(
          const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
      expect(
        () => Effect.succeed<int, String>(1).timeout(
          const Duration(microseconds: -1),
          onTimeout: () => 'timeout',
        ),
        throwsArgumentError,
      );
    });
  });
}

final class _FailingClock implements Clock {
  _FailingClock({Future<void> Function()? onCancel}) : wait = _FailingWait(onCancel);

  final _FailingWait wait;

  @override
  DateTime wallTime() => DateTime.utc(2026);

  @override
  Duration monotonic() => Duration.zero;

  @override
  CancellableWait sleep(Duration duration) => wait;
}

final class _FailingWait implements CancellableWait {
  _FailingWait(this.onCancel);

  final Future<void> Function()? onCancel;
  final error = StateError('wait failed');
  int cancellations = 0;

  @override
  Future<void> get completed => Future<void>.error(error);

  @override
  Future<void> cancel() async {
    cancellations += 1;
    await onCancel?.call();
  }
}

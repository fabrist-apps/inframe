import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Runtime', () {
    test('should interrupt a forked foreign operation through its hook', () async {
      final pending = Completer<int>();
      final started = Completer<void>();
      var cancelled = false;
      final fiber = Runtime().fork(
        Effect.tryFuture<int, String>(
          () {
            started.complete();
            return pending.future;
          },
          onError: (error, _) => '$error',
          onCancel: () => cancelled = true,
        ),
      );

      await started.future;
      final exit = await fiber.interrupt('test');

      expect(cancelled, isTrue);
      expect((exit as Failed<int, String>).cause, isA<Interrupted<String>>());
    });

    test('should interrupt and await owned roots when closed', () async {
      final pending = Completer<void>();
      final started = Completer<void>();
      var cancellationFinished = false;
      final runtime = Runtime();
      final fiber = runtime.fork(
        Effect.tryFuture<void, Never>(
          () {
            started.complete();
            return pending.future;
          },
          onError: (error, _) => throw StateError('$error'),
          onCancel: () async {
            await Future<void>.delayed(Duration.zero);
            cancellationFinished = true;
          },
        ),
      );

      await started.future;
      await runtime.close();

      expect(cancellationFinished, isTrue);
      final cause = (await fiber.join() as Failed<void, Never>).cause;
      expect(cause, isA<Interrupted<Never>>());
      expect(() => runtime.fork(Effect.succeed<void, Never>(null)), throwsStateError);
    });

    test('should map foreign failures only through the supplied mapper', () async {
      final mapped = await Runtime().run(
        Effect.tryFuture<int, String>(
          () => Future<int>.error(StateError('foreign')),
          onError: (error, _) => error.toString(),
        ),
      );
      final defective = await Runtime().run(
        Effect.tryFuture<int, String>(
          () => Future<int>.error(StateError('foreign')),
          onError: (_, _) => throw StateError('mapper'),
        ),
      );

      expect((mapped as Failed<int, String>).cause, isA<Expected<String>>());
      expect((defective as Failed<int, String>).cause, isA<Defect<String>>());
    });

    test('should observe a late foreign failure after cancellation', () async {
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final started = Completer<void>();
        final pending = Completer<int>();
        final fiber = Runtime().fork(
          Effect.tryFuture<int, String>(
            () {
              started.complete();
              return pending.future;
            },
            onError: (error, _) => '$error',
          ),
        );
        await started.future;
        await fiber.interrupt('test');

        pending.completeError(StateError('late'));
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
    });
  });

  group('SystemClock', () {
    test('should expose wall and monotonic time and cancel waits', () async {
      final clock = SystemClock();
      final beforeWall = clock.wallTime();
      final beforeElapsed = clock.monotonic();
      final wait = clock.sleep(const Duration(days: 1));

      await wait.cancel();
      await wait.completed;

      expect(clock.wallTime().isBefore(beforeWall), isFalse);
      expect(clock.monotonic() >= beforeElapsed, isTrue);
    });

    test('should let a controlled clock remove a cancelled wait', () async {
      final clock = _ControlledClock();
      final beforeWall = clock.wallTime();
      final wait = clock.sleep(const Duration(seconds: 5));

      clock.advance(const Duration(seconds: 2));
      await wait.cancel();

      expect(clock.wallTime(), beforeWall.add(const Duration(seconds: 2)));
      expect(clock.monotonic(), const Duration(seconds: 2));
      expect(clock.activeWaits, 0);
    });
  });
}

final class _ControlledClock implements Clock {
  DateTime _wall = DateTime.utc(2026);
  Duration _monotonic = Duration.zero;
  int activeWaits = 0;

  void advance(Duration duration) {
    _wall = _wall.add(duration);
    _monotonic += duration;
  }

  @override
  DateTime wallTime() => _wall;

  @override
  Duration monotonic() => _monotonic;

  @override
  CancellableWait sleep(Duration duration) {
    activeWaits += 1;
    return _ControlledWait(() => activeWaits -= 1);
  }
}

final class _ControlledWait implements CancellableWait {
  _ControlledWait(this._onCancel);

  final void Function() _onCancel;
  final Completer<void> _completed = Completer<void>();
  bool _cancelled = false;

  @override
  Future<void> get completed => _completed.future;

  @override
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
    _completed.complete();
  }
}

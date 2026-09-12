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
          (_) {
            started.complete();
            return pending.future;
          },
          onError: (error, _, _) => '$error',
          onCancel: (_) => cancelled = true,
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
          (_) {
            started.complete();
            return pending.future;
          },
          onError: (error, _, _) => throw StateError('$error'),
          onCancel: (_) async {
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

    test('should register root ownership before user work begins', () async {
      final started = Completer<void>();
      final pending = Completer<void>();
      late Future<void> closing;
      var cancelled = false;
      late final Runtime runtime;
      runtime = Runtime();
      final fiber = runtime.fork(
        Effect.tryFuture<void, Never>(
          (_) {
            closing = runtime.close();
            started.complete();
            return pending.future;
          },
          onError: (error, _, _) => throw StateError('$error'),
          onCancel: (_) => cancelled = true,
        ),
      );

      await started.future;
      await closing;

      expect(cancelled, isTrue);
      expect((await fiber.join() as Failed<void, Never>).cause, isA<Interrupted<Never>>());
      pending.completeError(StateError('late'));
      await Future<void>.delayed(Duration.zero);
    });

    test('should map foreign failures only through the supplied mapper', () async {
      final mapped = await Runtime().run(
        Effect.tryFuture<int, String>(
          (_) => Future<int>.error(StateError('foreign')),
          onError: (error, _, _) => error.toString(),
        ),
      );
      final defective = await Runtime().run(
        Effect.tryFuture<int, String>(
          (_) => Future<int>.error(StateError('foreign')),
          onError: (_, _, _) => throw StateError('mapper'),
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
            (_) {
              started.complete();
              return pending.future;
            },
            onError: (error, _, _) => '$error',
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
  });
}

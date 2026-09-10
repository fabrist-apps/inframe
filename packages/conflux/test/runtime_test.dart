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

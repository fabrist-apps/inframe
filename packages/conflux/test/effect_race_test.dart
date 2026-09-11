import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect race', () {
    test('should keep completion order after an earlier same-turn failure', () async {
      final gates = List.generate(4, (_) => Completer<int>());
      final starts = List.generate(4, (_) => Completer<void>());
      final running = Effect.race<int, int>([
        for (var index = 0; index < gates.length; index += 1)
          Effect.tryFuture<int, int>(
            () {
              starts[index].complete();
              return gates[index].future;
            },
            onError: (_, _) => index,
          ),
      ]).runFuture();
      await Future.wait(starts.map((start) => start.future));

      gates[0].completeError(StateError('first failed'));
      gates[3].complete(3);
      gates[2].complete(2);
      gates[1].complete(1);

      expect(await running, 3);
    });

    test('should wait for a success after an earlier expected failure', () async {
      final success = Completer<int>();
      final effect = Effect.race<int, String>([
        Effect.fail<int, String>('first failed'),
        Effect.tryFuture<int, String>(
          () => success.future,
          onError: (error, _) => '$error',
        ),
      ]);
      final running = Runtime().run(effect);

      await Future<void>.delayed(Duration.zero);
      success.complete(42);

      final exit = await running;
      expect((exit as Succeeded<int, String>).value, 42);
    });

    test('should retain all failures in input order', () async {
      final first = Completer<int>();
      final second = Completer<int>();
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final running = Runtime().run(
        Effect.race<int, String>([
          Effect.tryFuture<int, String>(
            () {
              firstStarted.complete();
              return first.future;
            },
            onError: (_, _) => 'first',
          ),
          Effect.tryFuture<int, String>(
            () {
              secondStarted.complete();
              return second.future;
            },
            onError: (_, _) => 'second',
          ),
        ]),
      );

      await Future.wait([firstStarted.future, secondStarted.future]);
      second.completeError(StateError('second'));
      await Future<void>.delayed(Duration.zero);
      first.completeError(StateError('first'));

      final cause = (await running as Failed<int, String>).cause;
      expect(cause, isA<Parallel<String>>());
      final causes = (cause as Parallel<String>).causes;
      expect((causes[0] as Expected<String>).error, 'first');
      expect((causes[1] as Expected<String>).error, 'second');
    });

    test('should await interrupted loser cleanup before succeeding', () async {
      final loserStarted = Completer<void>();
      final loserPending = Completer<int>();
      var cleaned = false;
      final running = Runtime().run(
        Effect.race<int, String>([
          Effect.tryFuture<int, String>(
            () async {
              await loserStarted.future;
              return 42;
            },
            onError: (error, _) => '$error',
          ),
          Effect.tryFuture<int, String>(
            () {
              loserStarted.complete();
              return loserPending.future;
            },
            onError: (error, _) => '$error',
            onCancel: () async {
              await Future<void>.delayed(Duration.zero);
              cleaned = true;
            },
          ),
        ]),
      );

      final exit = await running;

      expect((exit as Succeeded<int, String>).value, 42);
      expect(cleaned, isTrue);
    });

    test('should surface a loser cleanup defect after a winning value', () async {
      final loserStarted = Completer<void>();
      final loserPending = Completer<int>();
      final running = Runtime().run(
        Effect.race<int, String>([
          Effect.tryFuture<int, String>(
            () async {
              await loserStarted.future;
              return 42;
            },
            onError: (error, _) => '$error',
          ),
          Effect.tryFuture<int, String>(
            () {
              loserStarted.complete();
              return loserPending.future;
            },
            onError: (error, _) => '$error',
            onCancel: () => throw StateError('cleanup'),
          ),
        ]),
      );

      final cause = (await running as Failed<int, String>).cause;

      expect(cause, isA<Defect<String>>());
    });

    test('should interrupt every branch when its parent is cancelled', () async {
      final starts = [Completer<void>(), Completer<void>()];
      final pending = [Completer<int>(), Completer<int>()];
      var cancellations = 0;
      final runtime = Runtime();
      final fiber = runtime.fork(
        Effect.race<int, String>([
          for (var index = 0; index < 2; index += 1)
            Effect.tryFuture<int, String>(
              () {
                starts[index].complete();
                return pending[index].future;
              },
              onError: (error, _) => '$error',
              onCancel: () => cancellations += 1,
            ),
        ]),
      );
      await Future.wait(starts.map((started) => started.future));

      final exit = await fiber.interrupt('parent');

      expect(cancellations, 2);
      expect((exit as Failed<int, String>).cause, isA<Parallel<String>>());
    });

    test('should reject an empty race when the effect runs', () async {
      final effect = Effect.race<int, Never>(const []);

      final exit = await Runtime().run(effect);

      expect((exit as Failed<int, Never>).cause, isA<Defect<Never>>());
    });
  });
}

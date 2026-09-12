import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect collection', () {
    test('should yield so event-loop cancellation can stop immediate work', () async {
      var started = 0;
      final runtime = Runtime();
      final fiber = runtime.fork(
        Effect.forEach<int, int, Never>(
          List.generate(10000, (index) => index),
          (index, _) => Effect.sync((_) {
            started += 1;
            return index;
          }),
        ),
      );
      Timer.run(() => unawaited(fiber.interrupt('stop')));

      final exit = await fiber.join();

      expect(exit, isA<Failed<List<int>, Never>>());
      expect(started, lessThan(10000));
      await runtime.close();
    });

    test('should run sequentially by default and preserve input order', () async {
      final events = <String>[];
      final effect = Effect.forEach<int, int, Never>([1, 2, 3], (value, _) {
        return Effect.sync((_) {
          events.add('start$value');
          return value;
        });
      });

      final exit = await Runtime().run(effect);
      final values = (exit as Succeeded<List<int>, Never>).value;

      expect(values, [1, 2, 3]);
      expect(events, ['start1', 'start2', 'start3']);
      expect(() => values.add(4), throwsUnsupportedError);
    });

    test('should bound active work and collect nullable values in source order', () async {
      var active = 0;
      var maximumActive = 0;
      final gates = List.generate(4, (_) => Completer<void>());
      final started = List.generate(4, (_) => Completer<void>());
      final effect = Effect.forEach<int, int?, String>(
        [0, 1, 2, 3],
        (index, _) => Effect.tryFuture<int?, String>(
          (_) async {
            active += 1;
            maximumActive = active > maximumActive ? active : maximumActive;
            started[index].complete();
            await gates[index].future;
            active -= 1;
            return index == 1 ? null : index;
          },
          onError: (error, _, _) => '$error',
        ),
        concurrency: 2,
      );
      final fiber = Runtime().fork(effect);

      await Future.wait([started[0].future, started[1].future]);
      expect(active, 2);
      gates[1].complete();
      await started[2].future;
      gates[0].complete();
      await started[3].future;
      gates[2].complete();
      gates[3].complete();

      final values = (await fiber.join() as Succeeded<List<int?>, String>).value;
      expect(values, [0, null, 2, 3]);
      expect(maximumActive, 2);
    });

    test('should interrupt and await siblings after expected failure', () async {
      final siblingStarted = Completer<void>();
      final siblingPending = Completer<int>();
      var siblingCleaned = false;
      final effect = Effect.all<int, String>(
        [
          Effect.tryFuture<int, String>(
            (_) async {
              await siblingStarted.future;
              throw StateError('failed');
            },
            onError: (_, _, _) => 'failed',
          ),
          Effect.tryFuture<int, String>(
            (_) {
              siblingStarted.complete();
              return siblingPending.future;
            },
            onError: (error, _, _) => '$error',
            onCancel: (_) async {
              await Future<void>.delayed(Duration.zero);
              siblingCleaned = true;
            },
          ),
        ],
        concurrency: 2,
      );

      final exit = await Runtime().run(effect);

      expect((exit as Failed<List<int>, String>).cause, isA<Expected<String>>());
      expect(siblingCleaned, isTrue);
    });

    test('should preserve sibling cleanup defects after the failure', () async {
      final siblingStarted = Completer<void>();
      final siblingPending = Completer<int>();
      final effect = Effect.all<int, String>(
        [
          Effect.tryFuture<int, String>(
            (_) async {
              await siblingStarted.future;
              throw StateError('failed');
            },
            onError: (_, _, _) => 'failed',
          ),
          Effect.tryFuture<int, String>(
            (_) {
              siblingStarted.complete();
              return siblingPending.future;
            },
            onError: (error, _, _) => '$error',
            onCancel: (_) => throw StateError('cleanup'),
          ),
        ],
        concurrency: 2,
      );

      final exit = await Runtime().run(effect);
      final cause = (exit as Failed<List<int>, String>).cause;

      expect(cause, isA<Sequential<String>>());
      final causes = (cause as Sequential<String>).causes;
      expect(causes[0], isA<Expected<String>>());
      expect(causes[1], isA<Defect<String>>());
    });

    test('should handle empty input and reject non-positive concurrency', () async {
      final exit = await Runtime().run(Effect.all<int, Never>(const []));

      expect((exit as Succeeded<List<int>, Never>).value, isEmpty);
      expect(
        () => Effect.all<int, Never>(const [], concurrency: 0),
        throwsArgumentError,
      );
    });
  });
}

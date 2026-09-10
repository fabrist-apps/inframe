import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect collection', () {
    test('should run sequentially by default and preserve input order', () async {
      final events = <String>[];
      final effect = Effect.forEach<int, int, Never>([1, 2, 3], (value) {
        return Effect.sync(() {
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

    test('should keep active work within the configured bound', () async {
      var active = 0;
      var maximumActive = 0;
      final gates = List.generate(4, (_) => Completer<void>());
      final started = StreamController<int>.broadcast();
      addTearDown(started.close);
      final effect = Effect.forEach<int, int, String>(
        [0, 1, 2, 3],
        (index) => Effect.tryFuture<int, String>(
          () async {
            active += 1;
            maximumActive = active > maximumActive ? active : maximumActive;
            started.add(index);
            await gates[index].future;
            active -= 1;
            return index;
          },
          onError: (error, _) => '$error',
        ),
        concurrency: 2,
      );
      final fiber = Runtime().fork(effect);

      await started.stream.firstWhere((index) => index == 1);
      expect(active, 2);
      gates[1].complete();
      await started.stream.firstWhere((index) => index == 2);
      gates[0].complete();
      await started.stream.firstWhere((index) => index == 3);
      gates[2].complete();
      gates[3].complete();

      final values = (await fiber.join() as Succeeded<List<int>, String>).value;
      expect(values, [0, 1, 2, 3]);
      expect(maximumActive, 2);
    });

    test('should interrupt and await siblings after expected failure', () async {
      final siblingStarted = Completer<void>();
      final siblingPending = Completer<int>();
      var siblingCleaned = false;
      final effect = Effect.all<int, String>(
        [
          Effect.tryFuture<int, String>(
            () async {
              await siblingStarted.future;
              throw StateError('failed');
            },
            onError: (_, _) => 'failed',
          ),
          Effect.tryFuture<int, String>(
            () {
              siblingStarted.complete();
              return siblingPending.future;
            },
            onError: (error, _) => '$error',
            onCancel: () async {
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
            () async {
              await siblingStarted.future;
              throw StateError('failed');
            },
            onError: (_, _) => 'failed',
          ),
          Effect.tryFuture<int, String>(
            () {
              siblingStarted.complete();
              return siblingPending.future;
            },
            onError: (error, _) => '$error',
            onCancel: () => throw StateError('cleanup'),
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

import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:test/test.dart';

void main() {
  group('Flow sharing', () {
    test(
      'should share one connection and retain replay until the last subscriber leaves',
      () async {
        var connections = 0;
        final listening = Completer<void>();
        final upstreamFinished = Completer<void>();
        final controller = StreamController<int>(sync: true);
        addTearDown(controller.close);
        final source = Flow.fromStream<int, String>(
          (_) {
            connections += 1;
            return controller.stream;
          },
          onError: (error, stackTrace, _) => '$error',
        ).onExit((_, _) => Effect.sync(upstreamFinished.complete));
        final shared = source.share(capacity: 3, replay: 2);
        final releaseFirst = Completer<void>();
        final firstValues = <int>[];
        final secondValues = <int>[];
        final first = shared.subscribe((value, _) {
          firstValues.add(value);
          if (value != 1) return Effect.succeed(null);
          return Effect.tryFuture<void, String>(
            (_) {
              if (!listening.isCompleted) listening.complete();
              return releaseFirst.future;
            },
            onError: (error, stackTrace, _) => '$error',
          );
        });
        final second = shared.subscribe((value, _) {
          secondValues.add(value);
          return Effect.succeed(null);
        });

        await _flushMicrotasks();
        expect(connections, 1);
        controller
          ..add(1)
          ..add(2)
          ..add(3);
        await listening.future;
        await controller.close();
        await upstreamFinished.future;
        expect(await second.completion, isA<Succeeded<void, String>>());

        expect(await shared.runCollect().runFuture(), [2, 3]);
        expect(connections, 1);

        releaseFirst.complete();
        expect(await first.completion, isA<Succeeded<void, String>>());
        expect(firstValues, [1, 2, 3]);
        expect(secondValues, [1, 2, 3]);
      },
    );

    test('should retain replay followed by the same complete failure cause', () async {
      final failure = Sequential<String>([
        const Expected('failed'),
        Defect(StateError('defect'), StackTrace.current),
      ]);
      final upstreamFinished = Completer<void>();
      final releaseFirst = Completer<void>();
      final firstBlocked = Completer<void>();
      var connections = 0;
      final shared = Flow.defer<int, String>((_) {
        connections += 1;
        return Flow.fromIterable([1, 2])
            .widenError<String>()
            .concat(Effect.failCause<int, String>(failure).asFlow());
      }).onExit((_, _) => Effect.sync(upstreamFinished.complete)).share(replay: 1);
      final first = shared.subscribe((value, _) {
        if (value != 1) return Effect.succeed(null);
        return Effect.tryFuture<void, String>(
          (_) {
            firstBlocked.complete();
            return releaseFirst.future;
          },
          onError: (error, stackTrace, _) => '$error',
        );
      });

      await firstBlocked.future;
      await upstreamFinished.future;
      await _flushMicrotasks();
      final lateValues = <int>[];
      final late = shared.subscribe((value, _) {
        lateValues.add(value);
        return Effect.succeed(null);
      });
      final lateExit = await late.completion;

      expect(lateValues, [2]);
      expect(lateExit, isA<Failed<void, String>>());
      expect((lateExit as Failed<void, String>).cause, same(failure));
      expect(connections, 1);

      releaseFirst.complete();
      expect(await first.completion, isA<Failed<void, String>>());
    });

    test('should retain terminal completion without replay while a subscriber drains', () async {
      final releaseFirst = Completer<void>();
      final firstBlocked = Completer<void>();
      final upstreamFinished = Completer<void>();
      var connections = 0;
      final shared = Flow.defer<int, Never>((_) {
        connections += 1;
        return Flow.succeed(1);
      }).onExit((_, _) => Effect.sync(upstreamFinished.complete)).share();
      final first = shared.subscribe((_, _) {
        return Effect.tryFuture<void, Never>(
          (_) {
            firstBlocked.complete();
            return releaseFirst.future;
          },
          onError: (error, stackTrace, _) => _impossibleFutureError(error, stackTrace),
        );
      });

      await firstBlocked.future;
      await upstreamFinished.future;
      await _flushMicrotasks();
      expect(await shared.runCollect().runFuture(), isEmpty);
      expect(connections, 1);

      releaseFirst.complete();
      expect(await first.completion, isA<Succeeded<void, Never>>());
    });

    test('should clear replay and reconnect after the final subscriber detaches', () async {
      var connections = 0;
      final shared = Flow.defer<int, Never>((_) {
        connections += 1;
        return Flow.succeed(connections);
      }).share(replay: 1);

      expect(await shared.runCollect().runFuture(), [1]);
      expect(await shared.runCollect().runFuture(), [2]);
      expect(connections, 2);
    });

    test('should wait for previous cleanup before reconnecting', () async {
      var connections = 0;
      final firstStarted = Completer<void>();
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final pending = Completer<int>();
      final shared = Flow.defer<int, String>((_) {
        connections += 1;
        if (connections > 1) return Flow.succeed(connections);
        return Effect.tryFuture<int, String>(
          (_) {
            firstStarted.complete();
            return pending.future;
          },
          onError: (error, stackTrace, _) => '$error',
          onCancel: (_) async {
            cleanupStarted.complete();
            await releaseCleanup.future;
          },
        ).asFlow();
      }).share();
      final first = shared.subscribe((_, _) => Effect.succeed(null));

      await firstStarted.future;
      final cancelled = first.cancel('reset');
      await cleanupStarted.future;
      final next = shared.runCollect().runFuture();
      await _flushMicrotasks();
      expect(connections, 1);

      releaseCleanup.complete();
      await cancelled;
      expect(await next, [2]);
      expect(connections, 2);
    });

    test('should cancel an attachment waiting for previous cleanup', () async {
      var connections = 0;
      final firstStarted = Completer<void>();
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final pending = Completer<int>();
      final shared = Flow.defer<int, String>((_) {
        connections += 1;
        return Effect.tryFuture<int, String>(
          (_) {
            firstStarted.complete();
            return pending.future;
          },
          onError: (error, stackTrace, _) => '$error',
          onCancel: (_) async {
            cleanupStarted.complete();
            await releaseCleanup.future;
          },
        ).asFlow();
      }).share();
      final first = shared.subscribe((_, _) => Effect.succeed(null));

      await firstStarted.future;
      final firstCancellation = first.cancel('disconnect');
      await cleanupStarted.future;
      final waiting = shared.subscribe((_, _) => Effect.succeed(null));
      await _flushMicrotasks();
      final waitingCancellation = waiting.cancel('stop waiting');
      var cancelled = false;
      unawaited(waitingCancellation.then((_) => cancelled = true));
      await _flushMicrotasks();

      expect(cancelled, isTrue);
      expect(
        await waitingCancellation,
        isA<Failed<void, String>>(),
      );
      expect(connections, 1);

      releaseCleanup.complete();
      await firstCancellation;
    });

    test('should bound subscriber read-ahead under backpressure', () async {
      var pulled = 0;
      final consumerStarted = Completer<void>();
      final releaseConsumer = Completer<void>();
      final source = Flow.fromIterable(List.generate(100, (index) => index))
          .widenError<String>()
          .tap(
            (_, _) =>
                Effect.sync((_) => pulled += 1)
                    .mapError((value, _) => _widenNever(value! as Never)),
          )
          .share(capacity: 1, replay: 2);
      final subscription = source.subscribe((_, _) {
        return Effect.tryFuture<void, String>(
          (_) {
            if (!consumerStarted.isCompleted) consumerStarted.complete();
            return releaseConsumer.future;
          },
          onError: (error, stackTrace, _) => '$error',
        );
      });

      await consumerStarted.future;
      await _flushMicrotasks();
      expect(pulled, lessThanOrEqualTo(3));

      releaseConsumer.complete();
      expect(await subscription.completion, isA<Succeeded<void, String>>());
      expect(pulled, 100);
    });

    test('should validate sharing configuration eagerly', () {
      final source = Flow.succeed<int, String>(1);

      expect(() => source.share(capacity: 0), throwsArgumentError);
      expect(() => source.share(replay: -1), throwsArgumentError);
      expect(
        () => source.share(overflow: FlowOverflowPolicy.fail),
        throwsArgumentError,
      );
    });
  });
}

Future<void> _flushMicrotasks() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _widenNever(Never error) => error;

Never _impossibleFutureError(Object error, StackTrace stackTrace) {
  throw StateError('Unexpected future failure: $error');
}

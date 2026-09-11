import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:test/test.dart';

void main() {
  group('Flow switching', () {
    test('should await old cleanup and keep only the latest pending switch', () async {
      final listening = Completer<void>();
      final outer = StreamController<int>(sync: true)..onListen = listening.complete;
      addTearDown(outer.close);
      final oldResult = Completer<int>();
      final cleanupStarted = Completer<void>();
      final finishCleanup = Completer<void>();
      final replacementStarted = Completer<void>();
      final mapped = <int>[];
      final flow =
          Flow.fromStream<int, String>(
            () => outer.stream,
            onError: (error, stackTrace) => '$error',
          ).switchMap((value) {
            mapped.add(value);
            if (value == 0) {
              return Effect.tryFuture<int, String>(
                () => oldResult.future,
                onError: (error, stackTrace) => '$error',
                onCancel: () async {
                  cleanupStarted.complete();
                  await finishCleanup.future;
                },
              ).asFlow();
            }
            replacementStarted.complete();
            return Flow.succeed(value * 10);
          });

      final result = flow.runCollect().runFuture();
      await listening.future;
      outer.add(0);
      await Future<void>.delayed(Duration.zero);
      outer.add(1);
      await cleanupStarted.future;
      outer.add(2);
      expect(mapped, [0]);

      finishCleanup.complete();
      await replacementStarted.future;
      await outer.close();

      expect(await result, [20]);
      expect(mapped, [0, 2]);
    });

    test('should suppress values buffered by a replaced inner', () async {
      final listening = Completer<void>();
      final outer = StreamController<int>(sync: true)..onListen = listening.complete;
      addTearDown(outer.close);
      final consumingFirst = Completer<void>();
      final releaseFirst = Completer<void>();
      final replacementStarted = Completer<void>();
      final consumed = <int>[];
      final subscription =
          Flow.fromStream<int, String>(
                () => outer.stream,
                onError: (error, stackTrace) => '$error',
              )
              .switchMap(
                (value) {
                  if (value == 0) return Flow.fromIterable([0, 1, 2]).widenError();
                  replacementStarted.complete();
                  return Flow.succeed(value * 10);
                },
                capacity: 4,
              )
              .subscribe((value) {
                consumed.add(value);
                if (value != 0) return Effect.succeed(null);
                return Effect.tryFuture<void, String>(
                  () {
                    consumingFirst.complete();
                    return releaseFirst.future;
                  },
                  onError: (error, stackTrace) => '$error',
                );
              });

      await listening.future;
      outer.add(0);
      await consumingFirst.future;
      outer.add(1);
      await replacementStarted.future;
      releaseFirst.complete();
      await outer.close();

      expect(await subscription.completion, isA<Succeeded<void, String>>());
      expect(consumed, [0, 10]);
    });

    test('should release outer and inner work on downstream cancellation', () async {
      final listening = Completer<void>();
      final outerCancelled = Completer<void>();
      final innerStarted = Completer<void>();
      final innerCancelled = Completer<void>();
      final pending = Completer<int>();
      final outer = StreamController<int>(
        sync: true,
        onListen: listening.complete,
        onCancel: outerCancelled.complete,
      );
      addTearDown(outer.close);
      final subscription =
          Flow.fromStream<int, String>(
                () => outer.stream,
                onError: (error, stackTrace) => '$error',
              )
              .switchMap(
                (_) => Effect.tryFuture<int, String>(
                  () {
                    innerStarted.complete();
                    return pending.future;
                  },
                  onError: (error, stackTrace) => '$error',
                  onCancel: innerCancelled.complete,
                ).asFlow(),
              )
              .subscribe((_) => Effect.succeed(null));

      await listening.future;
      outer.add(1);
      await innerStarted.future;
      expect(await subscription.cancel('stop'), isA<Failed<void, String>>());

      expect(outerCancelled.isCompleted, isTrue);
      expect(innerCancelled.isCompleted, isTrue);
    });

    test('should ignore exhaust triggers without invoking their mapper', () async {
      final listening = Completer<void>();
      final outer = StreamController<int>(sync: true)..onListen = listening.complete;
      addTearDown(outer.close);
      final firstResult = Completer<int>();
      final firstFinished = Completer<void>();
      final thirdStarted = Completer<void>();
      final mapped = <int>[];
      final flow =
          Flow.fromStream<int, String>(
            () => outer.stream,
            onError: (error, stackTrace) => '$error',
          ).exhaustMap((value) {
            mapped.add(value);
            if (value == 1) {
              return Effect.tryFuture<int, String>(
                () => firstResult.future,
                onError: (error, stackTrace) => '$error',
              ).asFlow().onExit((_) => Effect.sync(firstFinished.complete));
            }
            thirdStarted.complete();
            return Flow.succeed(value * 10);
          });

      final result = flow.runCollect().runFuture();
      await listening.future;
      outer
        ..add(1)
        ..add(2);
      await Future<void>.delayed(Duration.zero);
      expect(mapped, [1]);

      firstResult.complete(10);
      await firstFinished.future;
      await Future<void>.delayed(Duration.zero);
      outer.add(3);
      await thirdStarted.future;
      await outer.close();

      expect(await result, [10, 30]);
      expect(mapped, [1, 3]);
    });

    test('should await outer cleanup and retain its defect after inner failure', () async {
      final listening = Completer<void>();
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final outer = StreamController<int>(
        sync: true,
        onListen: listening.complete,
        onCancel: () async {
          cleanupStarted.complete();
          await releaseCleanup.future;
          throw StateError('outer cleanup failed');
        },
      );
      addTearDown(outer.close);
      final result = Flow.fromStream<int, String>(
        () => outer.stream,
        onError: (error, stackTrace) => '$error',
      ).exhaustMap((_) => Flow.fail<int, String>('inner failed')).runDrain().runFutureExit();

      await listening.future;
      outer.add(1);
      await cleanupStarted.future;
      var completed = false;
      unawaited(result.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      releaseCleanup.complete();
      final exit = await result;
      expect(exit, isA<Failed<void, String>>());
      final cause = (exit as Failed<void, String>).cause;
      expect(cause.expectedErrors, ['inner failed']);
      expect(cause.containsFatal, isTrue);
    });
  });
}

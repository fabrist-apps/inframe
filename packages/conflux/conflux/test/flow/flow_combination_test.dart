import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Flow combination', () {
    test('should zip values by position and stop at the shortest source', () async {
      final values = await Flow.zip([
        Flow.fromIterable([1, 2]),
        Flow.fromIterable([10, 20, 30]),
      ]).runCollect().runFuture();

      expect(values, [
        [1, 10],
        [2, 20],
      ]);
      expect(() => values.first.add(99), throwsUnsupportedError);
    });

    test('should stop a pending zip sibling when another source is empty', () async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final pending = Completer<int>();
      final slow = Effect.tryFuture<int, String>(
        (_) {
          started.complete();
          return pending.future;
        },
        onError: (error, stackTrace, _) => '$error',
        onCancel: cancelled.complete,
      ).asFlow();
      final result = Flow.zip<int, String>([
        Flow.empty(),
        slow,
      ]).runCollect().runFuture();

      await started.future;
      expect(await result, isEmpty);
      expect(cancelled.isCompleted, isTrue);
    });

    test('should combine latest nullable values after every first value', () async {
      final leftListening = Completer<void>();
      final rightListening = Completer<void>();
      final left = StreamController<int?>(sync: true)..onListen = leftListening.complete;
      final right = StreamController<int?>(sync: true)..onListen = rightListening.complete;
      addTearDown(left.close);
      addTearDown(right.close);
      final result = Flow.combineLatest<int?, String>([
        Flow.fromStream(
          (_) => left.stream,
          onError: (error, stackTrace, _) => '$error',
        ),
        Flow.fromStream(
          (_) => right.stream,
          onError: (error, stackTrace, _) => '$error',
        ),
      ]).runCollect().runFuture();

      await Future.wait([leftListening.future, rightListening.future]);
      left.add(null);
      right.add(1);
      left.add(2);
      await right.close();
      left.add(3);
      await left.close();

      final values = await result;
      expect(values, [
        [null, 1],
        [2, 1],
        [3, 1],
      ]);
      expect(() => values.first.add(4), throwsUnsupportedError);
    });

    test('should complete combineLatest when a source ends without a value', () async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final pending = Completer<int>();
      final slow = Effect.tryFuture<int, String>(
        (_) {
          started.complete();
          return pending.future;
        },
        onError: (error, stackTrace, _) => '$error',
        onCancel: cancelled.complete,
      ).asFlow();
      final result = Flow.combineLatest<int, String>([
        Flow.empty(),
        slow,
      ]).runCollect().runFuture();

      await started.future;
      expect(await result, isEmpty);
      expect(cancelled.isCompleted, isTrue);
    });

    test('should emit withLatestFrom only on ready primary triggers', () async {
      final request = ContextKey<String>('request');
      final owner = Context().withBinding(request.bind('owner'));
      final contexts = <String>[];
      final primaryListening = Completer<void>();
      final secondaryListening = Completer<void>();
      final secondaryCancelled = Completer<void>();
      final secondLatestObserved = Completer<void>();
      final primary = StreamController<int>(sync: true)..onListen = primaryListening.complete;
      final secondary = StreamController<int>(
        sync: true,
        onListen: secondaryListening.complete,
        onCancel: secondaryCancelled.complete,
      );
      addTearDown(primary.close);
      addTearDown(secondary.close);
      final result =
          Flow.fromStream<int, String>(
                (_) => primary.stream,
                onError: (error, stackTrace, _) => '$error',
              )
              .withLatestFrom(
                Flow.fromStream(
                  (_) => secondary.stream,
                  onError: (error, stackTrace, _) => '$error',
                ).tap(
                  (value, _) => Effect.sync((_) {
                    if (value == 11) secondLatestObserved.complete();
                  }).mapError<String>((value, _) => _widenNever(value! as Never)),
                ),
                (trigger, latest, context) {
                  contexts.add(context.require(request));
                  return trigger + latest;
                },
              )
              .withContext(owner)
              .runCollect()
              .runFuture();

      await Future.wait([primaryListening.future, secondaryListening.future]);
      primary.add(1);
      secondary
        ..add(10)
        ..add(11);
      await secondLatestObserved.future;
      primary.add(2);
      await primary.close();

      expect(await result, [13]);
      expect(contexts, ['owner']);
      expect(secondaryCancelled.isCompleted, isTrue);
    });

    test('should retain primary completion outside every overflow buffer', () async {
      for (final overflow in FlowOverflowPolicy.values) {
        final primaryListening = Completer<void>();
        final secondaryListening = Completer<void>();
        final secondaryCancelled = Completer<void>();
        final consumerStarted = Completer<void>();
        final releaseConsumer = Completer<void>();
        final primary = StreamController<int>(sync: true)..onListen = primaryListening.complete;
        final secondary = StreamController<int>(
          sync: true,
          onListen: secondaryListening.complete,
          onCancel: secondaryCancelled.complete,
        );
        final values = <int>[];
        final subscription =
            Flow.fromStream<int, String>(
                  (_) => primary.stream,
                  onError: (error, stackTrace, _) => '$error',
                )
                .withLatestFrom(
                  Flow.fromStream(
                    (_) => secondary.stream,
                    onError: (error, stackTrace, _) => '$error',
                  ),
                  (trigger, latest, _) => trigger + latest,
                  capacity: 1,
                  overflow: overflow,
                  onOverflow: (_, _) => 'overflow',
                )
                .subscribe((value, _) {
                  values.add(value);
                  if (values.length > 1) return Effect.succeed(null);
                  return Effect.tryFuture<void, String>(
                    (_) {
                      consumerStarted.complete();
                      return releaseConsumer.future;
                    },
                    onError: (error, stackTrace, _) => '$error',
                  );
                });

        await Future.wait([
          primaryListening.future,
          secondaryListening.future,
        ]);
        secondary.add(10);
        await _flushMicrotasks();
        primary.add(1);
        await consumerStarted.future;
        primary.add(2);
        await primary.close();
        await _flushMicrotasks();
        releaseConsumer.complete();

        expect(
          await subscription.completion,
          isA<Succeeded<void, String>>(),
          reason: '$overflow',
        );
        expect(values, [11, 12], reason: '$overflow');
        expect(secondaryCancelled.isCompleted, isTrue, reason: '$overflow');
        await secondary.close();
      }
    });
  });
}

Future<void> _flushMicrotasks() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _widenNever(Never error) => error;

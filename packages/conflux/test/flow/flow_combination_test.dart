import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
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
        () {
          started.complete();
          return pending.future;
        },
        onError: (error, stackTrace) => '$error',
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
          () => left.stream,
          onError: (error, stackTrace) => '$error',
        ),
        Flow.fromStream(
          () => right.stream,
          onError: (error, stackTrace) => '$error',
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
        () {
          started.complete();
          return pending.future;
        },
        onError: (error, stackTrace) => '$error',
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
                () => primary.stream,
                onError: (error, stackTrace) => '$error',
              )
              .withLatestFrom(
                Flow.fromStream(
                  () => secondary.stream,
                  onError: (error, stackTrace) => '$error',
                ).tap(
                  (value) => Effect.sync(() {
                    if (value == 11) secondLatestObserved.complete();
                  }).mapError<String>(_widenNever),
                ),
                (trigger, latest) => trigger + latest,
              )
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
      expect(secondaryCancelled.isCompleted, isTrue);
    });
  });
}

String _widenNever(Never error) => error;

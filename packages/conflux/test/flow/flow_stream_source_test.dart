import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:test/test.dart';

void main() {
  group('Flow.fromStream', () {
    test('should invoke a cold source factory for every consumption', () async {
      var starts = 0;
      final flow = Flow.fromStream<int, String>(
        () => Stream.fromIterable([++starts, 2]),
        onError: (error, stackTrace) => '$error',
      );

      expect(await flow.runCollect().runFuture(), [1, 2]);
      expect(await flow.runCollect().runFuture(), [2, 2]);
      expect(starts, 2);
    });

    test('should preserve null and map source errors explicitly', () async {
      final source = StreamController<int?>();
      addTearDown(source.close);
      final flow = Flow.fromStream<int?, String>(
        () => source.stream,
        onError: (error, stackTrace) => 'mapped: $error',
      );
      final exitFuture = flow.runCollect().runFutureExit();
      await _waitForListener(source);
      source
        ..add(null)
        ..addError(StateError('source'));

      final cause = (await exitFuture as Failed<List<int?>, String>).cause;
      expect(cause.expectedErrors.single, contains('mapped: Bad state: source'));
    });

    test('should treat factory and error-mapper throws as defects', () async {
      final factory = Flow.fromStream<int, String>(
        () => throw StateError('factory'),
        onError: (error, stackTrace) => '$error',
      );
      final source = StreamController<int>();
      addTearDown(source.close);
      final mapper = Flow.fromStream<int, String>(
        () => source.stream,
        onError: (error, stackTrace) => throw StateError('mapper'),
      );

      final factoryExit = await factory.runCollect().runFutureExit();
      final mapperExitFuture = mapper.runCollect().runFutureExit();
      await _waitForListener(source);
      source.addError(StateError('source'));
      final mapperExit = await mapperExitFuture;

      expect((factoryExit as Failed<List<int>, String>).cause.containsFatal, isTrue);
      expect((mapperExit as Failed<List<int>, String>).cause.containsFatal, isTrue);
    });

    test('should apply drop-newest and drop-oldest within capacity', () async {
      final newest = await _runBurst(FlowOverflowPolicy.dropNewest);
      final oldest = await _runBurst(FlowOverflowPolicy.dropOldest);

      expect(newest, [1, 2, 3]);
      expect(oldest, [1, 3, 4]);
    });

    test('should fail through the configured overflow mapper', () async {
      final source = StreamController<int>(sync: true);
      addTearDown(source.close);
      final seen = <int>[];
      final flow =
          Flow.fromStream<int, String>(
            () => source.stream,
            onError: (error, stackTrace) => '$error',
            capacity: 2,
            overflow: FlowOverflowPolicy.fail,
            onOverflow: (overflow) => 'capacity ${overflow.capacity}',
          ).tap(
            (value) =>
                Effect.sync((_) => seen.add(value))
                    .mapError((value, _) => _widenNever(value! as Never)),
          );
      final exitFuture = flow.runDrain().runFutureExit();
      await _waitForListener(source);
      source
        ..add(1)
        ..add(2)
        ..add(3)
        ..add(4);

      final cause = (await exitFuture as Failed<void, String>).cause;
      expect(seen, [1, 2, 3]);
      expect(cause.expectedErrors, ['capacity 2']);
    });

    test('should pause a lossless source at capacity and resume after pulls', () async {
      var pauses = 0;
      final paused = Completer<void>();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final source = StreamController<int>(
        sync: true,
        onPause: () {
          pauses += 1;
          if (!paused.isCompleted) paused.complete();
        },
      );
      addTearDown(source.close);
      final flow =
          Flow.fromStream<int, String>(
            () => source.stream,
            onError: (error, stackTrace) => '$error',
            capacity: 2,
          ).mapEffect((value) {
            if (value != 1) return Effect.succeed(value);
            return Effect.tryFuture(
              (_) async {
                firstStarted.complete();
                await releaseFirst.future;
                return value;
              },
              onError: (error, stackTrace, _) => '$error',
            );
          });
      final valuesFuture = flow.runCollect().runFuture();
      await _waitForListener(source);
      source.add(1);
      await firstStarted.future;
      source
        ..add(2)
        ..add(3)
        ..add(4);
      await paused.future;
      final closing = source.close();
      releaseFirst.complete();

      expect(await valuesFuture, [1, 2, 3, 4]);
      await closing;
      expect(pauses, greaterThanOrEqualTo(1));
    });

    test('should await asynchronous source cancellation after an early take', () async {
      final cancellationStarted = Completer<void>();
      final releaseCancellation = Completer<void>();
      final source = StreamController<int>(
        sync: true,
        onCancel: () {
          cancellationStarted.complete();
          return releaseCancellation.future;
        },
      );
      final flow = Flow.fromStream<int, String>(
        () => source.stream,
        onError: (error, stackTrace) => '$error',
      ).take(1);
      final result = flow.runCollect().runFuture();
      await _waitForListener(source);
      source.add(1);
      await cancellationStarted.future;

      var completed = false;
      unawaited(result.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      releaseCancellation.complete();
      expect(await result, [1]);
      await source.close();
    });

    test('should preserve parent interruption after awaiting source cancellation', () async {
      final cancellationStarted = Completer<void>();
      final releaseCancellation = Completer<void>();
      final source = StreamController<int>(
        onCancel: () {
          cancellationStarted.complete();
          return releaseCancellation.future;
        },
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final consuming = runtime.fork(
        Flow.fromStream<int, String>(
          () => source.stream,
          onError: (error, stackTrace) => '$error',
        ).runDrain(),
      );
      await _waitForListener(source);

      final cancellation = consuming.interrupt('stop Stream Flow');
      await cancellationStarted.future;
      var completed = false;
      unawaited(cancellation.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      releaseCancellation.complete();
      final cause = (await cancellation as Failed<void, String>).cause;
      expect(cause, isA<Interrupted<String>>());
      expect((cause as Interrupted<String>).reason, 'stop Stream Flow');
      await source.close();
    });

    test('should validate capacity and fail-policy configuration', () {
      Stream<int> source() => const Stream.empty();
      String mapError(Object error, StackTrace stackTrace) => '$error';

      expect(
        () => Flow.fromStream<int, String>(source, onError: mapError, capacity: 0),
        throwsArgumentError,
      );
      expect(
        () => Flow.fromStream<int, String>(
          source,
          onError: mapError,
          overflow: FlowOverflowPolicy.fail,
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<List<int>> _runBurst(FlowOverflowPolicy overflow) async {
  final source = StreamController<int>(sync: true);
  final flow = Flow.fromStream<int, String>(
    () => source.stream,
    onError: (error, stackTrace) => '$error',
    capacity: 2,
    overflow: overflow,
  );
  final result = flow.runCollect().runFuture();
  await _waitForListener(source);
  source
    ..add(1)
    ..add(2)
    ..add(3)
    ..add(4);
  await source.close();
  return result;
}

Future<void> _waitForListener<T>(StreamController<T> controller) async {
  while (!controller.hasListener) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _widenNever(Never error) => error;

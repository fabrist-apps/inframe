import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  group('Flow timing', () {
    test('should debounce to the latest value after a monotonic quiet interval', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final listening = Completer<void>();
      final controller = StreamController<int>(sync: true, onListen: listening.complete);
      addTearDown(controller.close);
      final values = <int>[];
      final fiber = runtime.fork(
        Flow.fromStream<int, String>(
              () => controller.stream,
              onError: (error, stackTrace) => '$error',
            )
            .debounce(
              const Duration(seconds: 5),
            )
            .runForEach(
              (value) =>
                  Effect.sync((_) => values.add(value))
                      .mapError((value, _) => _widenNever(value! as Never)),
            ),
      );

      await listening.future;
      controller.add(1);
      await _waitUntil(() => clock.activeWaits == 1);
      clock.advanceMonotonic(const Duration(seconds: 3));
      controller.add(2);
      await _flushMicrotasks();
      clock.adjustWall(const Duration(days: 1));
      await _flushMicrotasks();
      expect(values, isEmpty);

      clock.advanceMonotonic(const Duration(seconds: 4));
      await _flushMicrotasks();
      expect(values, isEmpty);
      clock.advanceMonotonic(const Duration(seconds: 1));
      await _waitUntil(() => values.length == 1);
      expect(values, [2]);

      await controller.close();
      expect(await fiber.join(), isA<Succeeded<void, String>>());
      expect(clock.activeWaits, 0);
    });

    test('should flush debounce on completion and discard it on failure', () async {
      final completed = await Flow.fromIterable([1, 2])
          .widenError<String>()
          .debounce(const Duration(days: 1))
          .runCollect()
          .runFuture();
      final failedValues = <int>[];
      final failed = await Flow.succeed<int, String>(1)
          .concat(Flow.fail('failed'))
          .debounce(const Duration(days: 1))
          .runForEach(
            (value) =>
                Effect.sync((_) => failedValues.add(value))
                    .mapError((value, _) => _widenNever(value! as Never)),
          )
          .runFutureExit();

      expect(completed, [2]);
      expect(failedValues, isEmpty);
      expect((failed as Failed<void, String>).cause.expectedErrors, ['failed']);
    });

    test('should throttle leading values without a trailing emission', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final listening = Completer<void>();
      final controller = StreamController<int>(sync: true, onListen: listening.complete);
      addTearDown(controller.close);
      final values = <int>[];
      final fiber = runtime.fork(
        Flow.fromStream<int, Never>(
              () => controller.stream,
              onError: _impossibleStreamError,
            )
            .throttle(
              const Duration(seconds: 5),
            )
            .runForEach((value) => Effect.sync((_) => values.add(value))),
      );

      await listening.future;
      controller
        ..add(1)
        ..add(2);
      await _waitUntil(() => values.isNotEmpty);
      clock.adjustWall(const Duration(days: 1));
      controller.add(3);
      await _flushMicrotasks();
      expect(values, [1]);
      clock.advanceMonotonic(const Duration(seconds: 5));
      controller
        ..add(4)
        ..add(5);
      await controller.close();

      expect(await fiber.join(), isA<Succeeded<void, Never>>());
      expect(values, [1, 4]);
    });

    test('should release debounce timing and source cleanup on cancellation', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final listening = Completer<void>();
      final cancelled = Completer<void>();
      final controller = StreamController<int>(
        sync: true,
        onListen: listening.complete,
        onCancel: cancelled.complete,
      );
      addTearDown(controller.close);
      final fiber = runtime.fork(
        Flow.fromStream<int, String>(
          () => controller.stream,
          onError: (error, stackTrace) => '$error',
        ).debounce(const Duration(seconds: 5)).runDrain(),
      );

      await listening.future;
      controller.add(1);
      await _waitUntil(() => clock.activeWaits == 1);
      await fiber.interrupt('stop');

      expect(clock.activeWaits, 0);
      expect(cancelled.isCompleted, isTrue);
    });

    test('should keep timing staging bounded for a slow consumer', () async {
      var pulled = 0;
      final consumerStarted = Completer<void>();
      final releaseConsumer = Completer<void>();
      final values = <int>[];
      final flow = Flow.fromIterable(List.generate(100, (index) => index))
          .widenError<String>()
          .tap(
            (_) =>
                Effect.sync((_) => pulled += 1)
                    .mapError((value, _) => _widenNever(value! as Never)),
          )
          .debounce(Duration.zero, capacity: 1);
      final subscription = flow.subscribe((value) {
        values.add(value);
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
      expect(pulled, lessThanOrEqualTo(6));

      releaseConsumer.complete();
      expect(await subscription.completion, isA<Succeeded<void, String>>());
      expect(values, List.generate(100, (index) => index));
    });

    test('should stop the source before exposing output overflow', () async {
      final listening = Completer<void>();
      final sourceCancelled = Completer<void>();
      final consumerStarted = Completer<void>();
      final releaseConsumer = Completer<void>();
      final controller = StreamController<int>(
        sync: true,
        onListen: listening.complete,
        onCancel: sourceCancelled.complete,
      );
      addTearDown(controller.close);
      final subscription =
          Flow.fromStream<int, String>(
                () => controller.stream,
                onError: (error, stackTrace) => '$error',
              )
              .debounce(
                Duration.zero,
                capacity: 1,
                overflow: FlowOverflowPolicy.fail,
                onOverflow: (_) => 'overflow',
              )
              .subscribe((_) {
                return Effect.tryFuture<void, String>(
                  (_) {
                    if (!consumerStarted.isCompleted) consumerStarted.complete();
                    return releaseConsumer.future;
                  },
                  onError: (error, stackTrace, _) => '$error',
                );
              });

      await listening.future;
      controller.add(1);
      await consumerStarted.future;
      controller.add(2);
      await _flushMicrotasks();
      controller.add(3);
      await sourceCancelled.future;
      releaseConsumer.complete();

      final exit = await subscription.completion;
      expect(exit, isA<Failed<void, String>>());
      expect((exit as Failed<void, String>).cause.expectedErrors, ['overflow']);
    });

    test('should validate timing configuration eagerly', () {
      final source = Flow.succeed<int, String>(1);

      expect(
        () => source.debounce(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => source.throttle(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      expect(() => source.debounce(Duration.zero, capacity: 0), throwsArgumentError);
      expect(
        () => source.throttle(
          Duration.zero,
          overflow: FlowOverflowPolicy.fail,
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true.');
}

Future<void> _flushMicrotasks() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _widenNever(Never error) => error;

Never _impossibleStreamError(Object error, StackTrace stackTrace) {
  throw StateError('Unexpected Stream error: $error');
}

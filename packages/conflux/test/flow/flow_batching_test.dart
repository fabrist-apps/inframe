import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/flow/flow_buffer.dart' show FlowMailbox;
import 'package:test/test.dart';

import '../support/fake_clock.dart';

void main() {
  group('Flow batching', () {
    test('should emit immutable count batches and flush normal completion', () async {
      final batches = await Flow.fromIterable([1, 2, 3, 4, 5])
          .bufferCount(2)
          .runCollect()
          .runFuture();

      expect(batches, [
        [1, 2],
        [3, 4],
        [5],
      ]);
      expect(() => batches.first.add(9), throwsUnsupportedError);
    });

    test('should flush timed batches on elapsed time or maximum size', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final listening = Completer<void>();
      final controller = StreamController<int>(sync: true, onListen: listening.complete);
      addTearDown(controller.close);
      final batches = <List<int>>[];
      final fiber = runtime.fork(
        Flow.fromStream<int, String>(
              () => controller.stream,
              onError: (error, stackTrace) => '$error',
            )
            .bufferTime(
              const Duration(seconds: 5),
              maxSize: 2,
            )
            .runForEach(
              (batch) =>
                  Effect.sync((_) => batches.add(batch))
                      .mapError((value, _) => _widenNever(value! as Never)),
            ),
      );

      await listening.future;
      controller.add(1);
      await _waitUntil(() => clock.activeWaits == 1);
      clock.advance(const Duration(seconds: 5));
      await _waitUntil(() => batches.length == 1);
      expect(batches, [
        [1],
      ]);

      controller
        ..add(2)
        ..add(3);
      await _waitUntil(() => batches.length == 2);
      expect(batches, [
        [1],
        [2, 3],
      ]);
      expect(clock.activeWaits, 0);

      await controller.close();
      expect(await fiber.join(), isA<Succeeded<void, String>>());
    });

    test('should discard incomplete count and timed batches on failure', () async {
      final countBatches = <List<int>>[];
      final countExit = await Flow.succeed<int, String>(1)
          .concat(Flow.fail('count failed'))
          .bufferCount(2)
          .runForEach(
            (batch) =>
                Effect.sync((_) => countBatches.add(batch))
                    .mapError((value, _) => _widenNever(value! as Never)),
          )
          .runFutureExit();

      final timedBatches = <List<int>>[];
      final timedExit = await Flow.succeed<int, String>(1)
          .concat(Flow.fail('time failed'))
          .bufferTime(const Duration(days: 1), maxSize: 2)
          .runForEach(
            (batch) =>
                Effect.sync((_) => timedBatches.add(batch))
                    .mapError((value, _) => _widenNever(value! as Never)),
          )
          .runFutureExit();

      expect(countBatches, isEmpty);
      expect((countExit as Failed<void, String>).cause.expectedErrors, ['count failed']);
      expect(timedBatches, isEmpty);
      expect((timedExit as Failed<void, String>).cause.expectedErrors, ['time failed']);
    });

    test('should release a pending batch timer on cancellation', () async {
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
        ).bufferTime(const Duration(seconds: 5), maxSize: 2).runDrain(),
      );

      await listening.future;
      controller.add(1);
      await _waitUntil(() => clock.activeWaits == 1);
      await fiber.interrupt('stop');

      expect(clock.activeWaits, 0);
      expect(cancelled.isCompleted, isTrue);
    });

    test('should preserve an interrupted terminal cause at a timer boundary', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final mailbox = FlowMailbox<int, String>(
        1,
        FlowOverflowPolicy.backpressure,
        null,
      );
      final sourceCause = Sequential<String>([
        const Interrupted('source stopped'),
        Defect(StateError('source cleanup failed'), StackTrace.current),
      ]);
      final fiber = runtime.fork(
        mailbox.takeUntil(const Duration(seconds: 5)),
      );

      await _waitUntil(() => clock.activeWaits == 1);
      clock.advanceMonotonic(const Duration(seconds: 5));
      mailbox.fail(sourceCause);

      final exit = await fiber.join();
      expect(exit, isA<Failed<({bool elapsed, Option<int> value}), String>>());
      expect(
        (exit as Failed<({bool elapsed, Option<int> value}), String>).cause,
        same(sourceCause),
      );
    });

    test('should bound timed source read-ahead and batch growth', () async {
      var pulled = 0;
      final consumerStarted = Completer<void>();
      final releaseConsumer = Completer<void>();
      final batches = <List<int>>[];
      final flow = Flow.fromIterable(List.generate(100, (index) => index))
          .widenError<String>()
          .tap(
            (_) =>
                Effect.sync((_) => pulled += 1)
                    .mapError((value, _) => _widenNever(value! as Never)),
          )
          .bufferTime(
            const Duration(days: 1),
            maxSize: 2,
            capacity: 1,
          );
      final subscription = flow.subscribe((batch) {
        batches.add(batch);
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
      expect(pulled, lessThanOrEqualTo(5));

      releaseConsumer.complete();
      expect(await subscription.completion, isA<Succeeded<void, String>>());
      expect(batches, everyElement(hasLength(lessThanOrEqualTo(2))));
      expect(pulled, 100);
    });

    test('should anchor buffered windows to upstream arrival time', () async {
      final clock = FakeClock();
      final runtime = Runtime(clock: clock);
      addTearDown(runtime.close);
      final listening = Completer<void>();
      final consumerStarted = Completer<void>();
      final releaseConsumer = Completer<void>();
      final controller = StreamController<int>(sync: true)..onListen = listening.complete;
      addTearDown(controller.close);
      final batches = <List<int>>[];
      final fiber = runtime.fork(
        Flow.fromStream<int, String>(
              () => controller.stream,
              onError: (error, stackTrace) => '$error',
            )
            .bufferTime(
              const Duration(seconds: 5),
              maxSize: 2,
              capacity: 4,
            )
            .runForEach((batch) {
              batches.add(batch);
              if (batches.length > 1) return Effect.succeed(null);
              return Effect.tryFuture<void, String>(
                (_) {
                  consumerStarted.complete();
                  return releaseConsumer.future;
                },
                onError: (error, stackTrace, _) => '$error',
              );
            }),
      );

      await listening.future;
      controller
        ..add(1)
        ..add(2);
      await consumerStarted.future;
      controller.add(3);
      await _flushMicrotasks();
      clock.advanceMonotonic(const Duration(seconds: 6));
      controller.add(4);
      await controller.close();
      releaseConsumer.complete();

      expect(await fiber.join(), isA<Succeeded<void, String>>());
      expect(batches, [
        [1, 2],
        [3],
        [4],
      ]);
    });

    test('should validate batch configuration eagerly', () {
      final source = Flow.succeed<int, String>(1);

      expect(() => source.bufferCount(0), throwsArgumentError);
      expect(
        () => source.bufferTime(const Duration(microseconds: -1), maxSize: 1),
        throwsArgumentError,
      );
      expect(
        () => source.bufferTime(Duration.zero, maxSize: 0),
        throwsArgumentError,
      );
      expect(
        () => source.bufferTime(Duration.zero, maxSize: 1, capacity: 0),
        throwsArgumentError,
      );
      expect(
        () => source.bufferTime(
          Duration.zero,
          maxSize: 1,
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

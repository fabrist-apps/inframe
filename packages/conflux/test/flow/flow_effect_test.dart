import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:test/test.dart';

void main() {
  group('Flow effectful operations', () {
    test('should sequence mapEffect work in source order', () async {
      final started = List.generate(3, (_) => Completer<void>());
      final release = List.generate(3, (_) => Completer<void>());
      final runtime = Runtime();
      addTearDown(runtime.close);
      final flow = Flow.fromIterable([0, 1, 2]).widenError<String>().mapEffect(
        (value) => Effect.tryFuture(
          () async {
            started[value].complete();
            await release[value].future;
            return value * 10;
          },
          onError: (error, stackTrace) => '$error',
        ),
      );

      final fiber = runtime.fork(flow.runCollect());
      await started[0].future;
      expect(started[1].isCompleted, isFalse);
      release[0].complete();
      await started[1].future;
      expect(started[2].isCompleted, isFalse);
      release[1].complete();
      await started[2].future;
      release[2].complete();

      expect((await fiber.join() as Succeeded<List<int>, String>).value, [0, 10, 20]);
    });

    test('should consume each concatMap inner Flow before opening the next', () async {
      final events = <String>[];
      final values = await Flow.fromIterable([1, 2])
          .widenError<String>()
          .concatMap((outer) {
            events.add('open $outer');
            return Flow.fromIterable([outer, outer * 10]).widenError();
          })
          .runCollect()
          .runFuture();

      expect(values, [1, 10, 2, 20]);
      expect(events, ['open 1', 'open 2']);
    });

    test('should close each concatMap inner scope before opening the next', () async {
      final events = <String>[];
      final flow = Flow.fromIterable([1, 2]).widenError<String>().concatMap(
        (value) => Effect.build<int, String>(($) async {
          await $.acquireRelease(
            Effect.sync(() => events.add('acquire $value')).mapError(_widenNever),
            release: (_) => Effect.sync(() => events.add('release $value')),
          );
          return value;
        }).asFlow(),
      );

      expect(await flow.runCollect().runFuture(), [1, 2]);
      expect(events, ['acquire 1', 'release 1', 'acquire 2', 'release 2']);
    });

    test('should sequence runForEach and stop after failure', () async {
      final consumed = <int>[];
      final exit = await Flow.fromIterable([1, 2, 3]).widenError<String>().runForEach((value) {
        consumed.add(value);
        return value == 2 ? Effect.fail('stop') : Effect.succeed(null);
      }).runFutureExit();

      expect(exit, isA<Failed<void, String>>());
      expect(consumed, [1, 2]);
    });

    test('should fold, drain, and return the last present value', () async {
      final source = Flow.fromIterable<int?>([1, 3, null]);

      expect(
        await source.runFold(0, (count, _) => count + 1).runFuture(),
        3,
      );
      expect(await Flow.empty<int, Never>().runFold(4, (a, b) => a + b).runFuture(), 4);
      await source.runDrain().runFuture();
      final last = await source.runLast().runFuture();
      expect(last, isA<Some<int?>>());
      expect((last as Some<int?>).value, isNull);
      expect(await Flow.empty<int, Never>().runLast().runFuture(), isA<None>());
    });

    test('should interrupt pending effectful work and await its cancellation', () async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final pending = Completer<int>();
      final runtime = Runtime();
      addTearDown(runtime.close);
      final flow = Flow.succeed<int, String>(1).mapEffect(
        (_) => Effect.tryFuture(
          () {
            started.complete();
            return pending.future;
          },
          onError: (error, stackTrace) => '$error',
          onCancel: cancelled.complete,
        ),
      );

      final fiber = runtime.fork(flow.runDrain());
      await started.future;
      final exit = await fiber.interrupt('stop');

      expect(exit, isA<Failed<void, String>>());
      expect(cancelled.isCompleted, isTrue);
    });
  });
}

String _widenNever(Never error) => error;

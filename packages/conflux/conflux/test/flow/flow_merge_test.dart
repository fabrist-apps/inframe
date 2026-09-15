import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Flow concurrent merge', () {
    test('should preserve mapper and overflow Context regions', () async {
      final request = ContextKey<String>('request');
      final caller = Context().withBinding(request.bind('caller'));
      final owner = caller.withBinding(request.bind('owner'));
      final release = Completer<void>();
      final overflowed = Completer<void>();
      final seen = <String>[];
      var blocked = false;
      final flow = Flow.fromIterable([1, 2, 3])
          .widenError<String>()
          .mergeMap(
            (value, context) {
              seen.add('map:$value:${context.require(request)}');
              return Flow.defer((innerContext) {
                seen.add('inner:$value:${innerContext.require(request)}');
                return Flow.succeed(value);
              });
            },
            concurrency: 3,
            capacity: 1,
            overflow: FlowOverflowPolicy.fail,
            onOverflow: (event, context) {
              seen.add('overflow:${context.require(request)}');
              if (!overflowed.isCompleted) overflowed.complete();
              return 'capacity ${event.capacity}';
            },
          )
          .withContext(owner)
          .mapEffect((value, context) {
            seen.add('consumer:$value:${context.require(request)}');
            if (blocked) return Effect.succeed(value);
            blocked = true;
            return Effect.tryFuture(
              (_) async {
                await release.future;
                return value;
              },
              onError: (error, stackTrace, _) => '$error',
            );
          });
      final runtime = Runtime(context: caller);
      addTearDown(runtime.close);

      final exit = runtime.run(flow.runDrain());
      await overflowed.future;
      release.complete();

      expect(await exit, isA<Failed<void, String>>());
      expect(seen, contains('overflow:owner'));
      final consumers = seen.where((entry) => entry.startsWith('consumer:'));
      expect(consumers, isNotEmpty);
      expect(consumers.every((entry) => entry.endsWith(':caller')), isTrue);
      expect(seen.where((entry) => entry.startsWith('map:')), isNotEmpty);
      expect(
        seen.where((entry) => entry.startsWith('map:')).every((entry) => entry.endsWith(':owner')),
        isTrue,
      );
      expect(
        seen
            .where((entry) => entry.startsWith('inner:'))
            .every((entry) => entry.endsWith(':owner')),
        isTrue,
      );
    });

    test('should merge inner values by availability within its concurrency limit', () async {
      final started = List.generate(3, (_) => Completer<void>());
      final releases = List.generate(3, (_) => Completer<int>());
      final runtime = Runtime();
      addTearDown(runtime.close);
      final flow = Flow.fromIterable([0, 1, 2]).widenError<String>().mergeMap(
        (value, _) => Effect.tryFuture<int, String>(
          (_) {
            started[value].complete();
            return releases[value].future;
          },
          onError: (error, stackTrace, _) => '$error',
        ).asFlow(),
        concurrency: 2,
        capacity: 4,
      );

      final fiber = runtime.fork(flow.runCollect());
      await Future.wait([started[0].future, started[1].future]);
      expect(started[2].isCompleted, isFalse);

      releases[1].complete(10);
      await started[2].future;
      releases[0].complete(0);
      releases[2].complete(20);

      expect((await fiber.join() as Succeeded<List<int>, String>).value, [10, 0, 20]);
    });

    test('should merge sources and await sibling cleanup after failure', () async {
      final slowStarted = Completer<void>();
      final slowCancelled = Completer<void>();
      final never = Completer<int>();
      final slow = Effect.tryFuture<int, String>(
        (_) {
          slowStarted.complete();
          return never.future;
        },
        onError: (error, stackTrace, _) => '$error',
        onCancel: (_) {
          slowCancelled.complete();
          throw StateError('cleanup failed');
        },
      ).asFlow();
      final merged = Flow.merge<int, String>([
        slow,
        Flow.fail('failed'),
      ]);

      final exitFuture = merged.runCollect().runFutureExit();
      await slowStarted.future;
      final exit = await exitFuture;

      expect(exit, isA<Failed<List<int>, String>>());
      expect((exit as Failed<List<int>, String>).cause.expectedErrors, ['failed']);
      expect(exit.cause.containsFatal, isTrue);
      expect(slowCancelled.isCompleted, isTrue);
    });

    test('should enumerate merge sources lazily for each consumption', () async {
      var enumerations = 0;
      Iterable<Flow<int, Never>> sources() sync* {
        enumerations += 1;
        yield Flow.succeed(1);
      }

      final flow = Flow.merge(sources());
      expect(enumerations, 0);

      expect(await flow.runCollect().runFuture(), [1]);
      expect(await flow.runCollect().runFuture(), [1]);
      expect(enumerations, 2);
    });

    test('should complete after every merged source completes', () async {
      final values = await Flow.merge([
        Flow.fromIterable([1, 2]),
        Flow.fromIterable([3, 4]),
      ]).runCollect().runFuture();

      expect(values, unorderedEquals([1, 2, 3, 4]));
    });

    test('should bound read-ahead while a backpressured consumer is slow', () async {
      final consumerStarted = Completer<void>();
      final releaseConsumer = Completer<void>();
      var pulled = 0;
      final source = Flow.fromIterable(List.generate(100, (index) => index))
          .widenError<String>()
          .tap(
            (_, _) => Effect.sync((_) => pulled += 1),
          );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(
        Flow.merge([source], capacity: 1).runForEach(
          (_, _) => Effect.tryFuture(
            (_) {
              if (!consumerStarted.isCompleted) consumerStarted.complete();
              return releaseConsumer.future;
            },
            onError: (error, stackTrace, _) => '$error',
          ),
        ),
      );

      await consumerStarted.future;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(pulled, lessThanOrEqualTo(3));

      releaseConsumer.complete();
      expect(await fiber.join(), isA<Succeeded<void, String>>());
      expect(pulled, 100);
    });

    test('should fail through the overflow mapper when configured', () async {
      final consumerStarted = Completer<void>();
      final releaseConsumer = Completer<void>();
      final consumed = <int>[];
      final runtime = Runtime();
      addTearDown(runtime.close);
      final flow = Flow.merge<int, String>(
        [
          Flow.fromIterable([1, 2, 3]).widenError(),
        ],
        capacity: 1,
        overflow: FlowOverflowPolicy.fail,
        onOverflow: (overflow, _) => 'capacity ${overflow.capacity}',
      );
      final fiber = runtime.fork(
        flow.runForEach((value, _) {
          consumed.add(value);
          if (value != 1) return Effect.succeed(null);
          return Effect.tryFuture(
            (_) {
              consumerStarted.complete();
              return releaseConsumer.future;
            },
            onError: (error, stackTrace, _) => '$error',
          );
        }),
      );

      await consumerStarted.future;
      await Future<void>.delayed(Duration.zero);
      releaseConsumer.complete();
      final exit = await fiber.join();

      expect(exit, isA<Failed<void, String>>());
      expect((exit as Failed<void, String>).cause.expectedErrors, ['capacity 1']);
      expect(consumed, [1, 2]);
    });

    test('should apply drop policies to a full output buffer', () async {
      Future<List<int>> collect(FlowOverflowPolicy overflow) async {
        final consumerStarted = Completer<void>();
        final releaseConsumer = Completer<void>();
        final values = <int>[];
        final subscription =
            Flow.merge(
              [
                Flow.fromIterable([1, 2, 3, 4]),
              ],
              capacity: 1,
              overflow: overflow,
            ).subscribe((value, _) {
              values.add(value);
              if (value != 1) return Effect.succeed(null);
              return Effect.tryFuture<void, Never>(
                (_) {
                  consumerStarted.complete();
                  return releaseConsumer.future;
                },
                onError: (error, stackTrace, _) => _impossibleFutureError(error, stackTrace),
              );
            });
        await consumerStarted.future;
        await Future<void>.delayed(Duration.zero);
        releaseConsumer.complete();
        expect(await subscription.completion, isA<Succeeded<void, Never>>());
        return values;
      }

      expect(await collect(FlowOverflowPolicy.dropNewest), [1, 2]);
      expect(await collect(FlowOverflowPolicy.dropOldest), [1, 4]);
    });

    test('should validate concurrency and overflow configuration eagerly', () {
      final source = Flow.succeed<int, String>(1);

      expect(
        () => source.mergeMap((value, _) => Flow.succeed(value), concurrency: 0),
        throwsArgumentError,
      );
      expect(
        () => Flow.merge([source], capacity: 0),
        throwsArgumentError,
      );
      expect(
        () => Flow.merge(
          [source],
          overflow: FlowOverflowPolicy.fail,
        ),
        throwsArgumentError,
      );
    });

    test('should release active inner work when downstream stops early', () async {
      final started = List.generate(2, (_) => Completer<void>());
      final first = Completer<int>();
      final innerCancelled = Completer<void>();
      final never = Completer<int>();
      final runtime = Runtime();
      addTearDown(runtime.close);
      final flow = Flow.fromIterable([0, 1]).widenError<String>().mergeMap(
        (value, _) => Effect.tryFuture<int, String>(
          (_) {
            started[value].complete();
            return value == 0 ? first.future : never.future;
          },
          onError: (error, stackTrace, _) => '$error',
          onCancel: value == 1 ? innerCancelled.complete : null,
        ).asFlow(),
        concurrency: 2,
      );

      final fiber = runtime.fork(flow.runFirst());
      await Future.wait(started.map((event) => event.future));
      first.complete(1);
      expect(await fiber.join(), isA<Succeeded<Object?, String>>());
      expect(innerCancelled.isCompleted, isTrue);
    });
  });
}

Never _impossibleFutureError(Object error, StackTrace stackTrace) {
  throw StateError('Unexpected future failure: $error');
}

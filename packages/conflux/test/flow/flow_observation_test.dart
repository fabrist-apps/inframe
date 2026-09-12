import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Flow context, failures, and hooks', () {
    test('should replace Context for the Flow without changing siblings', () async {
      final key = ContextKey<String>('name');
      final parent = Context().withBinding(key.bind('parent'));
      final child = parent.withBinding(key.bind('child'));
      final read = Effect.context<String>((context) => context.require(key)).asFlow();
      final runtime = Runtime(context: parent);
      addTearDown(runtime.close);

      final childExit = await runtime.run(read.withContext(child).runCollect());
      final parentExit = await runtime.run(read.runCollect());

      expect((childExit as Succeeded<List<String>, Never>).value, ['child']);
      expect((parentExit as Succeeded<List<String>, Never>).value, ['parent']);
    });

    test('should map expected leaves while preserving fatal causes', () async {
      final cause = Sequential<String>([
        const Expected('expected'),
        Defect(StateError('defect'), StackTrace.current),
      ]);
      final exit = await Effect.failCause<int, String>(cause)
          .asFlow()
          .mapError((error) => error.length)
          .runCollect()
          .runFutureExit();

      final mapped = (exit as Failed<List<int>, int>).cause;
      expect(mapped.expectedErrors, [8]);
      expect(mapped.containsFatal, isTrue);
    });

    test('should recover once from expected failure and preserve defects', () async {
      var recoveries = 0;
      final recovered = Flow.fail<int, String>('missing').catchError((error) {
        recoveries += 1;
        return Flow.succeed(error.length);
      });
      final defective = Effect.sync<int>((_) => throw StateError('broken'))
          .mapError<String>((value, _) => _widenNever(value! as Never))
          .asFlow()
          .catchError((error) {
            recoveries += 1;
            return Flow.succeed(0);
          });

      expect(await recovered.runCollect().runFuture(), [7]);
      expect(await defective.runCollect().runFutureExit(), isA<Failed<List<int>, String>>());
      expect(recoveries, 1);
    });

    test('should recover grouped expected failures from the primary error once', () async {
      var recoveredError = '';
      final source =
          Effect.failCause<int, String>(
            Sequential([const Expected('first'), const Expected('second')]),
          ).asFlow().catchError((error) {
            recoveredError = error;
            return Flow.succeed(error.length);
          });

      expect(await source.runCollect().runFuture(), [5]);
      expect(recoveredError, 'first');
    });

    test('should sequence value and failure observations without recovery', () async {
      final seen = <String>[];
      final success = Flow.succeed<int, String>(1).tap(
        (value) =>
            Effect.sync((_) => seen.add('value $value'))
                .mapError((value, _) => _widenNever(value! as Never)),
      );
      final failed = Flow.fail<int, String>('source')
          .tapError((error) => Effect.sync((_) => seen.add('error $error')))
          .tapCause((cause) => Effect.sync((_) => seen.add('cause ${cause.expectedErrors}')));

      expect(await success.runCollect().runFuture(), [1]);
      final exit = await failed.runCollect().runFutureExit();
      expect(exit, isA<Failed<List<int>, String>>());
      expect(seen, ['value 1', 'error source', 'cause [source]']);
    });

    test('should append observer and finalizer defects after source failure', () async {
      final flow = Flow.fail<int, String>('source')
          .tapError((_) => Effect.sync((_) => throw StateError('observer')))
          .ensuring(Effect.sync((_) => throw StateError('finalizer')));

      final exit = await flow.runCollect().runFutureExit();
      final cause = (exit as Failed<List<int>, String>).cause;

      expect(cause, isA<Sequential<String>>());
      expect(cause.expectedErrors, ['source']);
      expect(cause.containsFatal, isTrue);
    });

    test('should run onExit once for success, failure, and cancellation', () async {
      final exits = <Exit<void, String>>[];
      final success = Flow.succeed<int, String>(1).onExit(
        (exit) => Effect.sync((_) => exits.add(exit)),
      );
      final failure = Flow.fail<int, String>('failed').onExit(
        (exit) => Effect.sync((_) => exits.add(exit)),
      );
      final started = Completer<void>();
      final pending = Completer<int>();
      final cancelled = Effect.tryFuture<int, String>(
        () {
          started.complete();
          return pending.future;
        },
        onError: (error, stackTrace) => '$error',
      ).asFlow().onExit((exit) => Effect.sync((_) => exits.add(exit)));
      final runtime = Runtime();
      addTearDown(runtime.close);

      await success.runFirst().runFuture();
      await failure.runCollect().runFutureExit();
      final fiber = runtime.fork(cancelled.runDrain());
      await started.future;
      await fiber.interrupt('cancel');

      expect(exits, hasLength(3));
      expect(exits[0], isA<Succeeded<void, String>>());
      expect(exits[1], isA<Failed<void, String>>());
      expect(exits[2], isA<Failed<void, String>>());
      expect((exits[2] as Failed<void, String>).cause.containsInterruption, isTrue);
    });

    test('should preserve ordered exit hooks through later operators', () async {
      final events = <String>[];
      final flow = Flow.fromIterable([1, 2])
          .onExit(
            (exit) => Effect.sync(
              (_) => events.add('source ${exit is Succeeded<void, Never>}'),
            ),
          )
          .map((value) => value * 2)
          .onExit((_) => Effect.sync((_) => events.add('mapped')))
          .ensuring(Effect.sync((_) => events.add('outer')));

      expect(await flow.runCollect().runFuture(), [2, 4]);
      expect(events, ['source true', 'mapped', 'outer']);
    });

    test('should finalize concatenated source scopes in consumption order', () async {
      final events = <String>[];
      final first = Flow.succeed<int, Never>(1).ensuring(
        Effect.sync((_) => events.add('first')),
      );
      final second = Flow.succeed<int, Never>(2).ensuring(
        Effect.sync((_) => events.add('second')),
      );

      expect(await first.concat(second).runCollect().runFuture(), [1, 2]);
      expect(events, ['first', 'second']);
    });
  });
}

String _widenNever(Never error) => error;

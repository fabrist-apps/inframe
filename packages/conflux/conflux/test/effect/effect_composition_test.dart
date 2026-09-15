import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Effect composition', () {
    test('should pass each execution Context through composition callbacks', () async {
      final request = ContextKey<String>('request');
      final seen = <String>[];
      final effect = Effect.sync((context) => context.require(request))
          .map((value, context) {
            seen.add('map:${context.require(request)}');
            return value.length;
          })
          .tap((value, context) {
            return Effect.sync((innerContext) {
              seen.add('tap:$value:${innerContext.require(request)}');
            });
          });

      final first = await Runtime(
        context: Context().withBinding(request.bind('first')),
      ).run(effect);
      final second = await Runtime(
        context: Context().withBinding(request.bind('second')),
      ).run(effect);

      expect((first as Succeeded<int, Never>).value, 5);
      expect((second as Succeeded<int, Never>).value, 6);
      expect(seen, ['map:first', 'tap:5:first', 'map:second', 'tap:6:second']);
    });

    test('should restore an outer Context before its observer runs', () async {
      final request = ContextKey<String>('request');
      final outer = Context().withBinding(request.bind('outer'));
      final inner = outer.withBinding(request.bind('inner'));
      late String observed;
      final effect = Effect.sync((context) => context.require(request))
          .withContext(inner)
          .tap((_, context) {
            return Effect.sync((_) => observed = context.require(request));
          });

      final exit = await Runtime(context: outer).run(effect);

      expect((exit as Succeeded<String, Never>).value, 'inner');
      expect(observed, 'outer');
    });

    test('should keep concurrent child Contexts independent', () async {
      final request = ContextKey<String>('request');
      final root = Context().withBinding(request.bind('root'));
      final mapperContexts = <String>[];
      final effect = Effect.forEach<String, String, Never>(
        ['left', 'right'],
        (name, context) {
          mapperContexts.add(context.require(request));
          return Effect.sync(
            (childContext) => childContext.require(request),
          ).withContext(root.withBinding(request.bind(name)));
        },
        concurrency: 2,
      );

      final exit = await Runtime(context: root).run(effect);

      expect((exit as Succeeded<List<String>, Never>).value, ['left', 'right']);
      expect(mapperContexts, ['root', 'root']);
    });

    test('should reject composite causes without a failure leaf', () {
      expect(() => Sequential<String>(const []), throwsArgumentError);
      expect(() => Parallel<String>(const []), throwsArgumentError);
    });

    test('should transform and sequence successful values', () async {
      final effect = Effect.succeed<int, String>(2)
          .map((value, _) => value + 1)
          .flatMap((value, _) => Effect.succeed<int, String>(value * 2))
          .zipWith(Effect.succeed<String, String>('ok'), (left, right, _) => '$left:$right');

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<String, String>).value, '6:ok');
    });

    test('should map expected leaves without changing cause structure', () async {
      final source = Effect.failCause<int, int>(
        Sequential([const Expected(1), const Expected(2)]),
      );

      final exit = await Runtime().run(source.mapError((error, _) => 'e$error'));
      final causes = ((exit as Failed<int, String>).cause as Sequential<String>).causes;

      expect((causes[0] as Expected<String>).error, 'e1');
      expect((causes[1] as Expected<String>).error, 'e2');
    });

    test('should recover all-expected groups once using source order', () async {
      var recoveries = 0;
      final source = Effect.failCause<int, String>(
        Parallel([const Expected('first'), const Expected('second')]),
      );
      final effect = source.catchError((error, _) {
        recoveries += 1;
        return Effect.succeed<int, String>(error.length);
      });

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<int, String>).value, 5);
      expect(recoveries, 1);
    });

    test('should recover before synchronous and asynchronous builder binds', () async {
      final effect = Effect.build<int, String>(($) async {
        final local = $.sync<int>(
          const Failure<int, String>('missing').orElse(
            (_) => const Success(20),
          ),
        );
        final remote = await $(
          Effect.fail<int, String>('offline').catchError(
            (_, _) => Effect.succeed<int, String>(22),
          ),
        );
        return local + remote;
      });

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<int, String>).value, 42);
    });

    test('should preserve a nullable primary expected error', () async {
      String? observed = 'unset';
      final source = Effect.failCause<int, String?>(const Expected(null));

      final exit = await Runtime().run(
        source.catchError((error, _) {
          observed = error;
          return Effect.succeed<int, String?>(42);
        }),
      );

      expect((exit as Succeeded<int, String?>).value, 42);
      expect(observed, isNull);
    });

    test('should propagate a complete mixed cause without recovery', () async {
      var recovered = false;
      final defect = Defect<String>(StateError('bad'), StackTrace.current);
      final cause = Sequential<String>([const Expected('expected'), defect]);
      final source = Effect.failCause<int, String>(cause);

      final exit = await Runtime().run(
        source.catchError((_, _) {
          recovered = true;
          return Effect.succeed<int, String>(1);
        }),
      );

      expect(recovered, isFalse);
      expect((exit as Failed<int, String>).cause, same(cause));
    });

    test('should preserve the original cause before an observer defect', () async {
      final source = Effect.fail<int, String>('expected').tapCause(
        (_, _) => Effect.sync((_) => throw StateError('observer')),
      );

      final cause = (await Runtime().run(source) as Failed<int, String>).cause;

      expect(cause, isA<Sequential<String>>());
      final causes = (cause as Sequential<String>).causes;
      expect(causes[0], isA<Expected<String>>());
      expect(causes[1], isA<Defect<String>>());
    });

    test('should expose the complete cause before primary recovery', () async {
      late Cause<String> observed;
      final cause = Parallel<String>([
        const Expected('first'),
        const Expected('second'),
      ]);
      final effect = Effect.failCause<int, String>(cause)
          .tapCause((value, _) => Effect.sync((_) => observed = value))
          .catchError((_, _) => Effect.succeed(42));

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<int, String>).value, 42);
      expect(observed, same(cause));
    });

    test('should let a failed success observer fail the operation', () async {
      final effect = Effect.succeed<int, String>(42).tap(
        (_, _) => Effect.fail<void, String>('observer failed'),
      );

      final cause = (await Runtime().run(effect) as Failed<int, String>).cause;

      expect((cause as Expected<String>).error, 'observer failed');
    });

    test('should capture all-expected failure in Result', () async {
      final source = Effect.failCause<int, String>(
        Sequential([const Expected('first'), const Expected('second')]),
      );

      final exit = await Runtime().run(source.result());
      final result = (exit as Succeeded<Result<int, String>, String>).value;

      expect((result as Failure<int, String>).error, 'first');
    });

    test('should capture a completed result despite interruption during cleanup', () async {
      final runtime = Runtime();
      late final Fiber<Result<int, String>, String> fiber;
      fiber = runtime.fork(
        Effect.succeed<int, String>(42)
            .ensuring(
              Effect.sync((_) {
                unawaited(fiber.interrupt('during cleanup'));
              }),
            )
            .result(),
      );

      final exit = await fiber.join();
      await runtime.close();

      final result = (exit as Succeeded<Result<int, String>, String>).value;
      expect((result as Success<int, String>).value, 42);
    });

    test('should retain a complete mixed cause in the Effect error channel', () async {
      final cause = Sequential<String>([
        const Expected('expected'),
        Defect(StateError('bad'), StackTrace.current),
      ]);
      final captured = Effect.failCause<int, String>(cause).result();

      final exit = await Runtime().run(captured);

      expect((exit as Failed<Result<int, String>, String>).cause, same(cause));
    });

    test('should be stack-safe and yield during deep composition', () async {
      var effect = Effect.succeed<int, Never>(0);
      for (var index = 0; index < 1000; index += 1) {
        effect = effect.flatMap((value, _) => Effect.succeed(value + 1));
      }
      var timerRan = false;
      Timer.run(() => timerRan = true);

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<int, Never>).value, 1000);
      expect(timerRan, isTrue);
    });
  });
}

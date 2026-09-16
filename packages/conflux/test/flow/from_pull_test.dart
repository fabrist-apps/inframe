import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Flow.fromPull', () {
    test('should acquire per consumption and pull only on demand', () async {
      var acquired = 0;
      var pulls = 0;
      final released = <int>[];
      final flow = Flow.fromPull<int, Never, int>(
        Effect.sync((_) => ++acquired),
        next: (source, _) {
          pulls++;
          return Effect.succeed(Some(source));
        },
        release: (source, _) => Effect.sync((_) => released.add(source)),
      );
      expect(acquired, 0);
      expect(pulls, 0);
      expect((await flow.runFirst().runFuture() as Some<int>).value, 1);
      expect((await flow.runFirst().runFuture() as Some<int>).value, 2);
      expect(pulls, 2);
      expect(released, [1, 2]);
    });
    test('should preserve nullable and Option-valued elements', () async {
      final nullable = Flow.fromPull<String?, Never, Iterator<String?>>(
        Effect.sync((_) => <String?>[null, 'value'].iterator),
        next: (source, _) => Effect.succeed(
          source.moveNext() ? Some(source.current) : const None(),
        ),
        release: (_, _) => Effect.succeed(null),
      );
      expect(await nullable.runCollect().runFuture(), [null, 'value']);
      final nested = Flow.fromPull<Option<String>, Never, Iterator<Option<String>>>(
        Effect.sync((_) => <Option<String>>[const None(), const Some('value')].iterator),
        next: (source, _) => Effect.succeed(
          source.moveNext() ? Some(source.current) : const None(),
        ),
        release: (_, _) => Effect.succeed(null),
      );
      final values = await nested.runCollect().runFuture();
      expect(values, hasLength(2));
      expect(values.first, isA<None>());
      expect((values.last as Some<String>).value, 'value');
    });

    test('should release on scope exit before the first pull', () async {
      var pulls = 0;
      var releases = 0;
      final flow = Flow.fromPull<int, Never, int>(
        Effect.succeed(1),
        next: (_, _) {
          pulls++;
          return Effect.succeed(const None());
        },
        release: (_, _) => Effect.sync((_) => releases++),
      );
      await Effect.build<void, Never>(($) async {
        await $(flow.open());
        expect(releases, 0);
      }).runFuture();
      expect(pulls, 0);
      expect(releases, 1);
    });

    test('should retain acquisition and consumption Context regions', () async {
      final key = ContextKey<String>('region');
      final context = Context().withBinding(key.bind('consumer'));
      final seen = <String>[];
      final flow = Flow.fromPull<int, Never, int>(
        Effect.context((context) {
          seen.add('acquire:${context.require(key)}');
          return 1;
        }),
        next: (_, context) {
          seen.add('next:${context.require(key)}');
          return Effect.succeed(const None());
        },
        release: (_, context) => Effect.sync((_) {
          seen.add('release:${context.require(key)}');
        }),
      );
      await Runtime(context: context).run(
        Effect.build<void, Never>(($) async {
          final cursor = await $(flow.open());
          await $(cursor.next().withContext(context.withBinding(key.bind('pull caller'))));
        }),
      );
      expect(seen, ['acquire:consumer', 'next:consumer', 'release:consumer']);
    });

    test('should not release another consumer after rejected acquisition', () async {
      var claimed = false;
      var releases = 0;
      final flow = Flow.fromPull<int, String, int>(
        Effect.defer((_) {
          if (claimed) return Effect.fail('already claimed');
          claimed = true;
          return Effect.succeed(1);
        }),
        next: (_, _) => Effect.succeed(const Some(1)),
        release: (_, _) => Effect.sync((_) => releases++),
      );
      await Effect.build<void, String>(($) async {
        final owner = await $(flow.open());
        final rejected = await flow.open().runFutureExit();
        expect((rejected as Failed<FlowCursor<int, String>, String>).cause.expectedErrors, [
          'already claimed',
        ]);
        expect(releases, 0);
        expect((await $(owner.next()) as Some<int>).value, 1);
      }).runFuture();
      expect(releases, 1);
    });

    test('should preserve source and release callback causes', () async {
      final cleanupError = StateError('cleanup');
      final flow = Flow.fromPull<int, String, int>(
        Effect.succeed(1),
        next: (_, _) => Effect.fail('source'),
        release: (_, _) => throw cleanupError,
      );
      final exit = await flow.runCollect().runFutureExit();
      final cause = (exit as Failed<List<int>, String>).cause;
      expect(cause, isA<Sequential<String>>());
      expect(cause.expectedErrors, ['source']);
      expect(
        (cause as Sequential<String>).causes.last,
        isA<Defect<String>>().having((cause) => cause.error, 'error', same(cleanupError)),
      );
    });

    test('should preserve next callback defects and release once', () async {
      final error = StateError('next');
      final stack = StackTrace.current;
      var releases = 0;
      final flow = Flow.fromPull<int, Never, int>(
        Effect.succeed(1),
        next: (_, _) => Error.throwWithStackTrace(error, stack),
        release: (_, _) => Effect.sync((_) => releases++),
      );
      final exit = await flow.runCollect().runFutureExit();
      final cause = (exit as Failed<List<int>, Never>).cause as Defect<Never>;
      expect(cause.error, same(error));
      expect(cause.stackTrace.toString(), stack.toString());
      expect(releases, 1);
    });

    test('should preserve cleanup defects after early termination', () async {
      final error = StateError('release');
      final flow = Flow.fromPull<int, Never, int>(
        Effect.succeed(1),
        next: (_, _) => Effect.succeed(const Some(1)),
        release: (_, _) => Effect.sync((_) => throw error),
      );
      final exit = await flow.runFirst().runFutureExit();
      expect(
        (exit as Failed<Option<int>, Never>).cause,
        isA<Defect<Never>>().having((cause) => cause.error, 'error', same(error)),
      );
    });

    test('should reject overlapping pulls and interrupt pending work', () async {
      final started = Completer<void>();
      final pending = Completer<Option<int>>();
      var pulls = 0;
      var releases = 0;
      final flow = Flow.fromPull<int, String, int>(
        Effect.succeed(1),
        next: (_, _) => Effect.tryFuture((_) {
          pulls++;
          started.complete();
          return pending.future;
        }, onError: (error, _, _) => '$error'),
        release: (_, _) => Effect.sync((_) => releases++),
      );
      final exit = await Effect.build<void, String>(($) async {
        final cursor = await $(flow.open());
        await $(Effect.all([cursor.next(), cursor.next()], concurrency: 2));
      }).runFutureExit();
      expect((exit as Failed<void, String>).cause.containsFatal, isTrue);
      expect(pulls, 1);
      expect(releases, 1);
    });

    test('should preserve interruption and cleanup defects during a pull', () async {
      final started = Completer<void>();
      final pending = Completer<Option<int>>();
      final cleanupError = StateError('cleanup');
      var releases = 0;
      final flow = Flow.fromPull<int, String, int>(
        Effect.succeed(1),
        next: (_, _) => Effect.tryFuture((_) {
          started.complete();
          return pending.future;
        }, onError: (error, _, _) => '$error'),
        release: (_, _) => Effect.sync((_) {
          releases++;
          throw cleanupError;
        }),
      );
      final fiber = Runtime().fork(flow.runCollect());
      await started.future;
      final exit = await fiber.interrupt('cancel');
      final cause = (exit as Failed<List<int>, String>).cause;
      expect(cause.containsInterruption, isTrue);
      expect(cause, isA<Sequential<String>>());
      expect(
        (cause as Sequential<String>).causes.last,
        isA<Defect<String>>().having((cause) => cause.error, 'error', same(cleanupError)),
      );
      expect(releases, 1);
    });
    test('should register release when interruption races successful acquisition', () async {
      final ready = Completer<void>();
      final gate = Completer<void>();
      var releases = 0;
      var pulls = 0;
      late Fiber<List<int>, Never> fiber;
      final acquire = Effect.build<int, Never>(($) async {
        ready.complete();
        await gate.future;
        unawaited(fiber.interrupt('acquisition handoff'));
        return 1;
      });
      final flow = Flow.fromPull<int, Never, int>(
        acquire,
        next: (_, _) {
          pulls++;
          return Effect.succeed(const Some(1));
        },
        release: (_, _) => Effect.sync((_) => releases++),
      );
      fiber = Runtime().fork(flow.runCollect());
      await ready.future;
      gate.complete();
      final exit = await fiber.exit;
      expect((exit as Failed<List<int>, Never>).cause.containsInterruption, isTrue);
      expect(pulls, 0);
      expect(releases, 1);
    });

    test('should leave partial cleanup to a failed acquisition', () async {
      var partialReleases = 0;
      var sourceReleases = 0;
      final acquire = Effect.build<int, String>(($) async {
        $.addFinalizer(Effect.sync((_) => partialReleases++));
        return $(Effect.fail('acquisition'));
      });
      final flow = Flow.fromPull<int, String, int>(
        acquire,
        next: (_, _) => Effect.succeed(const None()),
        release: (_, _) => Effect.sync((_) => sourceReleases++),
      );
      final exit = await flow.runCollect().runFutureExit();
      expect((exit as Failed<List<int>, String>).cause.expectedErrors, ['acquisition']);
      expect(partialReleases, 1);
      expect(sourceReleases, 0);
    });
  });
}

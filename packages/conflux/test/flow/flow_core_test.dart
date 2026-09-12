import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Flow', () {
    test('should read a fresh consumer Context through a sequential pipeline', () async {
      final request = ContextKey<String>('request');
      final seen = <String>[];
      final flow = Flow.defer<String, Never>(
        (context) => Flow.succeed('source:${context.require(request)}'),
      ).map((value, context) => '$value/map:${context.require(request)}');

      for (final name in ['first', 'second']) {
        final context = Context().withBinding(request.bind(name));
        await Runtime(context: context).run(
          flow.runForEach((value, callbackContext) {
            return Effect.sync(
              (_) => seen.add('$value/consumer:${callbackContext.require(request)}'),
            );
          }),
        );
      }

      expect(seen, [
        'source:first/map:first/consumer:first',
        'source:second/map:second/consumer:second',
      ]);
    });

    test('should preserve upstream and downstream Context regions', () async {
      final request = ContextKey<String>('request');
      final caller = Context().withBinding(request.bind('caller'));
      final upstream = caller.withBinding(request.bind('upstream'));
      final seen = <String>[];
      final flow =
          Flow.defer<int, Never>((context) {
                seen.add('source:${context.require(request)}');
                return Flow.succeed(1);
              })
              .mapEffect((value, context) {
                seen.add('map:${context.require(request)}');
                return Effect.context((effectContext) {
                  seen.add('effect:${effectContext.require(request)}');
                  return value + 1;
                });
              })
              .concatMap((value, context) {
                seen.add('concat:${context.require(request)}');
                return Flow.defer((innerContext) {
                  seen.add('inner:${innerContext.require(request)}');
                  return Flow.succeed(value);
                });
              })
              .scan(0, (state, value, context) {
                seen.add('scan:${context.require(request)}');
                return state + value;
              })
              .withContext(upstream)
              .map((value, context) {
                seen.add('downstream:${context.require(request)}');
                return value;
              });

      final result = await Runtime(context: caller).run(
        flow.runFold(0, (state, value, context) {
          seen.add('fold:${context.require(request)}');
          return state + value;
        }),
      );

      expect((result as Succeeded<int, Never>).value, 2);
      expect(seen, [
        'source:upstream',
        'map:upstream',
        'effect:upstream',
        'concat:upstream',
        'inner:upstream',
        'scan:upstream',
        'downstream:caller',
        'fold:caller',
      ]);
    });

    test('should be lazy and restart cold sources for every consumption', () async {
      var starts = 0;
      final flow = Flow.defer((_) {
        starts += 1;
        return Flow.fromIterable([starts]);
      });

      final first = await flow.runCollect().runFuture();
      final second = await flow.runCollect().runFuture();

      expect(first, [1]);
      expect(second, [2]);
      expect(starts, 2);
    });

    test('should collect a mapped bounded prefix and preserve null', () async {
      final values = await Flow.fromIterable<int?>([null, 2, 3, 4])
          .map((value, _) => value == null ? null : value * 2)
          .take(3)
          .runCollect()
          .runFuture();

      expect(values, [null, 4, 6]);
      expect(() => values.add(8), throwsUnsupportedError);
    });

    test('should avoid opening upstream for a zero-length prefix', () async {
      var opened = false;
      final source = Flow.defer<int, Never>((_) {
        opened = true;
        return Flow.succeed(1);
      });

      expect(await source.take(0).runCollect().runFuture(), isEmpty);
      expect(opened, isFalse);
      expect(() => source.take(-1), throwsArgumentError);
    });

    test('should preserve source failures and callback defects', () async {
      final failed = await Flow.fail<int, String>('expected').runCollect().runFutureExit();
      expect((failed as Failed<List<int>, String>).cause.expectedErrors, ['expected']);

      final defective = await Flow.defer<int, String>(
        (_) => throw StateError('factory'),
      ).runCollect().runFutureExit();
      expect((defective as Failed<List<int>, String>).cause.containsFatal, isTrue);

      final mapped = await Flow.fromIterable([1])
          .map<int>((_, _) => throw StateError('map'))
          .runCollect()
          .runFutureExit();
      expect((mapped as Failed<List<int>, Never>).cause.containsFatal, isTrue);
    });

    test('should reject overlapping pulls on one cursor', () async {
      final release = Completer<int>();
      final slow = Effect.tryFuture<int, String>(
        (_) => release.future,
        onError: (error, stackTrace, _) => '$error',
      ).asFlow();

      final exit = await Effect.build<void, String>(($) async {
        final cursor = await $(slow.open());
        await $(Effect.all([cursor.next(), cursor.next()], concurrency: 2));
      }).runFutureExit();

      expect(exit, isA<Failed<void, String>>());
      final cause = (exit as Failed<void, String>).cause;
      expect(cause.containsFatal, isTrue);
      expect(cause.containsInterruption, isFalse);
    });

    test('should close upstream after runFirst and await cleanup', () async {
      final events = <String>[];
      final source = Effect.build<int, Never>(($) async {
        await $.acquireRelease(
          Effect.sync((_) => events.add('acquire')),
          release: (_, _) => Effect.sync((_) => events.add('release')),
        );
        return 1;
      }).asFlow();

      final first = await source.runFirst().runFuture();

      expect(first, isA<Some<int>>());
      expect((first as Some<int>).value, 1);
      expect(events, ['acquire', 'release']);
      expect(await Flow.empty<int, Never>().runFirst().runFuture(), isA<None>());
    });

    test('should preserve typed Effect failures and cleanup defects', () async {
      final flow = Effect.fail<int, String>('source')
          .ensuring(Effect.sync((_) => throw StateError('cleanup')))
          .asFlow();

      final exit = await flow.runCollect().runFutureExit();

      expect(exit, isA<Failed<List<int>, String>>());
      final cause = (exit as Failed<List<int>, String>).cause;
      expect(cause, isA<Sequential<String>>());
      expect(cause.expectedErrors, ['source']);
      expect(cause.containsFatal, isTrue);
      expect(cause.containsInterruption, isFalse);
    });
  });
}

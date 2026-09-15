import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:conflux/option.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Flow selection and accumulation', () {
    test('should filter and filterMap values including present null', () async {
      final filtered = await Flow.fromIterable([1, 2, 3, 4])
          .filter((value, _) => value.isEven)
          .filterMap<int?>((value, _) => value == 2 ? const Some(null) : Some(value))
          .runCollect()
          .runFuture();

      expect(filtered, [null, 4]);
    });

    test('should select prefixes and remainders at their boundaries', () async {
      final source = Flow.fromIterable([1, 2, 3, 4]);

      expect(await source.skip(2).runCollect().runFuture(), [3, 4]);
      expect(await source.skip(10).runCollect().runFuture(), isEmpty);
      expect(await source.takeWhile((value, _) => value < 3).runCollect().runFuture(), [1, 2]);
      expect(await source.skipWhile((value, _) => value < 3).runCollect().runFuture(), [3, 4]);
      expect(
        () => source.skip(-1),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'count')
              .having((error) => error.invalidValue, 'invalidValue', -1)
              .having((error) => error.message, 'message', 'Must be at least 0, got -1.'),
        ),
      );
    });

    test('should suppress only consecutive duplicate values', () async {
      final values = await Flow.fromIterable([1, 1, 2, 1, 1])
          .distinctUntilChanged()
          .runCollect()
          .runFuture();

      expect(values, [1, 2, 1]);
    });

    test('should concatenate sources in lazy sequence', () async {
      final opened = <String>[];
      final first = Flow.defer<int, String>((_) {
        opened.add('first');
        return Flow.fromIterable([1, 2]).widenError();
      });
      final second = Flow.defer<int, String>((_) {
        opened.add('second');
        return Flow.succeed(3);
      });

      expect(await first.concat(second).runCollect().runFuture(), [1, 2, 3]);
      expect(opened, ['first', 'second']);

      var openedAfterFailure = false;
      final failed = Flow.fail<int, String>('stop').concat(
        Flow.defer((_) {
          openedAfterFailure = true;
          return Flow.succeed(4);
        }),
      );
      expect(await failed.runCollect().runFutureExit(), isA<Failed<List<int>, String>>());
      expect(openedAfterFailure, isFalse);
    });

    test('should accumulate and prefix values with fresh state per run', () async {
      final flow = Flow.fromIterable([1, 2, 3])
          .scan(0, (sum, value, _) => sum + value)
          .startWith([-1, 0]);

      expect(await flow.runCollect().runFuture(), [-1, 0, 1, 3, 6]);
      expect(await flow.runCollect().runFuture(), [-1, 0, 1, 3, 6]);
    });

    test('should invoke an empty fallback only after normal empty completion', () async {
      var fallbacks = 0;
      Flow<int, String> fallback(Context _) {
        fallbacks += 1;
        return Flow.succeed(9);
      }

      final empty = Flow.empty<int, String>().switchIfEmpty(fallback);
      final present = Flow.succeed<int, String>(1).switchIfEmpty(fallback);
      final failed = Flow.fail<int, String>('failed').switchIfEmpty(fallback);

      expect(await empty.runCollect().runFuture(), [9]);
      expect(await present.runCollect().runFuture(), [1]);
      expect(await failed.runCollect().runFutureExit(), isA<Failed<List<int>, String>>());
      expect(fallbacks, 1);
    });
  });
}

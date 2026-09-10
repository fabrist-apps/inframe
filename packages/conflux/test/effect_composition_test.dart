import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect composition', () {
    test('should transform and sequence successful values', () async {
      final effect = Effect.succeed<int, String>(2)
          .map((value) => value + 1)
          .flatMap((value) => Effect.succeed<int, String>(value * 2))
          .zipWith(Effect.succeed<String, String>('ok'), (left, right) => '$left:$right');

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<String, String>).value, '6:ok');
    });

    test('should map expected leaves without changing cause structure', () async {
      final source = Effect.failCause<int, int>(
        Sequential([const Expected(1), const Expected(2)]),
      );

      final exit = await Runtime().run(source.mapError((error) => 'e$error'));
      final causes = ((exit as Failed<int, String>).cause as Sequential<String>).causes;

      expect((causes[0] as Expected<String>).error, 'e1');
      expect((causes[1] as Expected<String>).error, 'e2');
    });

    test('should recover all-expected groups once using source order', () async {
      var recoveries = 0;
      final source = Effect.failCause<int, String>(
        Parallel([const Expected('first'), const Expected('second')]),
      );
      final effect = source.catchError((error) {
        recoveries += 1;
        return Effect.succeed<int, String>(error.length);
      });

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<int, String>).value, 5);
      expect(recoveries, 1);
    });

    test('should propagate a complete mixed cause without recovery', () async {
      var recovered = false;
      final defect = Defect<String>(StateError('bad'), StackTrace.current);
      final cause = Sequential<String>([const Expected('expected'), defect]);
      final source = Effect.failCause<int, String>(cause);

      final exit = await Runtime().run(
        source.catchError((_) {
          recovered = true;
          return Effect.succeed<int, String>(1);
        }),
      );

      expect(recovered, isFalse);
      expect((exit as Failed<int, String>).cause, same(cause));
    });

    test('should preserve the original cause before an observer defect', () async {
      final source = Effect.fail<int, String>('expected').tapCause(
        (_) => Effect.sync(() => throw StateError('observer')),
      );

      final cause = (await Runtime().run(source) as Failed<int, String>).cause;

      expect(cause, isA<Sequential<String>>());
      final causes = (cause as Sequential<String>).causes;
      expect(causes[0], isA<Expected<String>>());
      expect(causes[1], isA<Defect<String>>());
    });

    test('should capture all-expected failure in Result', () async {
      final source = Effect.failCause<int, String>(
        Sequential([const Expected('first'), const Expected('second')]),
      );

      final exit = await Runtime().run(source.result());
      final result = (exit as Succeeded<Result<int, String>, String>).value;

      expect((result as Failure<int, String>).error, 'first');
    });

    test('should be stack-safe and yield during deep composition', () async {
      var effect = Effect.succeed<int, Never>(0);
      for (var index = 0; index < 1000; index += 1) {
        effect = effect.flatMap((value) => Effect.succeed(value + 1));
      }
      var timerRan = false;
      Timer.run(() => timerRan = true);

      final exit = await Runtime().run(effect);

      expect((exit as Succeeded<int, Never>).value, 1000);
      expect(timerRan, isTrue);
    });
  });
}

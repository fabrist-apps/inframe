import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect convenience runners', () {
    test('should finish cleanup before returning a successful Exit', () async {
      var cleaned = false;
      final effect = Effect.build<int, Never>(($) {
        $.addFinalizer(Effect.sync((_) => cleaned = true));
        return 42;
      });

      final exit = await effect.runFutureExit();

      expect((exit as Succeeded<int, Never>).value, 42);
      expect(cleaned, isTrue);
    });

    test('should return a value or throw the complete EffectException', () async {
      final value = await Effect.succeed<int, String>(42).runFuture();
      final cause = Sequential<String>([
        const Expected('failed'),
        Defect(StateError('cleanup'), StackTrace.current),
      ]);

      expect(value, 42);
      await expectLater(
        Effect.failCause<int, String>(cause).runFuture(),
        throwsA(
          isA<EffectException<String>>().having(
            (exception) => exception.cause,
            'cause',
            same(cause),
          ),
        ),
      );
    });
  });

  group('Effect public surface', () {
    test('should compose conversions, filtering, flattening, and matching', () async {
      final effect =
          Effect.fromOption<int, String>(
                const Some(2),
                (_) => 'missing',
              )
              .filterOrFail((value, _) => value.isEven, (_, _) => 'odd')
              .map((value, _) => Effect.fromResult<int, String>(Success(value * 2)))
              .flatten()
              .match(
                onSuccess: (value, _) => 'value:$value',
                onFailure: (error, _) => 'error:$error',
              );

      final exit = await effect.runFutureExit();

      expect((exit as Succeeded<String, String>).value, 'value:4');
    });

    test('should evaluate Option failure factories only for None', () async {
      var calls = 0;
      final present = Effect.fromOption<int, String>(
        const Some(1),
        (_) {
          calls += 1;
          return 'missing';
        },
      );
      final absent = Effect.fromOption<int, String>(
        const None(),
        (_) {
          calls += 1;
          return 'missing';
        },
      );

      expect(calls, 0);
      await present.runFutureExit();
      expect(calls, 0);
      await absent.runFutureExit();
      expect(calls, 1);
    });

    test('should invoke success and expected-error observers on their branch', () async {
      final events = <String>[];
      await Effect.succeed<int, String>(1)
          .tap(
            (value, _) =>
                Effect.sync((_) => events.add('success:$value')).mapError((error, _) => '$error'),
          )
          .asVoid()
          .runFutureExit();
      await Effect.fail<int, String>('failed')
          .tapError((error, _) => Effect.sync((_) => events.add('failure:$error')))
          .runFutureExit();

      expect(events, ['success:1', 'failure:failed']);
    });
  });
}

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect convenience runners', () {
    test('should finish cleanup before returning a successful Exit', () async {
      var cleaned = false;
      final effect = Effect.build<int, Never>(($) {
        $.addFinalizer(Effect.sync(() => cleaned = true));
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
                () => 'missing',
              )
              .filterOrFail((value) => value.isEven, (_) => 'odd')
              .map((value) => Effect.fromResult<int, String>(Success(value * 2)))
              .flatten()
              .match(
                onSuccess: (value) => 'value:$value',
                onFailure: (error) => 'error:$error',
              );

      final exit = await effect.runFutureExit();

      expect((exit as Succeeded<String, String>).value, 'value:4');
    });

    test('should invoke success and expected-error observers on their branch', () async {
      final events = <String>[];
      await Effect.succeed<int, String>(1)
          .tap(
            (value) =>
                Effect.sync(() => events.add('success:$value')).mapError((error) => '$error'),
          )
          .asVoid()
          .runFutureExit();
      await Effect.fail<int, String>('failed')
          .tapError((error) => Effect.sync(() => events.add('failure:$error')))
          .runFutureExit();

      expect(events, ['success:1', 'failure:failed']);
    });
  });
}

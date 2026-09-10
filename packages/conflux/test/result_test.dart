import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('should transform only the selected branch', () {
      const Result<int, String> success = Success(2);
      const Result<int, String> failure = Failure('bad');
      var successCalls = 0;
      var failureCalls = 0;

      expect(success.map((value) => value * 2).getOrNull(), 4);
      expect(failure.map((value) => ++successCalls).getFailure().getOrNull(), 'bad');
      expect(success.mapError((error) => '$error!').getOrNull(), 2);
      expect(failure.mapError((error) => '$error!').getFailure().getOrNull(), 'bad!');
      expect(
        success
            .mapBoth(
              onSuccess: (value) {
                successCalls++;
                return '$value';
              },
              onFailure: (error) {
                failureCalls++;
                return error.length;
              },
            )
            .getOrNull(),
        '2',
      );
      expect(success.flatMap((value) => Success(value + 1)).getOrNull(), 3);
      expect(
        failure
            .flatMap((value) {
              successCalls++;
              return Success(value + 1);
            })
            .getFailure()
            .getOrNull(),
        'bad',
      );
      expect(
        failure
            .mapBoth(
              onSuccess: (value) {
                successCalls++;
                return '$value';
              },
              onFailure: (error) {
                failureCalls++;
                return error.length;
              },
            )
            .getFailure()
            .getOrNull(),
        3,
      );
      expect(successCalls, 1);
      expect(failureCalls, 1);
    });

    test('should recover lazily from failures', () {
      const Result<int, String> success = Success(2);
      const Result<int, String> failure = Failure('bad');
      var calls = 0;

      expect(success.getOrElse((_) => ++calls), 2);
      expect(success.orElse<int>((_) => Failure(++calls)).getOrNull(), 2);
      expect(failure.getOrElse((error) => error.length), 3);
      expect(failure.orElse<int>((error) => Failure(error.length)).getFailure().getOrNull(), 3);
      expect(calls, 0);
    });

    test('should inspect nullable branches without losing presence', () {
      const Result<String?, int?> success = Success(null);
      const Result<String?, int?> failure = Failure(null);

      expect(success.isSuccess, isTrue);
      expect(success.isFailure, isFalse);
      expect(failure.isFailure, isTrue);
      expect(success.getSuccess().isSome, isTrue);
      expect(success.getSuccess().getOrNull(), isNull);
      expect(success.getFailure(), isA<None>());
      expect(failure.getFailure().isSome, isTrue);
      expect(failure.getFailure().getOrNull(), isNull);
      expect(success.match(onSuccess: (_) => 'success', onFailure: (_) => 'failure'), 'success');
      expect(failure.match(onSuccess: (_) => 'success', onFailure: (_) => 'failure'), 'failure');
      expect(success.getOrNull(), isNull);
      expect(failure.getOrNull(), isNull);
    });

    test('should map a failure to the exact thrown object', () {
      const Result<int, String> success = Success(2);
      const Result<int, String> failure = Failure('bad');
      final exception = StateError('bad');
      var calls = 0;

      expect(success.getOrThrowWith((_) => calls++), 2);
      expect(() => failure.getOrThrowWith((_) => exception), throwsA(same(exception)));
      expect(calls, 0);
    });

    test('should filter successes and preserve existing failures', () {
      const Result<int, String> accepted = Success(2);
      const Result<int, String> rejected = Success(3);
      const Result<int, String> failure = Failure('original');
      var predicateCalls = 0;
      var failureCalls = 0;

      expect(
        accepted.filterOrFail((value) => value.isEven, (_) {
          failureCalls++;
          return 'odd';
        }),
        same(accepted),
      );
      expect(
        rejected
            .filterOrFail((value) => value.isEven, (value) {
              failureCalls++;
              return 'odd:$value';
            })
            .getFailure()
            .getOrNull(),
        'odd:3',
      );
      expect(
        failure.filterOrFail((value) => ++predicateCalls == value, (_) {
          failureCalls++;
          return 'replacement';
        }),
        same(failure),
      );
      expect(predicateCalls, 0);
      expect(failureCalls, 1);
    });

    test('should flip both variants and generic roles', () {
      const Result<int, String> success = Success(2);
      const Result<int, String> failure = Failure('bad');

      final flippedSuccess = success.flip();
      final flippedFailure = failure.flip();
      expect(flippedSuccess.getFailure().getOrNull(), 2);
      expect(flippedFailure.getOrNull(), 'bad');
    });

    test('should observe only the selected branch and retain identity', () {
      const Result<int, String> success = Success(2);
      const Result<int, String> failure = Failure('bad');
      final values = <Object>[];

      expect(success.tap(values.add), same(success));
      expect(success.tapError(values.add), same(success));
      expect(failure.tap(values.add), same(failure));
      expect(failure.tapError(values.add), same(failure));
      expect(values, [2, 'bad']);
    });

    test('should leave callback exceptions as ordinary Dart exceptions', () {
      final exception = StateError('callback failed');

      expect(
        () => const Success<int, String>(1).map<int>((_) => throw exception),
        throwsA(same(exception)),
      );
      expect(
        () => const Failure<int, String>('bad').tapError((_) => throw exception),
        throwsA(same(exception)),
      );
    });

    test('should construct a result from an option lazily', () {
      var calls = 0;
      const Option<String?> cleared = Some(null);
      const Option<String?> absent = None();

      expect(Result.fromOption(cleared, () => '${++calls}').getSuccess().isSome, isTrue);
      expect(Result.fromOption(absent, () => '${++calls}').getFailure().getOrNull(), '1');
    });

    test('should transpose every option and result combination', () {
      const Option<Result<String?, int>> absent = None();
      const Option<Result<String?, int>> success = Some(Success(null));
      const Option<Result<String?, int>> failure = Some(Failure(7));

      expect(Result.transposeOption(absent).getSuccess().getOrNull(), isA<None>());
      expect(Result.transposeOption(success).getSuccess().getOrNull()?.isSome, isTrue);
      expect(Result.transposeOption(failure).getFailure().getOrNull(), 7);
    });
  });
}

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Result collection', () {
    test('should collect every success in order', () {
      final result = Result.all<String?, String>(const [Success('first'), Success(null)]);

      expect(result.getOrNull(), ['first', null]);
      expect(() => result.getOrNull()!.add('third'), throwsUnsupportedError);
      expect(Result.all<int, String>(const []).getOrNull(), isEmpty);
    });

    test('should stop inspecting at the first failure', () {
      var inspected = 0;

      Iterable<Result<int, String>> results() sync* {
        inspected++;
        yield const Success(1);
        inspected++;
        yield const Failure('bad');
        throw StateError('inspected after failure');
      }

      expect(Result.all(results()).getFailure().getOrNull(), 'bad');
      expect(inspected, 2);
    });

    test('should validate every input and retain successful output order', () {
      final visited = <int>[];
      final result = Result.validate<int, int, String>([3, 1, 2], (input) {
        visited.add(input);
        return Success(input * 2);
      });

      expect(visited, [3, 1, 2]);
      expect(result.getOrNull(), [6, 2, 4]);
      expect(() => result.getOrNull()!.add(8), throwsUnsupportedError);
      expect(Result.validate<int, int, String>(const [], Success.new).getOrNull(), isEmpty);
    });

    test('should accumulate every expected failure in input order', () {
      final visited = <int>[];
      final result = Result.validate<int, int, String>([1, 2, 3, 4], (input) {
        visited.add(input);
        return input.isEven ? Success(input) : Failure('odd:$input');
      });

      final errors = result.getFailure().getOrNull()!;
      expect(visited, [1, 2, 3, 4]);
      expect(errors.first, 'odd:1');
      expect(errors.rest, ['odd:3']);
      expect(errors.values, ['odd:1', 'odd:3']);
      expect(result.getOrNull(), isNull);

      final single = Result.validate<int, int, String>(const [1], (_) => const Failure('only'));
      expect(single.getFailure().getOrNull()!.values, ['only']);
    });

    test('should let unexpected validator exceptions escape unchanged', () {
      final exception = StateError('validator failed');

      expect(
        () => Result.validate<int, int, String>([1], (_) => throw exception),
        throwsA(same(exception)),
      );
    });
  });

  group('NonEmptyList', () {
    test('should copy its remaining values and expose immutable lists', () {
      final source = [2, 3];
      final values = NonEmptyList(1, source);
      source.add(4);

      expect(values.first, 1);
      expect(values.rest, [2, 3]);
      expect(values.values, [1, 2, 3]);
      expect(values.toList(), [1, 2, 3]);
      expect(() => values.rest.add(4), throwsUnsupportedError);
      expect(() => values.values.add(4), throwsUnsupportedError);
    });
  });
}

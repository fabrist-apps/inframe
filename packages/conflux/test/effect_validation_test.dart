import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Effect validation', () {
    test('should return immutable successful values in input order', () async {
      final effect = Effect.validate<int, int, String>(
        [1, 2, 3],
        (value) => Effect.succeed(value * 2),
      );

      final exit = await Runtime().run(effect);
      final values = (exit as Succeeded<List<int>, NonEmptyList<String>>).value;

      expect(values, [2, 4, 6]);
      expect(() => values.add(8), throwsUnsupportedError);
    });

    test('should accumulate every expected leaf in input order', () async {
      final visited = <int>[];
      final effect = Effect.validate<int, int, String>([1, 2, 3], (value) {
        visited.add(value);
        if (value == 1) {
          return Effect.failCause(
            Parallel([const Expected('1a'), const Expected('1b')]),
          );
        }
        return value == 2 ? Effect.succeed(value) : Effect.fail('3');
      });

      final exit = await Runtime().run(effect);
      final cause = (exit as Failed<List<int>, NonEmptyList<String>>).cause;
      final errors = (cause as Expected<NonEmptyList<String>>).error;

      expect(visited, [1, 2, 3]);
      expect(errors.values, ['1a', '1b', '3']);
    });

    test('should abort on a mixed cause and preserve its structure', () async {
      final defect = Defect<String>(StateError('bad'), StackTrace.current);
      final mixed = Sequential<String>([const Expected('expected'), defect]);
      var visitedSecond = false;
      final effect = Effect.validate<int, int, String>([1, 2], (value) {
        if (value == 1) return Effect.failCause(mixed);
        visitedSecond = true;
        return Effect.succeed(value);
      });

      final exit = await Runtime().run(effect);
      final cause = (exit as Failed<List<int>, NonEmptyList<String>>).cause;

      expect(visitedSecond, isFalse);
      expect(cause, isA<Sequential<NonEmptyList<String>>>());
      final leaves = (cause as Sequential<NonEmptyList<String>>).causes;
      expect(
        (leaves[0] as Expected<NonEmptyList<String>>).error.values,
        ['expected'],
      );
      expect(leaves[1], isA<Defect<NonEmptyList<String>>>());
    });

    test('should support empty input', () async {
      final exit = await Runtime().run(
        Effect.validate<int, int, String>(const [], Effect.succeed),
      );

      expect(
        (exit as Succeeded<List<int>, NonEmptyList<String>>).value,
        isEmpty,
      );
    });
  });
}

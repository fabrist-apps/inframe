import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Option', () {
    test('should preserve absence and present nullable values', () {
      const Option<String?> absent = None();
      const Option<String?> cleared = Some(null);
      const Option<String?> supplied = Some('Bhaswanth');

      expect(absent.isNone, isTrue);
      expect(cleared.isSome, isTrue);
      expect(
        [absent, cleared, supplied].map(
          (option) => option.match(onSome: (value) => 'some:$value', onNone: () => 'none'),
        ),
        ['none', 'some:null', 'some:Bhaswanth'],
      );
      expect(absent.getOrNull(), isNull);
      expect(cleared.getOrNull(), isNull);
    });

    test('should transform only present values', () {
      var calls = 0;
      const Option<int> absent = None();
      const Option<int> present = Some(2);

      expect(absent.map((value) => calls += value), isA<None>());
      expect(calls, 0);
      expect(present.map((value) => calls += value).getOrNull(), 2);
      expect(present.flatMap((value) => Some(value * 3)).getOrNull(), 6);
      expect(calls, 2);
    });

    test('should flatten and zip typed nullable values', () {
      const Option<Option<String?>> nested = Some(Some(null));
      const Option<String> name = Some('Ada');
      const Option<int> age = Some(37);

      expect(nested.flatten().isSome, isTrue);
      expect(nested.flatten().getOrNull(), isNull);
      expect(name.zipWith(age, (left, right) => (name: left, age: right)).getOrNull(), (
        name: 'Ada',
        age: 37,
      ));
      expect(name.zipWith(const None(), (left, right) => (left, right)), isA<None>());
    });

    test('should recover only from absence', () {
      var calls = 0;
      const Option<String?> cleared = Some(null);
      const Option<String?> absent = None();

      expect(cleared.getOrElse(() => '${++calls}'), isNull);
      expect(cleared.orElse(() => Some('${++calls}')), same(cleared));
      expect(absent.getOrElse(() => '${++calls}'), '1');
      expect(absent.orElse(() => Some('${++calls}')).getOrNull(), '2');
    });

    test('should select only present values', () {
      var calls = 0;
      const Option<int> absent = None();
      const Option<int> even = Some(2);

      expect(absent.filter((value) => ++calls == value), isA<None>());
      expect(absent.exists((value) => ++calls == value), isFalse);
      expect(calls, 0);
      expect(even.filter((value) => value.isEven), same(even));
      expect(even.filter((value) => value.isOdd), isA<None>());
      expect(even.exists((value) => value.isEven), isTrue);
      expect(even.contains(2), isTrue);
      expect(even.contains(2.0), isTrue);
      expect(absent.contains(null), isFalse);
      expect(const Some<String?>(null).contains(null), isTrue);
    });

    test('should return immutable zero or one element lists', () {
      const Option<int> absent = None();
      final present = const Some<int?>(null).toList();

      expect(absent.toList(), isEmpty);
      expect(present, [null]);
      expect(() => absent.toList().add(1), throwsUnsupportedError);
      expect(() => present.add(1), throwsUnsupportedError);
    });

    test('should let callback exceptions escape unchanged', () {
      final error = StateError('callback failed');

      expect(() => const Some(1).map<int>((_) => throw error), throwsA(same(error)));
    });
  });
}

import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Option collection', () {
    test('should collect every present value in order', () {
      final result = Option.all<String?>(const [Some('first'), Some(null), Some('third')]);

      expect(result.getOrNull(), ['first', null, 'third']);
      expect(() => result.getOrNull()!.add('fourth'), throwsUnsupportedError);
      expect(Option.all<int>(const []).getOrNull(), isEmpty);
    });

    test('should stop collecting at the first absence', () {
      var inspected = 0;

      Iterable<Option<int>> options() sync* {
        inspected++;
        yield const Some(1);
        inspected++;
        yield const None();
        throw StateError('inspected after None');
      }

      expect(Option.all(options()), isA<None>());
      expect(inspected, 2);
    });

    test('should return the first present value including null', () {
      var inspected = 0;

      Iterable<Option<String?>> options() sync* {
        inspected++;
        yield const None();
        inspected++;
        yield const Some(null);
        throw StateError('inspected after Some');
      }

      final result = Option.firstSome(options());
      expect(result.isSome, isTrue);
      expect(result.getOrNull(), isNull);
      expect(inspected, 2);
      expect(Option.firstSome<int>(const []), isA<None>());
      expect(Option.firstSome<int>(const [None(), None()]), isA<None>());
    });

    test('should inspect only the first iterable element', () {
      var inspected = 0;

      Iterable<String?> values() sync* {
        inspected++;
        yield null;
        throw StateError('requested a second element');
      }

      final result = Option.fromIterable(values());
      expect(result.isSome, isTrue);
      expect(result.getOrNull(), isNull);
      expect(inspected, 1);
      expect(Option.fromIterable<int>(const []), isA<None>());
    });
  });
}

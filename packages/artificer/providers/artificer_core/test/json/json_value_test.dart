import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('JsonValues', () {
    test('should reject cycles without rejecting shared acyclic values', () {
      final cycle = <Object?>[];
      cycle.add(cycle);
      expect(() => JsonValues.validate(cycle), throwsFormatException);
      final shared = <Object?>['hello'];
      expect(() => JsonValues.validate([shared, shared]), returnsNormally);
    });
    test('should reject unsupported JSON values at the boundary', () {
      for (final value in [
        double.nan,
        double.infinity,
        {1: 'x'},
        Object(),
      ]) {
        expect(() => JsonValues.validate(value), throwsFormatException);
      }
      expect(
        () => JsonValues.validate({
          'a': [null, true, 1, 1.5, 'text'],
        }),
        returnsNormally,
      );
    });
  });
}

import 'package:chrono_id/chrono_id.dart';
import 'package:test/test.dart';

void main() {
  group('ChronoID public API', () {
    test('should expose generation and validation through the package entrypoint', () {
      final id = ChronoID.generate(prefix: 'use');

      expect(ChronoID.isValid(id, prefix: 'use'), isTrue);
    });
  });
}

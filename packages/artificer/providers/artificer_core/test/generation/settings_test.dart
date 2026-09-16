import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  group('Setting', () {
    test('should distinguish inherited, replaced and cleared values', () {
      expect(const Setting<int>.inherit().resolve(4), 4);
      expect(const Setting<int>.set(8).resolve(4), 8);
      expect(const Setting<int>.clear().resolve(4), isNull);
      final source = ['first'];
      final replacement = ['second'];
      expect(Setting.set(replacement).resolve(source), same(replacement));
      expect(source, ['first']);
    });
  });
}

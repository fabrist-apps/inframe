import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  test('raw JSON hook rejects objects and cyclic values', () {
    for (final invalid in [
      DateTime.utc(2026),
      const Usage(inputTokens: 4),
      double.infinity,
      {1: 'bad'},
    ]) {
      expect(() => const JsonValueHook().beforeEncode(invalid), throwsFormatException);
      expect(() => const JsonValueHook().beforeDecode(invalid), throwsFormatException);
    }
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(() => const JsonValueHook().beforeEncode(cycle), throwsFormatException);
    expect(() => const JsonValueHook().beforeDecode(cycle), throwsFormatException);
  });
}

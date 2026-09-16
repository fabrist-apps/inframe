import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  test('raw JSON persistence rejects objects instead of invoking registered mappers', () {
    for (final invalid in [
      DateTime.utc(2026),
      const Usage(inputTokens: 4),
      double.infinity,
      {1: 'bad'},
    ]) {
      final value = NativePayload(providerId: 'test', api: 'test', modelId: 'test', data: invalid);
      expect(value.toMap, throwsA(isA<Exception>()));
    }
    final cycle = <Object?>[];
    cycle.add(cycle);
    final value = NativePayload(providerId: 'test', api: 'test', modelId: 'test', data: cycle);
    expect(value.toJson, throwsA(isA<Exception>()));
  });
}

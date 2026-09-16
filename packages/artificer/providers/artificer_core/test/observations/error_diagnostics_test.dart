import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  test('Retry-After keeps raw values and parses seconds or HTTP dates without guessing', () {
    const seconds = ProviderError('rate limited', retryAfter: '120');
    expect(seconds.retryAfterDelay, const Duration(seconds: 120));
    expect(seconds.retryAfterDate, isNull);
    const date = ProviderError('rate limited', retryAfter: 'Wed, 21 Oct 2015 07:28:00 GMT');
    expect(date.retryAfterDate, DateTime.utc(2015, 10, 21, 7, 28));
    expect(date.retryAfterDelay, isNull);
    for (final raw in ['unknown', '-2', '1.5', '']) {
      final error = ProviderError('error', retryAfter: raw);
      expect(error.retryAfter, raw);
      expect(error.retryAfterDelay, isNull);
      expect(error.retryAfterDate, isNull);
    }
  });
}

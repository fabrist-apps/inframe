import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/metrics/series.dart';
import 'package:test/test.dart';

import 'support/moments.dart';

void main() {
  setUpAll(Chronicler.initialize);
  final maximumCount = int.parse('9223372036854775807');

  group('SumSeries', () {
    test('should reject count overflow without changing the sum', () {
      final series = SumSeries(const {})
        ..count = maximumCount
        ..sum = 4;
      expect(series.add(1), isFalse);
      expect(series.count, maximumCount);
      expect(series.sum, 4);
    });

    test('should reject nonfinite sum without incrementing count', () {
      final series = SumSeries(const {})
        ..count = 2
        ..sum = double.maxFinite;
      expect(series.add(double.maxFinite), isFalse);
      expect(series.count, 2);
      expect(series.sum, double.maxFinite);
    });
  });

  group('GaugeSeries', () {
    test('should preserve value and timestamp when count overflows', () {
      final observedAt = utcMoment(2026);
      final series = GaugeSeries(const {})
        ..count = maximumCount
        ..value = 7
        ..observedAt = observedAt;
      expect(series.set(8, () => utcMoment(2027)), isFalse);
      expect(series.count, maximumCount);
      expect(series.value, 7);
      expect(series.observedAt, observedAt);
    });
  });

  group('HistogramSeries', () {
    for (final countOverflow in [true, false]) {
      test('should reject ${countOverflow ? 'count' : 'sum'} overflow atomically', () {
        final series = HistogramSeries(const {}, 3)
          ..count = countOverflow ? maximumCount : 2
          ..sum = countOverflow ? 4 : double.maxFinite
          ..min = 1
          ..max = 4;
        series.bucketCounts.setAll(0, [series.count, 0, 0]);
        final count = series.count;
        final sum = series.sum;

        expect(series.record(countOverflow ? 5 : double.maxFinite, [10, 50]), isFalse);
        expect(series.count, count);
        expect(series.sum, sum);
        expect(series.bucketCounts, [count, 0, 0]);
        expect(series.min, 1);
        expect(series.max, 4);
      });
    }
  });
}

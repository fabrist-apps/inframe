import 'package:conflux/moment.dart';

/// Mutable interval state for one canonical attribute set.
sealed class MetricSeries {
  MetricSeries(this.attributes);

  /// Immutable dimensions validated before admission.
  final Map<String, Object?> attributes;

  /// Accepted observations in the current interval.
  int count = 0;

  /// Monotonic acceptance time retained across interval resets for eviction.
  Duration lastAccepted = Duration.zero;

  /// Clears observations while retaining dimensions and idle age.
  void reset();
}

/// Finite delta sum with an observation count.
final class SumSeries extends MetricSeries {
  /// Creates empty interval state for validated dimensions.
  SumSeries(super.attributes);

  /// Sum of accepted observations.
  double sum = 0;

  /// Rejects numeric overflow without changing the aggregate.
  bool add(double value) {
    final nextCount = count + 1;
    final nextSum = sum + value;
    if (nextCount <= count || !nextSum.isFinite) return false;
    count = nextCount;
    sum = nextSum == 0 ? 0 : nextSum;
    return true;
  }

  @override
  void reset() {
    count = 0;
    sum = 0;
  }
}

/// Latest observation and its wall-clock timestamp.
final class GaugeSeries extends MetricSeries {
  /// Creates empty interval state for validated dimensions.
  GaugeSeries(super.attributes);

  /// Most recently accepted value.
  double value = 0;

  /// Wall-clock time of the most recent accepted observation.
  Moment? observedAt;

  /// Replaces the observation unless the count overflows.
  bool set(double observation, Moment Function() now) {
    final nextCount = count + 1;
    if (nextCount <= count) return false;
    count = nextCount;
    value = observation == 0 ? 0 : observation;
    observedAt = now();
    return true;
  }

  @override
  void reset() {
    count = 0;
    value = 0;
    observedAt = null;
  }
}

/// Explicit bucket counts and distribution statistics.
final class HistogramSeries extends MetricSeries {
  /// Creates empty interval state for validated dimensions.
  HistogramSeries(super.attributes, int bucketCount) : bucketCounts = List.filled(bucketCount, 0);

  /// Per-bucket counts, including the overflow bucket.
  final List<int> bucketCounts;

  /// Sum of accepted observations.
  double sum = 0;

  /// Smallest accepted observation, absent in an empty interval.
  double? min;

  /// Largest accepted observation, absent in an empty interval.
  double? max;

  /// Rejects overflow atomically, including the selected bucket.
  bool record(double value, List<double> boundaries) {
    var bucket = boundaries.indexWhere((boundary) => value <= boundary);
    if (bucket < 0) bucket = boundaries.length;
    final nextCount = count + 1;
    final nextBucketCount = bucketCounts[bucket] + 1;
    final nextSum = sum + value;
    if (nextCount <= count || nextBucketCount <= bucketCounts[bucket] || !nextSum.isFinite) {
      return false;
    }
    count = nextCount;
    sum = nextSum == 0 ? 0 : nextSum;
    min = min == null || value < min! ? value : min;
    max = max == null || value > max! ? value : max;
    bucketCounts[bucket] = nextBucketCount;
    return true;
  }

  @override
  void reset() {
    count = 0;
    sum = 0;
    min = null;
    max = null;
    bucketCounts.fillRange(0, bucketCounts.length, 0);
  }
}

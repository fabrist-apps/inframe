import 'package:chronicler/src/metrics.dart';
import 'package:chronicler/src/metrics/series.dart';
import 'package:chronicler/src/models.dart';

/// Runtime-owned definition and admitted series for one metric name.
sealed class RegisteredInstrument {
  RegisteredInstrument({required this.name, required this.unit});

  /// Registry key and exported metric name.
  final String name;

  /// Validated unit, fixed for the life of this definition.
  final String unit;

  /// Series admitted and evicted by the aggregation registry.
  final series = <String, MetricSeries>{};

  /// Wire-level instrument kind.
  MetricInstrument get instrument;

  /// Snapshots a nonempty aggregate for the supplied interval.
  MetricPayload payload(
    MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  });
}

/// Shared delta payload construction for signed and nonnegative sums.
sealed class SumInstrument extends RegisteredInstrument {
  SumInstrument({required super.name, required super.unit});

  @override
  MetricPayload payload(
    MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  }) {
    final sum = series as SumSeries;
    return MetricPayload(
      name: name,
      instrument: instrument,
      unit: unit,
      attributes: sum.attributes,
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      durationMicros: durationMicros,
      observationCount: sum.count,
      temporality: MetricTemporality.delta,
      sum: sum.sum,
    );
  }
}

/// Registered counter definition and interval payload construction.
final class CounterInstrument extends SumInstrument {
  /// Creates the definition and its stable application handle.
  CounterInstrument({
    required super.name,
    required super.unit,
    required void Function(num, Map<String, Object?>) record,
  }) : handle = _CounterHandle(record);

  /// Stable handle returned for compatible lookups.
  final ChroniclerCounter handle;

  @override
  MetricInstrument get instrument => MetricInstrument.counter;
}

/// Registered up/down counter definition and interval payload construction.
final class UpDownCounterInstrument extends SumInstrument {
  /// Creates the definition and its stable application handle.
  UpDownCounterInstrument({
    required super.name,
    required super.unit,
    required void Function(num, Map<String, Object?>) record,
  }) : handle = _UpDownCounterHandle(record);

  /// Stable handle returned for compatible lookups.
  final ChroniclerUpDownCounter handle;

  @override
  MetricInstrument get instrument => MetricInstrument.upDownCounter;
}

/// Registered gauge definition and interval payload construction.
final class GaugeInstrument extends RegisteredInstrument {
  /// Creates the definition and its stable application handle.
  GaugeInstrument({
    required super.name,
    required super.unit,
    required void Function(num, Map<String, Object?>) record,
  }) : handle = _GaugeHandle(record);

  /// Stable handle returned for compatible lookups.
  final ChroniclerGauge handle;

  @override
  MetricInstrument get instrument => MetricInstrument.gauge;

  @override
  MetricPayload payload(
    MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  }) {
    final gauge = series as GaugeSeries;
    return MetricPayload(
      name: name,
      instrument: instrument,
      unit: unit,
      attributes: gauge.attributes,
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      durationMicros: durationMicros,
      observationCount: gauge.count,
      value: gauge.value,
      observedAt: gauge.observedAt,
    );
  }
}

/// Registered histogram definition and interval payload construction.
final class HistogramInstrument extends RegisteredInstrument {
  /// Creates a definition using validated, immutable boundaries.
  HistogramInstrument({
    required super.name,
    required super.unit,
    required this.boundaries,
    required void Function(num, Map<String, Object?>) record,
  }) : handle = _HistogramHandle(record);

  /// Strictly increasing, upper-inclusive bucket boundaries.
  final List<double> boundaries;

  /// Stable handle returned for compatible lookups.
  final ChroniclerHistogram handle;

  @override
  MetricInstrument get instrument => MetricInstrument.histogram;

  @override
  MetricPayload payload(
    MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  }) {
    final histogram = series as HistogramSeries;
    return MetricPayload(
      name: name,
      instrument: instrument,
      unit: unit,
      attributes: histogram.attributes,
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      durationMicros: durationMicros,
      observationCount: histogram.count,
      temporality: MetricTemporality.delta,
      boundaries: boundaries,
      bucketCounts: histogram.bucketCounts,
      count: histogram.count,
      sum: histogram.sum,
      min: histogram.min,
      max: histogram.max,
    );
  }
}

/// Records nonnegative changes into bounded interval aggregates.
final class _CounterHandle implements ChroniclerCounter {
  _CounterHandle(this._add);

  final void Function(num value, Map<String, Object?> attributes) _add;

  /// Adds [value] to the current interval for [attributes].
  ///
  /// Dimensions are validated and redacted before selecting a series, so
  /// sensitive values replaced by the same marker intentionally share state.
  /// Values use finite double precision and may approximate large integers.
  @override
  void add(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _add(value, attributes);
}

/// Records signed changes into bounded interval aggregates.
final class _UpDownCounterHandle implements ChroniclerUpDownCounter {
  _UpDownCounterHandle(this._add);

  final void Function(num value, Map<String, Object?> attributes) _add;

  /// Adds [value] to the current interval for [attributes].
  ///
  /// The exported sum is the signed net change during the interval. Use a
  /// gauge for an absolute current value.
  @override
  void add(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _add(value, attributes);
}

/// Records the latest current value observed during each interval.
final class _GaugeHandle implements ChroniclerGauge {
  _GaugeHandle(this._set);

  final void Function(num value, Map<String, Object?> attributes) _set;

  /// Sets the latest [value] for [attributes] in the current interval.
  ///
  /// Call this method again in every interval that should emit a value.
  @override
  void set(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _set(value, attributes);
}

/// Records distributions using explicit upper-inclusive bucket boundaries.
final class _HistogramHandle implements ChroniclerHistogram {
  _HistogramHandle(this._record);

  final void Function(num value, Map<String, Object?> attributes) _record;

  /// Records [value] in the current interval for [attributes].
  @override
  void record(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _record(value, attributes);
}

import 'dart:async';
import 'dart:convert';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/metrics.dart';
import 'package:chronicler/src/metrics/dimensions.dart';
import 'package:chronicler/src/metrics/instruments.dart';
import 'package:chronicler/src/metrics/series.dart';
import 'package:chronicler/src/models.dart';

final _instrumentName = RegExp(r'^[A-Za-z][A-Za-z0-9_.\-/]{0,254}$');

/// Registry of metric instruments owned by one Chronicler runtime.
final class MetricAggregation implements ChroniclerMetrics {
  /// Creates the registry used by the Chronicler runtime.
  ///
  /// Application code obtains this object through `context.metrics`.
  MetricAggregation({
    required this._options,
    required this._limits,
    required this._canRecord,
    required this._diagnose,
    required this._redact,
    required this._createRecord,
    required this._finalize,
    required bool startEnabled,
    required DateTime Function() now,
    required Duration Function() elapsed,
  }) : _now = now,
       _elapsed = elapsed,
       _intervalStart = now(),
       _intervalElapsed = elapsed(),
       _enabled = startEnabled {
    if (_enabled) _scheduleInterval();
  }

  final MetricOptions _options;
  final ChroniclerLimits _limits;
  final bool Function() _canRecord;
  final void Function(DiagnosticReason reason) _diagnose;
  final Map<String, Object?> Function(Map<String, Object?> attributes) _redact;
  final MetricRecord Function(MetricPayload payload) _createRecord;
  final void Function(MetricRecord record) _finalize;
  final DateTime Function() _now;
  final Duration Function() _elapsed;
  final _instruments = <String, RegisteredInstrument>{};
  late DateTime _intervalStart;
  late Duration _intervalElapsed;
  Timer? _timer;
  var _generation = 0;
  var _seriesCount = 0;
  bool _enabled;

  /// Returns a counter that records nonnegative interval changes.
  @override
  ChroniclerCounter counter(String name, {String unit = '1'}) {
    _validateDefinition(name, unit);
    final existing = _instruments[name];
    if (existing != null) {
      _requireCompatible(existing, MetricInstrument.counter, unit);
      return (existing as CounterInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final CounterInstrument instrument;
    instrument = CounterInstrument(
      name: name,
      unit: unit,
      record: (value, attributes) => _addSum(instrument, value, attributes, nonnegative: true),
    );
    _instruments[name] = instrument;
    return instrument.handle;
  }

  /// Returns an up/down counter that records signed interval changes.
  @override
  ChroniclerUpDownCounter upDownCounter(String name, {String unit = '1'}) {
    _validateDefinition(name, unit);
    final existing = _instruments[name];
    if (existing != null) {
      _requireCompatible(existing, MetricInstrument.upDownCounter, unit);
      return (existing as UpDownCounterInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final UpDownCounterInstrument instrument;
    instrument = UpDownCounterInstrument(
      name: name,
      unit: unit,
      record: (value, attributes) => _addSum(instrument, value, attributes, nonnegative: false),
    );
    _instruments[name] = instrument;
    return instrument.handle;
  }

  /// Returns a setter gauge that records the latest interval observation.
  @override
  ChroniclerGauge gauge(String name, {String unit = '1'}) {
    _validateDefinition(name, unit);
    final existing = _instruments[name];
    if (existing != null) {
      _requireCompatible(existing, MetricInstrument.gauge, unit);
      return (existing as GaugeInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final GaugeInstrument instrument;
    instrument = GaugeInstrument(
      name: name,
      unit: unit,
      record: (value, attributes) => _setGauge(instrument, value, attributes),
    );
    _instruments[name] = instrument;
    return instrument.handle;
  }

  /// Returns a histogram with explicit upper-inclusive bucket boundaries.
  @override
  ChroniclerHistogram histogram(
    String name, {
    required List<num> boundaries,
    String unit = '1',
  }) {
    _validateDefinition(name, unit);
    final normalizedBoundaries = _validateBoundaries(boundaries);
    final existing = _instruments[name];
    if (existing != null) {
      _requireCompatible(
        existing,
        MetricInstrument.histogram,
        unit,
        boundaries: normalizedBoundaries,
      );
      return (existing as HistogramInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final HistogramInstrument instrument;
    instrument = HistogramInstrument(
      name: name,
      unit: unit,
      boundaries: normalizedBoundaries,
      record: (value, attributes) => _recordHistogram(instrument, value, attributes),
    );
    _instruments[name] = instrument;
    return instrument.handle;
  }

  void _requireCompatible(
    RegisteredInstrument existing,
    MetricInstrument instrument,
    String unit, {
    List<double>? boundaries,
  }) {
    if (existing.instrument != instrument ||
        existing.unit != unit ||
        !_sameBoundaries(existing, boundaries)) {
      throw const ChroniclerConfigurationException(
        'metric instrument',
        'name is already registered with a different definition',
      );
    }
  }

  bool _sameBoundaries(RegisteredInstrument existing, List<double>? boundaries) {
    if (existing is! HistogramInstrument) return boundaries == null;
    if (boundaries == null || existing.boundaries.length != boundaries.length) return false;
    for (var index = 0; index < boundaries.length; index++) {
      if (existing.boundaries[index] != boundaries[index]) return false;
    }
    return true;
  }

  void _requireInstrumentCapacity() {
    if (_instruments.length >= _options.maxInstruments) {
      throw const ChroniclerConfigurationException(
        'maxInstruments',
        'metric instrument limit reached',
      );
    }
  }

  void _validateDefinition(String name, String unit) {
    if (!_instrumentName.hasMatch(name) || utf8.encode(name).length > _limits.maxLabelBytes) {
      throw const ChroniclerConfigurationException(
        'metric name',
        'must match the Chronicler instrument name grammar and shared label limit',
      );
    }
    final unitBytes = utf8.encode(unit);
    if (unitBytes.isEmpty ||
        unitBytes.length > 63 ||
        unitBytes.length > _limits.maxLabelBytes ||
        unit.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
      throw const ChroniclerConfigurationException(
        'metric unit',
        'must be printable ASCII within the metric and shared label limits',
      );
    }
  }

  List<double> _validateBoundaries(List<num> boundaries) {
    if (boundaries.isEmpty || boundaries.length > _options.maxHistogramBoundaries) {
      throw const ChroniclerConfigurationException(
        'histogram boundaries',
        'must be nonempty and within maxHistogramBoundaries',
      );
    }
    final normalized = <double>[];
    for (final boundary in boundaries) {
      final value = boundary.toDouble();
      if (!value.isFinite || normalized.isNotEmpty && value <= normalized.last) {
        throw const ChroniclerConfigurationException(
          'histogram boundaries',
          'must be finite and strictly increasing after double conversion',
        );
      }
      normalized.add(value == 0 ? 0 : value);
    }
    return List.unmodifiable(normalized);
  }

  void _addSum(
    SumInstrument instrument,
    num input,
    Map<String, Object?> attributes, {
    required bool nonnegative,
  }) {
    if (!_canRecord()) return;
    final value = input.toDouble();
    if (!value.isFinite || nonnegative && value < 0) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    late final Map<String, Object?> dimensions;
    try {
      dimensions = _redact(snapshotMetricDimensions(attributes, _limits, _options));
    } on Object {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    final series = _series(instrument, dimensions, SumSeries.new);
    if (series == null) return;
    if (!series.add(value)) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series.lastAccepted = _elapsed();
  }

  void _setGauge(
    GaugeInstrument instrument,
    num input,
    Map<String, Object?> attributes,
  ) {
    if (!_canRecord()) return;
    final value = input.toDouble();
    if (!value.isFinite) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    late final Map<String, Object?> dimensions;
    try {
      dimensions = _redact(snapshotMetricDimensions(attributes, _limits, _options));
    } on Object {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    final series = _series(instrument, dimensions, GaugeSeries.new);
    if (series == null) return;
    if (!series.set(value, _now)) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series.lastAccepted = _elapsed();
  }

  void _recordHistogram(
    HistogramInstrument instrument,
    num input,
    Map<String, Object?> attributes,
  ) {
    if (!_canRecord()) return;
    final value = input.toDouble();
    if (!value.isFinite) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    late final Map<String, Object?> dimensions;
    try {
      dimensions = _redact(snapshotMetricDimensions(attributes, _limits, _options));
    } on Object {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    final series = _series(
      instrument,
      dimensions,
      (attributes) => HistogramSeries(attributes, instrument.boundaries.length + 1),
    );
    if (series == null) return;
    if (!series.record(value, instrument.boundaries)) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series.lastAccepted = _elapsed();
  }

  T? _series<T extends MetricSeries>(
    RegisteredInstrument instrument,
    Map<String, Object?> dimensions,
    T Function(Map<String, Object?> attributes) create,
  ) {
    final key = metricSeriesKey(dimensions);
    final existing = instrument.series[key];
    if (existing != null) return existing as T;
    _evictExpired(_now(), _elapsed(), finalizePending: true);
    if (_seriesCount >= _options.maxSeries ||
        instrument.series.length >= _options.maxSeriesPerInstrument) {
      _diagnose(DiagnosticReason.seriesLimitReached);
      return null;
    }
    final series = create(dimensions)..lastAccepted = _elapsed();
    instrument.series[key] = series;
    _seriesCount++;
    return series;
  }

  void _scheduleInterval() {
    _timer?.cancel();
    final generation = _generation;
    _timer = Timer(_options.interval, () => _onInterval(generation));
  }

  void _onInterval(int generation) {
    if (generation != _generation) return;
    seal().forEach(_finalize);
  }

  MetricRecord? _tryCreateRecord(MetricPayload payload) {
    try {
      return _createRecord(payload);
    } on Object {
      _diagnose(DiagnosticReason.invalidRecord);
      return null;
    }
  }

  /// Seals the current partial interval and begins a fresh interval.
  List<MetricRecord> seal({bool scheduleNext = true}) {
    _timer?.cancel();
    _generation++;
    final intervalEnd = _now();
    final elapsedEnd = _elapsed();
    final durationMicros = (elapsedEnd - _intervalElapsed).inMicroseconds;
    final records = <MetricRecord>[];
    for (final instrument in _instruments.values) {
      for (final series in instrument.series.values) {
        if (series.count == 0) continue;
        final record = _tryCreateRecord(
          instrument.payload(
            series,
            intervalStart: _intervalStart,
            intervalEnd: intervalEnd,
            durationMicros: durationMicros < 0 ? 0 : durationMicros,
          ),
        );
        series.reset();
        if (record != null) records.add(record);
      }
    }
    _evictExpired(intervalEnd, elapsedEnd, finalizePending: false);
    _intervalStart = intervalEnd;
    _intervalElapsed = elapsedEnd;
    if (scheduleNext && _enabled) _scheduleInterval();
    return records;
  }

  void _evictExpired(
    DateTime intervalEnd,
    Duration elapsedEnd, {
    required bool finalizePending,
  }) {
    for (final instrument in _instruments.values.toList()) {
      final expired = instrument.series.entries
          .where((entry) => elapsedEnd - entry.value.lastAccepted >= _options.idleTimeout)
          .toList();
      for (final entry in expired) {
        final series = entry.value;
        if (finalizePending && series.count > 0) {
          final record = _tryCreateRecord(
            instrument.payload(
              series,
              intervalStart: _intervalStart,
              intervalEnd: intervalEnd,
              durationMicros: (elapsedEnd - _intervalElapsed).inMicroseconds,
            ),
          );
          if (record != null) _finalize(record);
        }
        instrument.series.remove(entry.key);
        _seriesCount--;
      }
    }
  }

  /// Discards unfinished aggregates and pauses interval scheduling.
  void disable() {
    _timer?.cancel();
    _generation++;
    _enabled = false;
    for (final instrument in _instruments.values) {
      instrument.series.clear();
    }
    _seriesCount = 0;
  }

  /// Starts a fresh empty interval while retaining instrument definitions.
  void enable() {
    _generation++;
    _enabled = true;
    _intervalStart = _now();
    _intervalElapsed = _elapsed();
    _scheduleInterval();
  }

  /// Stops interval scheduling without finalizing current measurements.
  void stop() {
    _timer?.cancel();
    _generation++;
    _enabled = false;
    _timer = null;
  }

  /// Rotates once and stops the next timer for deterministic package tests.
  void rotateForTesting() {
    seal().forEach(_finalize);
    stop();
  }

  /// Replaces an existing counter aggregate for overflow boundary tests.
  void setCounterAggregateForTesting({
    required String name,
    required Map<String, Object?> attributes,
    required int count,
    required double sum,
  }) {
    final instrument = _instruments[name];
    final dimensions = _redact(snapshotMetricDimensions(attributes, _limits, _options));
    final series = instrument?.series[metricSeriesKey(dimensions)];
    if (series is! SumSeries) throw StateError('counter series does not exist');
    series
      ..count = count
      ..sum = sum;
  }

  /// Replaces an existing series count for portable-boundary tests.
  void setSeriesCountForTesting({
    required String name,
    required Map<String, Object?> attributes,
    required int count,
  }) {
    final instrument = _instruments[name];
    final dimensions = _redact(snapshotMetricDimensions(attributes, _limits, _options));
    final series = instrument?.series[metricSeriesKey(dimensions)];
    if (series == null) throw StateError('metric series does not exist');
    series.count = count;
  }

  /// Replaces an existing histogram aggregate for atomic-overflow tests.
  void setHistogramAggregateForTesting({
    required String name,
    required Map<String, Object?> attributes,
    required int count,
    required List<int> bucketCounts,
    required double sum,
    required double min,
    required double max,
  }) {
    final instrument = _instruments[name];
    final dimensions = _redact(snapshotMetricDimensions(attributes, _limits, _options));
    final series = instrument?.series[metricSeriesKey(dimensions)];
    if (series is! HistogramSeries) throw StateError('histogram series does not exist');
    series
      ..count = count
      ..sum = sum
      ..min = min
      ..max = max;
    series.bucketCounts.setAll(0, bucketCounts);
  }
}

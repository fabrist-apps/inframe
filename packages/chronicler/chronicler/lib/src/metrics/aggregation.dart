import 'dart:async';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/metrics.dart';
import 'package:chronicler/src/metrics/dimensions.dart';
import 'package:chronicler/src/metrics/instruments.dart';
import 'package:chronicler/src/metrics/series.dart';
import 'package:chronicler/src/models.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/moment.dart';

/// Registry of metric instruments owned by one Chronicler runtime.
final class MetricAggregation implements ChroniclerMetrics {
  /// Creates the registry used by the Chronicler runtime.
  ///
  /// Application code obtains this object through `context.metrics`.
  /// Interval tasks and all time readings use the borrowed runtime.
  /// [stop] cancels this registry's task without closing the runtime.
  MetricAggregation({
    required this._options,
    required this._canRecord,
    required this._diagnose,
    required this._redact,
    required this._createRecord,
    required this._finalize,
    required bool startEnabled,
    required this._runtime,
    this._maxRecordBytes = 64 * 1024,
  }) : _enabled = startEnabled {
    _intervalStart = _runtime.clock.wallTime();
    _intervalElapsed = _runtime.clock.monotonic();
    if (_enabled) _scheduleInterval();
  }

  final MetricOptions _options;
  final int _maxRecordBytes;
  final bool Function() _canRecord;
  final void Function(DiagnosticReason reason) _diagnose;
  final Map<String, Object?> Function(Map<String, Object?> attributes) _redact;
  final MetricRecord Function(MetricPayload payload) _createRecord;
  final void Function(MetricRecord record) _finalize;
  final Runtime _runtime;
  final _instruments = <String, RegisteredInstrument<MetricSeries>>{};
  late Moment _intervalStart;
  late Duration _intervalElapsed;
  Fiber<void, Never>? _interval;
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
    RegisteredInstrument<MetricSeries> existing,
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

  bool _sameBoundaries(RegisteredInstrument<MetricSeries> existing, List<double>? boundaries) {
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
    if (name.isEmpty) {
      throw const ChroniclerConfigurationException(
        'metric name',
        'must be nonempty',
      );
    }
    if (unit.isEmpty) {
      throw const ChroniclerConfigurationException(
        'metric unit',
        'must be nonempty',
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
    final dimensions = _admitDimensions(attributes);
    if (dimensions == null) return;
    final series = _series(instrument, dimensions, SumSeries.new);
    if (series == null) return;
    if (!series.add(value)) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series.lastAccepted = _runtime.clock.monotonic();
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
    final dimensions = _admitDimensions(attributes);
    if (dimensions == null) return;
    final series = _series(instrument, dimensions, GaugeSeries.new);
    if (series == null) return;
    if (!series.set(value, _runtime.clock.wallTime)) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series.lastAccepted = _runtime.clock.monotonic();
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
    final dimensions = _admitDimensions(attributes);
    if (dimensions == null) return;
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
    series.lastAccepted = _runtime.clock.monotonic();
  }

  Map<String, Object?>? _admitDimensions(Map<String, Object?> attributes) {
    try {
      return _redact(
        snapshotMetricDimensions(attributes, _options, maxRecordBytes: _maxRecordBytes),
      );
    } on Object {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return null;
    }
  }

  T? _series<T extends MetricSeries>(
    RegisteredInstrument<T> instrument,
    Map<String, Object?> dimensions,
    T Function(Map<String, Object?> attributes) create,
  ) {
    final key = metricSeriesKey(dimensions);
    final existing = instrument.series[key];
    if (existing != null) return existing;
    _evictExpired(_runtime.clock.wallTime(), _runtime.clock.monotonic(), finalizePending: true);
    if (_seriesCount >= _options.maxSeries ||
        instrument.series.length >= _options.maxSeriesPerInstrument) {
      _diagnose(DiagnosticReason.seriesLimitReached);
      return null;
    }
    final series = create(dimensions)..lastAccepted = _runtime.clock.monotonic();
    instrument.series[key] = series;
    _seriesCount++;
    return series;
  }

  void _scheduleInterval() {
    _cancelInterval();
    final generation = _generation;
    final deadline = _runtime.clock.monotonic() + _options.interval;
    _interval = _runtime.fork(
      Effect.defer<void, Never>((_) {
        final remaining = deadline - _runtime.clock.monotonic();
        return Effect.sleep(remaining.isNegative ? Duration.zero : remaining);
      }).map((_, _) => _onInterval(generation)),
    );
  }

  void _cancelInterval() {
    final interval = _interval;
    _interval = null;
    if (interval != null) unawaited(interval.interrupt());
  }

  void _onInterval(int generation) {
    // A flush or disable invalidates callbacks before interruption settles.
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
    _cancelInterval();
    _generation++;
    final intervalEnd = _runtime.clock.wallTime();
    final elapsedEnd = _runtime.clock.monotonic();
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
    Moment intervalEnd,
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
    _cancelInterval();
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
    _intervalStart = _runtime.clock.wallTime();
    _intervalElapsed = _runtime.clock.monotonic();
    _scheduleInterval();
  }

  /// Stops interval scheduling without finalizing current measurements.
  void stop() {
    _cancelInterval();
    _generation++;
    _enabled = false;
  }
}

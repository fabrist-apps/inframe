import 'dart:async';
import 'dart:convert';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';

const _maximumPortableInteger = 9007199254740991;
final _instrumentName = RegExp(r'^[A-Za-z][A-Za-z0-9_.\-/]{0,254}$');

/// Registry of metric instruments owned by one Chronicler runtime.
final class ChroniclerMetrics {
  /// Creates the registry used by the Chronicler runtime.
  ///
  /// Application code obtains this object through `context.metrics`.
  ChroniclerMetrics.internal({
    required this._options,
    required this._limits,
    required this._canRecord,
    required this._diagnose,
    required this._redact,
    required this._createRecord,
    required this._finalize,
    required DateTime Function() now,
    required Duration Function() elapsed,
  }) : _now = now,
       _elapsed = elapsed,
       _intervalStart = now(),
       _intervalElapsed = elapsed() {
    _scheduleInterval();
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
  final _instruments = <String, _MetricInstrument>{};
  late DateTime _intervalStart;
  late Duration _intervalElapsed;
  Timer? _timer;
  var _generation = 0;
  var _seriesCount = 0;

  /// Returns a counter that records nonnegative interval changes.
  ChroniclerCounter counter(String name, {String unit = '1'}) {
    _validateDefinition(name, unit);
    final existing = _instruments[name];
    if (existing != null) {
      _requireCompatible(existing, MetricInstrument.counter, unit);
      return (existing as _CounterInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final _CounterInstrument instrument;
    final handle = ChroniclerCounter.internal(
      (value, attributes) => _addSum(instrument, value, attributes, nonnegative: true),
    );
    instrument = _CounterInstrument(name: name, unit: unit, handle: handle);
    _instruments[name] = instrument;
    return handle;
  }

  /// Returns an up/down counter that records signed interval changes.
  ChroniclerUpDownCounter upDownCounter(String name, {String unit = '1'}) {
    _validateDefinition(name, unit);
    final existing = _instruments[name];
    if (existing != null) {
      _requireCompatible(existing, MetricInstrument.upDownCounter, unit);
      return (existing as _UpDownCounterInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final _UpDownCounterInstrument instrument;
    final handle = ChroniclerUpDownCounter.internal(
      (value, attributes) => _addSum(instrument, value, attributes, nonnegative: false),
    );
    instrument = _UpDownCounterInstrument(name: name, unit: unit, handle: handle);
    _instruments[name] = instrument;
    return handle;
  }

  /// Returns a setter gauge that records the latest interval observation.
  ChroniclerGauge gauge(String name, {String unit = '1'}) {
    _validateDefinition(name, unit);
    final existing = _instruments[name];
    if (existing != null) {
      _requireCompatible(existing, MetricInstrument.gauge, unit);
      return (existing as _GaugeInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final _GaugeInstrument instrument;
    final handle = ChroniclerGauge.internal(
      (value, attributes) => _setGauge(instrument, value, attributes),
    );
    instrument = _GaugeInstrument(name: name, unit: unit, handle: handle);
    _instruments[name] = instrument;
    return handle;
  }

  /// Returns a histogram with explicit upper-inclusive bucket boundaries.
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
      return (existing as _HistogramInstrument).handle;
    }
    _requireInstrumentCapacity();
    late final _HistogramInstrument instrument;
    final handle = ChroniclerHistogram.internal(
      (value, attributes) => _recordHistogram(instrument, value, attributes),
    );
    instrument = _HistogramInstrument(
      name: name,
      unit: unit,
      boundaries: normalizedBoundaries,
      handle: handle,
    );
    _instruments[name] = instrument;
    return handle;
  }

  void _requireCompatible(
    _MetricInstrument existing,
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

  bool _sameBoundaries(_MetricInstrument existing, List<double>? boundaries) {
    if (existing is! _HistogramInstrument) return boundaries == null;
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
    if (!_instrumentName.hasMatch(name)) {
      throw const ChroniclerConfigurationException(
        'metric name',
        'must match the Chronicler instrument name grammar',
      );
    }
    final unitBytes = utf8.encode(unit);
    if (unitBytes.isEmpty ||
        unitBytes.length > 63 ||
        unit.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e)) {
      throw const ChroniclerConfigurationException(
        'metric unit',
        'must be 1 to 63 printable ASCII bytes',
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
    _SumInstrument instrument,
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
      dimensions = _redact(_snapshotDimensions(attributes));
    } on Object {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    final series = _series(instrument, dimensions, _SumSeries.new);
    if (series == null) return;
    final nextCount = series.count + 1;
    final nextSum = series.sum + value;
    if (nextCount > _maximumPortableInteger || !nextSum.isFinite) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series
      ..count = nextCount
      ..sum = nextSum == 0 ? 0 : nextSum
      ..lastAccepted = _elapsed();
  }

  void _setGauge(
    _GaugeInstrument instrument,
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
      dimensions = _redact(_snapshotDimensions(attributes));
    } on Object {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    final series = _series(instrument, dimensions, _GaugeSeries.new);
    if (series == null) return;
    final nextCount = series.count + 1;
    if (nextCount > _maximumPortableInteger) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series
      ..count = nextCount
      ..value = value == 0 ? 0 : value
      ..observedAt = _now()
      ..lastAccepted = _elapsed();
  }

  void _recordHistogram(
    _HistogramInstrument instrument,
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
      dimensions = _redact(_snapshotDimensions(attributes));
    } on Object {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    final series = _series(
      instrument,
      dimensions,
      (attributes) => _HistogramSeries(attributes, instrument.boundaries.length + 1),
    );
    if (series == null) return;
    var bucket = instrument.boundaries.indexWhere((boundary) => value <= boundary);
    if (bucket < 0) bucket = instrument.boundaries.length;
    final nextCount = series.count + 1;
    final nextBucketCount = series.bucketCounts[bucket] + 1;
    final nextSum = series.sum + value;
    if (nextCount > _maximumPortableInteger ||
        nextBucketCount > _maximumPortableInteger ||
        !nextSum.isFinite) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series
      ..count = nextCount
      ..sum = nextSum == 0 ? 0 : nextSum
      ..min = series.min == null || value < series.min! ? value : series.min
      ..max = series.max == null || value > series.max! ? value : series.max
      ..lastAccepted = _elapsed();
    series.bucketCounts[bucket] = nextBucketCount;
  }

  T? _series<T extends _MetricSeries>(
    _MetricInstrument instrument,
    Map<String, Object?> dimensions,
    T Function(Map<String, Object?> attributes) create,
  ) {
    final key = _seriesKey(dimensions);
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

  Map<String, Object?> _snapshotDimensions(Map<String, Object?> attributes) {
    if (attributes.length > _options.maxAttributes) {
      throw const RecordValidationException('metric attribute limit exceeded');
    }
    final validator = RecordValidator(_limits);
    final names = attributes.keys.toList()..sort();
    final result = <String, Object?>{};
    for (final name in names) {
      if (name.isEmpty) {
        throw const RecordValidationException('metric keys must be nonempty');
      }
      validator.validateString(name, _limits.maxKeyBytes, 'metric key');
      final value = attributes[name];
      result[name] = switch (value) {
        String() => validator.validateString(value, _limits.maxStringBytes, 'metric value'),
        bool() => value,
        int() when value >= -_maximumPortableInteger && value <= _maximumPortableInteger =>
          value.toDouble() == 0 ? 0.0 : value.toDouble(),
        double()
            when value.isFinite &&
                (value != value.truncateToDouble() || value.abs() <= _maximumPortableInteger) =>
          value == 0 ? 0.0 : value,
        _ => throw const RecordValidationException('metric values must be scalar'),
      };
    }
    return Map.unmodifiable(result);
  }

  void _scheduleInterval() {
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
    if (scheduleNext) _scheduleInterval();
    return records;
  }

  void _evictExpired(
    DateTime intervalEnd,
    Duration elapsedEnd, {
    required bool finalizePending,
  }) {
    for (final instrument in _instruments.values) {
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
    for (final instrument in _instruments.values) {
      instrument.series.clear();
    }
    _seriesCount = 0;
  }

  /// Starts a fresh empty interval while retaining instrument definitions.
  void enable() {
    _generation++;
    _intervalStart = _now();
    _intervalElapsed = _elapsed();
    _scheduleInterval();
  }

  /// Stops interval scheduling without finalizing current measurements.
  void stop() {
    _timer?.cancel();
    _generation++;
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
    final dimensions = _redact(_snapshotDimensions(attributes));
    final series = instrument?.series[_seriesKey(dimensions)];
    if (series is! _SumSeries) throw StateError('counter series does not exist');
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
    final dimensions = _redact(_snapshotDimensions(attributes));
    final series = instrument?.series[_seriesKey(dimensions)];
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
    final dimensions = _redact(_snapshotDimensions(attributes));
    final series = instrument?.series[_seriesKey(dimensions)];
    if (series is! _HistogramSeries) throw StateError('histogram series does not exist');
    series
      ..count = count
      ..sum = sum
      ..min = min
      ..max = max;
    series.bucketCounts.setAll(0, bucketCounts);
  }
}

/// Records nonnegative changes into bounded interval aggregates.
final class ChroniclerCounter {
  /// Creates a runtime-owned counter handle.
  ChroniclerCounter.internal(this._add);

  final void Function(num value, Map<String, Object?> attributes) _add;

  /// Adds [value] to the current interval for [attributes].
  ///
  /// Dimensions are validated and redacted before selecting a series, so
  /// sensitive values replaced by the same marker intentionally share state.
  /// Values use finite double precision and may approximate large integers.
  void add(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _add(value, attributes);
}

/// Records signed changes into bounded interval aggregates.
final class ChroniclerUpDownCounter {
  /// Creates a runtime-owned up/down counter handle.
  ChroniclerUpDownCounter.internal(this._add);

  final void Function(num value, Map<String, Object?> attributes) _add;

  /// Adds [value] to the current interval for [attributes].
  ///
  /// The exported sum is the signed net change during the interval. Use a
  /// gauge for an absolute current value.
  void add(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _add(value, attributes);
}

/// Records the latest current value observed during each interval.
final class ChroniclerGauge {
  /// Creates a runtime-owned setter gauge handle.
  ChroniclerGauge.internal(this._set);

  final void Function(num value, Map<String, Object?> attributes) _set;

  /// Sets the latest [value] for [attributes] in the current interval.
  ///
  /// Call this method again in every interval that should emit a value.
  void set(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _set(value, attributes);
}

/// Records distributions using explicit upper-inclusive bucket boundaries.
final class ChroniclerHistogram {
  /// Creates a runtime-owned histogram handle.
  ChroniclerHistogram.internal(this._record);

  final void Function(num value, Map<String, Object?> attributes) _record;

  /// Records [value] in the current interval for [attributes].
  void record(
    num value, {
    Map<String, Object?> attributes = const {},
  }) => _record(value, attributes);
}

sealed class _MetricInstrument {
  _MetricInstrument({required this.name, required this.unit});

  final String name;
  final String unit;
  final series = <String, _MetricSeries>{};

  MetricInstrument get instrument;

  MetricPayload payload(
    _MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  });
}

sealed class _SumInstrument extends _MetricInstrument {
  _SumInstrument({required super.name, required super.unit});

  @override
  MetricPayload payload(
    _MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  }) {
    final sum = series as _SumSeries;
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

final class _CounterInstrument extends _SumInstrument {
  _CounterInstrument({required super.name, required super.unit, required this.handle});

  final ChroniclerCounter handle;

  @override
  MetricInstrument get instrument => MetricInstrument.counter;
}

final class _UpDownCounterInstrument extends _SumInstrument {
  _UpDownCounterInstrument({required super.name, required super.unit, required this.handle});

  final ChroniclerUpDownCounter handle;

  @override
  MetricInstrument get instrument => MetricInstrument.upDownCounter;
}

final class _GaugeInstrument extends _MetricInstrument {
  _GaugeInstrument({required super.name, required super.unit, required this.handle});

  final ChroniclerGauge handle;

  @override
  MetricInstrument get instrument => MetricInstrument.gauge;

  @override
  MetricPayload payload(
    _MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  }) {
    final gauge = series as _GaugeSeries;
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

final class _HistogramInstrument extends _MetricInstrument {
  _HistogramInstrument({
    required super.name,
    required super.unit,
    required this.boundaries,
    required this.handle,
  });

  final List<double> boundaries;
  final ChroniclerHistogram handle;

  @override
  MetricInstrument get instrument => MetricInstrument.histogram;

  @override
  MetricPayload payload(
    _MetricSeries series, {
    required DateTime intervalStart,
    required DateTime intervalEnd,
    required int durationMicros,
  }) {
    final histogram = series as _HistogramSeries;
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

sealed class _MetricSeries {
  _MetricSeries(this.attributes);

  final Map<String, Object?> attributes;
  int count = 0;
  Duration lastAccepted = Duration.zero;

  void reset();
}

final class _SumSeries extends _MetricSeries {
  _SumSeries(super.attributes);

  double sum = 0;

  @override
  void reset() {
    count = 0;
    sum = 0;
  }
}

final class _GaugeSeries extends _MetricSeries {
  _GaugeSeries(super.attributes);

  double value = 0;
  DateTime? observedAt;

  @override
  void reset() {
    count = 0;
    value = 0;
    observedAt = null;
  }
}

final class _HistogramSeries extends _MetricSeries {
  _HistogramSeries(super.attributes, int bucketCount) : bucketCounts = List.filled(bucketCount, 0);

  final List<int> bucketCounts;
  double sum = 0;
  double? min;
  double? max;

  @override
  void reset() {
    count = 0;
    sum = 0;
    min = null;
    max = null;
    bucketCounts.fillRange(0, bucketCounts.length, 0);
  }
}

String _seriesKey(Map<String, Object?> attributes) => jsonEncode([
  for (final MapEntry(:key, :value) in attributes.entries)
    [
      key,
      switch (value) {
        String() => 'string',
        bool() => 'boolean',
        double() => 'number',
        _ => throw StateError('metric dimension was not canonicalized'),
      },
      value,
    ],
]);

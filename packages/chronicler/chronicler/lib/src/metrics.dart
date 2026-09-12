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
  final _instruments = <String, _CounterInstrument>{};
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
      if (existing.unit != unit) {
        throw const ChroniclerConfigurationException(
          'metric instrument',
          'name is already registered with a different definition',
        );
      }
      return existing.handle;
    }
    if (_instruments.length >= _options.maxInstruments) {
      throw const ChroniclerConfigurationException(
        'maxInstruments',
        'metric instrument limit reached',
      );
    }
    late final _CounterInstrument instrument;
    final handle = ChroniclerCounter.internal(
      (value, attributes) => _add(instrument, value, attributes),
    );
    instrument = _CounterInstrument(name: name, unit: unit, handle: handle);
    _instruments[name] = instrument;
    return handle;
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

  void _add(
    _CounterInstrument instrument,
    num input,
    Map<String, Object?> attributes,
  ) {
    if (!_canRecord()) return;
    final value = input.toDouble();
    if (!value.isFinite || value < 0) {
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
    final key = _seriesKey(dimensions);
    var series = instrument.series[key];
    if (series == null) {
      if (_seriesCount >= _options.maxSeries ||
          instrument.series.length >= _options.maxSeriesPerInstrument) {
        _diagnose(DiagnosticReason.seriesLimitReached);
        return;
      }
      series = _CounterSeries(dimensions);
      instrument.series[key] = series;
      _seriesCount++;
    }
    final nextCount = series.count + 1;
    final nextSum = series.sum + value;
    if (nextCount > _maximumPortableInteger || !nextSum.isFinite) {
      _diagnose(DiagnosticReason.invalidMeasurement);
      return;
    }
    series
      ..count = nextCount
      ..sum = nextSum == 0 ? 0 : nextSum;
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
        records.add(
          _createRecord(
            MetricPayload(
              name: instrument.name,
              instrument: MetricInstrument.counter,
              unit: instrument.unit,
              attributes: series.attributes,
              intervalStart: _intervalStart,
              intervalEnd: intervalEnd,
              durationMicros: durationMicros < 0 ? 0 : durationMicros,
              observationCount: series.count,
              temporality: MetricTemporality.delta,
              sum: series.sum,
            ),
          ),
        );
        series
          ..count = 0
          ..sum = 0;
      }
    }
    _intervalStart = intervalEnd;
    _intervalElapsed = elapsedEnd;
    if (scheduleNext) _scheduleInterval();
    return records;
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
    if (series == null) throw StateError('counter series does not exist');
    series
      ..count = count
      ..sum = sum;
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

final class _CounterInstrument {
  _CounterInstrument({required this.name, required this.unit, required this.handle});

  final String name;
  final String unit;
  final ChroniclerCounter handle;
  final series = <String, _CounterSeries>{};
}

final class _CounterSeries {
  _CounterSeries(this.attributes);

  final Map<String, Object?> attributes;
  int count = 0;
  double sum = 0;
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

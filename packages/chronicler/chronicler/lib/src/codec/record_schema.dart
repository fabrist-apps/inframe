import 'package:chronicler/src/codec/results.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chrono_id/chrono_id.dart';

/// Enforces the version-one model contract for both encoding and decoding.
final class RecordSchema {
  /// Creates schema validation with field, dimension, and snapshot limits.
  const RecordSchema({
    required this._limits,
    required this._metricOptions,
    required this._maxRecordBytes,
  });

  final ChroniclerLimits _limits;
  final MetricOptions _metricOptions;
  final int _maxRecordBytes;

  RecordValidator get _recordValidator =>
      RecordValidator(_limits, maxSnapshotBytes: _maxRecordBytes);

  /// Whether a trace ID is nonzero lowercase hexadecimal with 128 bits.
  bool isTraceId(String value) => _traceId.hasMatch(value);

  /// Whether a span ID is nonzero lowercase hexadecimal with 64 bits.
  bool isSpanId(String value) => _spanId.hasMatch(value);

  /// Validates record envelopes and signal payload contracts.
  void validate(ChroniclerRecord record) {
    final envelope = record.envelope;
    if (!ChronoID.isValid(envelope.eventId, prefix: 'evt')) {
      throw const ChroniclerEncodingException('eventId is invalid');
    }
    _validateModelString(envelope.eventId, _limits.maxIdBytes, allowEmpty: false);
    _validateModelString(envelope.appId, _limits.maxIdBytes, allowEmpty: false);
    _validateModelString(envelope.release, _limits.maxLabelBytes, allowEmpty: false);
    if (envelope.buildId case final value?) {
      _validateModelString(value, _limits.maxLabelBytes, allowEmpty: false);
    }
    for (final value in [envelope.userId, envelope.anonymousId, envelope.sessionId]) {
      if (value != null) _validateModelString(value, _limits.maxIdBytes, allowEmpty: false);
    }
    _validateTimestampForEncoding(envelope.timestamp);
    for (final value in [envelope.traceId, envelope.spanId, envelope.parentSpanId]) {
      if (value != null) _validateModelString(value, _limits.maxIdBytes, allowEmpty: false);
    }
    if ((envelope.traceId == null) != (envelope.spanId == null) ||
        envelope.traceId != null && !isTraceId(envelope.traceId!) ||
        envelope.spanId != null && !isSpanId(envelope.spanId!)) {
      throw const ChroniclerEncodingException('trace correlation is invalid');
    }
    if (envelope.parentSpanId != null &&
        (record is! SpanRecord || !isSpanId(envelope.parentSpanId!))) {
      throw const ChroniclerEncodingException('parent span is invalid');
    }
    switch (record) {
      case LogRecord():
        _validateModelString(record.payload.message, _limits.maxStringBytes, allowEmpty: true);
        _recordValidator.snapshotAttributes(record.payload.attributes);
        if (record.payload.error != null && record.payload.stackTrace != null) {
          throw const ChroniclerEncodingException('log has duplicate stack locations');
        }
        if (record.payload.error case final error?) _validateErrorDetails(error);
        if (record.payload.stackTrace case final stack?) {
          _validateModelString(stack, _limits.maxStackTraceBytes, allowEmpty: true);
        }
      case ProductEventRecord():
        _validateLabelAndAttributes(record.payload.name, record.payload.properties);
      case IdentityLinkRecord():
        _validateModelString(record.payload.anonymousId, _limits.maxIdBytes, allowEmpty: false);
        _validateModelString(record.payload.userId, _limits.maxIdBytes, allowEmpty: false);
      case UserPropertiesSetRecord():
        _validateModelString(record.payload.userId, _limits.maxIdBytes, allowEmpty: false);
        if (record.payload.properties.isEmpty) {
          throw const ChroniclerEncodingException('properties must be nonempty');
        }
        _recordValidator.snapshotAttributes(record.payload.properties);
      case UserPropertiesUnsetRecord():
        _validateModelString(record.payload.userId, _limits.maxIdBytes, allowEmpty: false);
        if (record.payload.keys.isEmpty ||
            record.payload.keys.length > _limits.maxListItems ||
            record.payload.keys.toSet().length != record.payload.keys.length) {
          throw const ChroniclerEncodingException(
            'property keys must be nonempty, distinct, and within the list limit',
          );
        }
        for (final key in record.payload.keys) {
          _validateModelString(key, _limits.maxKeyBytes, allowEmpty: false);
        }
      case SpanRecord():
        if (envelope.traceId == null) {
          throw const ChroniclerEncodingException('span needs trace IDs');
        }
        _validateLabelAndAttributes(record.payload.name, record.payload.attributes);
        _validatePortableInt(record.payload.durationMicros);
      case ErrorRecord():
        _validateErrorDetails(record.payload.error);
        if (record.payload.causes.length > _limits.maxCauses) {
          throw const ChroniclerEncodingException('too many causes');
        }
        record.payload.causes.forEach(_validateErrorDetails);
        _recordValidator.snapshotAttributes(record.payload.attributes);
      case MetricRecord():
        if (envelope.userId != null ||
            envelope.anonymousId != null ||
            envelope.sessionId != null ||
            envelope.traceId != null) {
          throw const ChroniclerEncodingException('metric envelope has correlation');
        }
        validateMetric(record.payload);
        if (record.envelope.timestamp.toUtc() != record.payload.intervalEnd.toUtc()) {
          throw const ChroniclerEncodingException('metric timestamp must equal interval end');
        }
    }
  }

  /// Validates instrument-specific metric payload fields.
  void validateMetric(MetricPayload payload) {
    _validateModelString(payload.name, _limits.maxLabelBytes, allowEmpty: false);
    _validateModelString(payload.unit, _limits.maxLabelBytes, allowEmpty: false);
    _recordValidator.snapshotMetricAttributes(
      payload.attributes,
      maxAttributes: _metricOptions.maxAttributes,
    );
    _validatePortableInt(payload.durationMicros);
    _validatePortableInt(payload.observationCount);
    _validateTimestampForEncoding(payload.intervalStart);
    _validateTimestampForEncoding(payload.intervalEnd);
    if (payload.observedAt case final observedAt?) {
      _validateTimestampForEncoding(observedAt);
    }
    if (payload.observationCount == 0) {
      throw const ChroniclerEncodingException('metric observationCount must be positive');
    }
    switch (payload.instrument) {
      case MetricInstrument.counter || MetricInstrument.upDownCounter:
        if (payload.temporality != MetricTemporality.delta ||
            payload.sum == null ||
            !payload.sum!.isFinite ||
            payload.instrument == MetricInstrument.counter && payload.sum! < 0 ||
            payload.boundaries != null ||
            payload.bucketCounts != null ||
            payload.count != null ||
            payload.min != null ||
            payload.max != null ||
            payload.value != null ||
            payload.observedAt != null) {
          throw const ChroniclerEncodingException('sum metric payload is invalid');
        }
      case MetricInstrument.histogram:
        final boundaries = payload.boundaries;
        final buckets = payload.bucketCounts;
        if (payload.temporality != MetricTemporality.delta ||
            boundaries == null ||
            boundaries.isEmpty ||
            boundaries.length > _metricOptions.maxHistogramBoundaries ||
            buckets == null ||
            buckets.length != boundaries.length + 1 ||
            payload.count == null ||
            payload.count != payload.observationCount ||
            buckets.fold(0, (sum, value) => sum + value) != payload.count ||
            payload.sum == null ||
            payload.min == null ||
            payload.max == null ||
            !payload.sum!.isFinite ||
            !payload.min!.isFinite ||
            !payload.max!.isFinite ||
            payload.min! > payload.max! ||
            !_strictlyIncreasing(boundaries) ||
            buckets.any((value) => value < 0 || value > 9007199254740991) ||
            payload.value != null ||
            payload.observedAt != null) {
          throw const ChroniclerEncodingException('histogram payload is invalid');
        }
      case MetricInstrument.gauge:
        if (payload.temporality != null ||
            payload.value == null ||
            !payload.value!.isFinite ||
            payload.observedAt == null ||
            payload.sum != null ||
            payload.boundaries != null ||
            payload.bucketCounts != null ||
            payload.count != null ||
            payload.min != null ||
            payload.max != null) {
          throw const ChroniclerEncodingException('gauge payload is invalid');
        }
    }
  }

  bool _strictlyIncreasing(List<double> values) {
    for (var index = 0; index < values.length; index++) {
      if (!values[index].isFinite || index > 0 && values[index - 1] >= values[index]) return false;
    }
    return true;
  }

  void _validateLabelAndAttributes(String label, Map<String, Object?> attributes) {
    _validateModelString(label, _limits.maxLabelBytes, allowEmpty: false);
    _recordValidator.snapshotAttributes(attributes);
  }

  void _validateErrorDetails(ErrorDetails error) {
    _validateModelString(error.type, _limits.maxLabelBytes, allowEmpty: false);
    _validateModelString(error.message, _limits.maxErrorMessageBytes, allowEmpty: true);
    if (error.stackTrace case final stack?) {
      _validateModelString(stack, _limits.maxStackTraceBytes, allowEmpty: true);
    }
  }

  void _validateModelString(String value, int maxBytes, {required bool allowEmpty}) {
    if (!allowEmpty && value.isEmpty) throw const ChroniclerEncodingException('string is empty');
    try {
      _recordValidator.validateString(value, maxBytes, 'string');
    } on RecordValidationException catch (failure) {
      throw ChroniclerEncodingException(failure.reason);
    }
  }

  void _validatePortableInt(int value) {
    if (value < 0 || value > 9007199254740991) {
      throw const ChroniclerEncodingException('integer is outside the portable range');
    }
  }

  void _validateTimestampForEncoding(DateTime value) {
    final utc = value.toUtc();
    if (utc.year < 1 || utc.year > 9999) {
      throw const ChroniclerEncodingException('timestamp year is outside the supported range');
    }
  }

  static final _traceId = RegExp(r'^(?!0{32}$)[0-9a-f]{32}$');
  static final _spanId = RegExp(r'^(?!0{16}$)[0-9a-f]{16}$');
}

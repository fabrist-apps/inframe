import 'dart:convert';
import 'dart:typed_data';

import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chrono_id/chrono_id.dart';

final class ChroniclerEncodingException implements Exception {
  const ChroniclerEncodingException(this.reason);
  final String reason;
}

sealed class DecodeResult<T> {
  const DecodeResult();
}

final class Decoded<T> extends DecodeResult<T> {
  const Decoded(this.value);
  final T value;
}

final class DecodeFailure<T> extends DecodeResult<T> {
  const DecodeFailure(this.reason);
  final DecodeFailureReason reason;
}

enum DecodeFailureReason {
  invalidUtf8,
  invalidJson,
  unsupportedVersion,
  unknownKind,
  invalidField,
  limitExceeded,
}

/// Canonical compact UTF-8 JSON codec for version-one records and batches.
final class ChroniclerCodec {
  const ChroniclerCodec({
    this.limits = const ChroniclerLimits(),
    this.maxRecordBytes = 64 * 1024,
    this.maxBatchBytes = 512 * 1024,
    this.maxBatchRecords = 100,
  });

  final ChroniclerLimits limits;
  final int maxRecordBytes;
  final int maxBatchBytes;
  final int maxBatchRecords;

  RecordValidator get _recordValidator => RecordValidator(limits, maxSnapshotBytes: maxRecordBytes);

  /// Validates record fields without applying the complete encoded-record limit.
  void validateRecord(ChroniclerRecord record) {
    try {
      _validateRecord(record);
    } on ChroniclerEncodingException {
      rethrow;
    } on Object {
      throw const ChroniclerEncodingException('record is invalid');
    }
  }

  Uint8List encodeRecord(ChroniclerRecord record) {
    try {
      validateRecord(record);
      final encoded = _encodeObject(_recordMap(record));
      if (encoded.length > maxRecordBytes) {
        throw const ChroniclerEncodingException('record byte limit exceeded');
      }
      return encoded;
    } on ChroniclerEncodingException {
      rethrow;
    } on Object {
      throw const ChroniclerEncodingException('record is invalid');
    }
  }

  Uint8List encodeBatch(ChroniclerBatch batch) {
    if (batch.records.isEmpty || batch.records.length > maxBatchRecords) {
      throw const ChroniclerEncodingException('batch record count is invalid');
    }
    final recordMaps = batch.records
        .map((record) {
          validateRecord(record);
          final map = _recordMap(record);
          if (_encodeObject(map).length > maxRecordBytes) {
            throw const ChroniclerEncodingException('record byte limit exceeded');
          }
          return map;
        })
        .toList(growable: false);
    final encoded = _encodeObject({
      'schemaVersion': 1,
      'records': recordMaps,
    });
    if (encoded.length > maxBatchBytes) {
      throw const ChroniclerEncodingException('batch byte limit exceeded');
    }
    return encoded;
  }

  DecodeResult<ChroniclerRecord> decodeRecord(Uint8List bytes) {
    if (bytes.length > maxRecordBytes) {
      return const DecodeFailure(DecodeFailureReason.limitExceeded);
    }
    final parsed = _parse(bytes);
    if (parsed case final DecodeFailure<Object?> failure) return DecodeFailure(failure.reason);
    try {
      return Decoded(_decodeRecordMap(_map((parsed as Decoded<Object?>).value)));
    } on _CodecFailure catch (failure) {
      return DecodeFailure(failure.reason);
    } on RecordValidationException catch (failure) {
      return DecodeFailure(_validationFailure(failure));
    } on Object {
      return const DecodeFailure(DecodeFailureReason.invalidField);
    }
  }

  DecodeResult<ChroniclerBatch> decodeBatch(Uint8List bytes) {
    if (bytes.length > maxBatchBytes) {
      return const DecodeFailure(DecodeFailureReason.limitExceeded);
    }
    final parsed = _parse(bytes);
    if (parsed case final DecodeFailure<Object?> failure) return DecodeFailure(failure.reason);
    try {
      final map = _map((parsed as Decoded<Object?>).value);
      _version(map);
      final rawRecords = map['records'];
      if (rawRecords is! List<Object?> || rawRecords.length > maxBatchRecords) {
        throw const _CodecFailure(DecodeFailureReason.invalidField);
      }
      final records = <ChroniclerRecord>[];
      for (final raw in rawRecords) {
        final recordMap = _map(raw);
        if (_encodeObject(recordMap).length > maxRecordBytes) {
          throw const _CodecFailure(DecodeFailureReason.limitExceeded);
        }
        records.add(_decodeRecordMap(recordMap));
      }
      return Decoded(ChroniclerBatch(records));
    } on _CodecFailure catch (failure) {
      return DecodeFailure(failure.reason);
    } on RecordValidationException catch (failure) {
      return DecodeFailure(_validationFailure(failure));
    } on Object {
      return const DecodeFailure(DecodeFailureReason.invalidField);
    }
  }

  DecodeFailureReason _validationFailure(RecordValidationException failure) =>
      failure.reason.contains('limit')
      ? DecodeFailureReason.limitExceeded
      : DecodeFailureReason.invalidField;

  DecodeResult<Object?> _parse(Uint8List bytes) {
    late final String text;
    try {
      text = const Utf8Decoder().convert(bytes);
    } on FormatException {
      return const DecodeFailure(DecodeFailureReason.invalidUtf8);
    }
    try {
      return Decoded(jsonDecode(text));
    } on FormatException {
      return const DecodeFailure(DecodeFailureReason.invalidJson);
    }
  }

  ChroniclerRecord _decodeRecordMap(Map<String, Object?> map) {
    _version(map);
    final kind = _string(map, 'kind', limits.maxLabelBytes);
    if (!_knownKinds.contains(kind)) {
      throw const _CodecFailure(DecodeFailureReason.unknownKind);
    }
    final envelope = _decodeEnvelope(map, kind);
    final payload = _map(map['payload']);
    final record = switch (kind) {
      'log' => LogRecord(envelope: envelope, payload: _decodeLog(payload)),
      'event' => ProductEventRecord(
        envelope: envelope,
        payload: ProductEventPayload(
          name: _label(payload, 'name'),
          properties: _attributes(payload, 'properties'),
        ),
      ),
      'identity_link' => IdentityLinkRecord(
        envelope: envelope,
        payload: IdentityLinkPayload(
          anonymousId: _id(payload, 'anonymousId'),
          userId: _id(payload, 'userId'),
        ),
      ),
      'user_properties_set' => UserPropertiesSetRecord(
        envelope: envelope,
        payload: UserPropertiesSetPayload(
          userId: _id(payload, 'userId'),
          properties: _nonemptyAttributes(payload, 'properties'),
        ),
      ),
      'user_properties_unset' => UserPropertiesUnsetRecord(
        envelope: envelope,
        payload: UserPropertiesUnsetPayload(
          userId: _id(payload, 'userId'),
          keys: _propertyKeys(payload),
        ),
      ),
      'span' => SpanRecord(envelope: envelope, payload: _decodeSpan(payload)),
      'error' => ErrorRecord(envelope: envelope, payload: _decodeError(payload)),
      'metric' => MetricRecord(envelope: envelope, payload: _decodeMetric(payload)),
      _ => throw const _CodecFailure(DecodeFailureReason.unknownKind),
    };
    _validateRecord(record);
    return record;
  }

  RecordEnvelope _decodeEnvelope(Map<String, Object?> map, String kind) {
    final eventId = _string(map, 'eventId', limits.maxIdBytes);
    if (!ChronoID.isValid(eventId, prefix: 'evt')) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final traceId = _optionalString(map, 'traceId', limits.maxIdBytes);
    final spanId = _optionalString(map, 'spanId', limits.maxIdBytes);
    if ((traceId == null) != (spanId == null) ||
        traceId != null && !_traceId.hasMatch(traceId) ||
        spanId != null && !_spanId.hasMatch(spanId)) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final parentSpanId = _optionalString(map, 'parentSpanId', limits.maxIdBytes);
    if (parentSpanId != null && (kind != 'span' || !_spanId.hasMatch(parentSpanId))) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    if (kind == 'span' && traceId == null || kind == 'metric' && traceId != null) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final source = switch (_string(map, 'source', limits.maxLabelBytes)) {
      'client' => ChroniclerSource.client,
      'server' => ChroniclerSource.server,
      _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
    };
    final envelope = RecordEnvelope(
      eventId: eventId,
      appId: _id(map, 'appId'),
      release: _label(map, 'release'),
      source: source,
      timestamp: _timestamp(map, 'timestamp'),
      buildId: _optionalLabel(map, 'buildId'),
      userId: _optionalId(map, 'userId'),
      anonymousId: _optionalId(map, 'anonymousId'),
      sessionId: _optionalId(map, 'sessionId'),
      traceId: traceId,
      spanId: spanId,
      parentSpanId: parentSpanId,
    );
    if (kind == 'metric' &&
        (envelope.userId != null || envelope.anonymousId != null || envelope.sessionId != null)) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    return envelope;
  }

  LogPayload _decodeLog(Map<String, Object?> map) {
    final severity = switch (_string(map, 'severity', limits.maxLabelBytes)) {
      'debug' => LogSeverity.debug,
      'info' => LogSeverity.info,
      'warning' => LogSeverity.warning,
      'error' => LogSeverity.error,
      _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
    };
    final errorValue = map['error'];
    final error = errorValue == null ? null : _decodeErrorDetails(_map(errorValue));
    final stack = _optionalString(map, 'stackTrace', limits.maxStackTraceBytes, allowEmpty: true);
    if (error != null && stack != null) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    return LogPayload(
      severity: severity,
      message: _string(map, 'message', limits.maxStringBytes, allowEmpty: true),
      attributes: _attributes(map, 'attributes'),
      error: error,
      stackTrace: stack,
    );
  }

  SpanPayload _decodeSpan(Map<String, Object?> map) => SpanPayload(
    name: _label(map, 'name'),
    spanKind: switch (_string(map, 'spanKind', limits.maxLabelBytes)) {
      'internal' => SpanKind.internal,
      'server' => SpanKind.server,
      'client' => SpanKind.client,
      'producer' => SpanKind.producer,
      'consumer' => SpanKind.consumer,
      _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
    },
    status: switch (_string(map, 'status', limits.maxLabelBytes)) {
      'success' => SpanStatus.success,
      'error' => SpanStatus.error,
      'cancelled' => SpanStatus.cancelled,
      _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
    },
    durationMicros: _portableInt(map, 'durationMicros'),
    attributes: _attributes(map, 'attributes'),
  );

  ErrorPayload _decodeError(Map<String, Object?> map) {
    final causesValue = map['causes'];
    if (causesValue is! List<Object?> || causesValue.length > limits.maxCauses) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final handled = map['handled'];
    if (handled is! bool) throw const _CodecFailure(DecodeFailureReason.invalidField);
    return ErrorPayload(
      error: _decodeErrorDetails(_map(map['error'])),
      handled: handled,
      causes: causesValue.map((cause) => _decodeErrorDetails(_map(cause))),
      attributes: _attributes(map, 'attributes'),
    );
  }

  ErrorDetails _decodeErrorDetails(Map<String, Object?> map) => ErrorDetails(
    type: _string(map, 'type', limits.maxLabelBytes),
    message: _string(map, 'message', limits.maxErrorMessageBytes, allowEmpty: true),
    stackTrace: _optionalString(map, 'stackTrace', limits.maxStackTraceBytes, allowEmpty: true),
  );

  MetricPayload _decodeMetric(Map<String, Object?> map) {
    final instrument = switch (_string(map, 'instrument', limits.maxLabelBytes)) {
      'counter' => MetricInstrument.counter,
      'up_down_counter' => MetricInstrument.upDownCounter,
      'histogram' => MetricInstrument.histogram,
      'gauge' => MetricInstrument.gauge,
      _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
    };
    final payload = MetricPayload(
      name: _label(map, 'name'),
      instrument: instrument,
      unit: _label(map, 'unit'),
      attributes: _attributes(map, 'attributes'),
      intervalStart: _timestamp(map, 'intervalStart'),
      intervalEnd: _timestamp(map, 'intervalEnd'),
      durationMicros: _portableInt(map, 'durationMicros'),
      observationCount: _portableInt(map, 'observationCount'),
      temporality: map['temporality'] == null
          ? null
          : switch (_string(map, 'temporality', limits.maxLabelBytes)) {
              'delta' => MetricTemporality.delta,
              _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
            },
      sum: _optionalFiniteDouble(map, 'sum'),
      boundaries: _optionalDoubleList(map, 'boundaries'),
      bucketCounts: _optionalIntList(map, 'bucketCounts'),
      count: _optionalPortableInt(map, 'count'),
      min: _optionalFiniteDouble(map, 'min'),
      max: _optionalFiniteDouble(map, 'max'),
      value: _optionalFiniteDouble(map, 'value'),
      observedAt: map['observedAt'] == null ? null : _timestamp(map, 'observedAt'),
    );
    _validateMetric(payload);
    return payload;
  }

  void _validateRecord(ChroniclerRecord record) {
    final envelope = record.envelope;
    if (!ChronoID.isValid(envelope.eventId, prefix: 'evt')) {
      throw const ChroniclerEncodingException('eventId is invalid');
    }
    _validateModelString(envelope.eventId, limits.maxIdBytes, allowEmpty: false);
    _validateModelString(envelope.appId, limits.maxIdBytes, allowEmpty: false);
    _validateModelString(envelope.release, limits.maxLabelBytes, allowEmpty: false);
    if (envelope.buildId case final value?) {
      _validateModelString(value, limits.maxLabelBytes, allowEmpty: false);
    }
    for (final value in [envelope.userId, envelope.anonymousId, envelope.sessionId]) {
      if (value != null) _validateModelString(value, limits.maxIdBytes, allowEmpty: false);
    }
    _validateTimestampForEncoding(envelope.timestamp);
    for (final value in [envelope.traceId, envelope.spanId, envelope.parentSpanId]) {
      if (value != null) _validateModelString(value, limits.maxIdBytes, allowEmpty: false);
    }
    if ((envelope.traceId == null) != (envelope.spanId == null) ||
        envelope.traceId != null && !_traceId.hasMatch(envelope.traceId!) ||
        envelope.spanId != null && !_spanId.hasMatch(envelope.spanId!)) {
      throw const ChroniclerEncodingException('trace correlation is invalid');
    }
    if (envelope.parentSpanId != null &&
        (record is! SpanRecord || !_spanId.hasMatch(envelope.parentSpanId!))) {
      throw const ChroniclerEncodingException('parent span is invalid');
    }
    switch (record) {
      case LogRecord():
        _validateModelString(record.payload.message, limits.maxStringBytes, allowEmpty: true);
        _recordValidator.snapshotAttributes(record.payload.attributes);
        if (record.payload.error != null && record.payload.stackTrace != null) {
          throw const ChroniclerEncodingException('log has duplicate stack locations');
        }
        if (record.payload.error case final error?) _validateErrorDetails(error);
        if (record.payload.stackTrace case final stack?) {
          _validateModelString(stack, limits.maxStackTraceBytes, allowEmpty: true);
        }
      case ProductEventRecord():
        _validateLabelAndAttributes(record.payload.name, record.payload.properties);
      case IdentityLinkRecord():
        _validateModelString(record.payload.anonymousId, limits.maxIdBytes, allowEmpty: false);
        _validateModelString(record.payload.userId, limits.maxIdBytes, allowEmpty: false);
      case UserPropertiesSetRecord():
        _validateModelString(record.payload.userId, limits.maxIdBytes, allowEmpty: false);
        if (record.payload.properties.isEmpty) {
          throw const ChroniclerEncodingException('properties must be nonempty');
        }
        _recordValidator.snapshotAttributes(record.payload.properties);
      case UserPropertiesUnsetRecord():
        _validateModelString(record.payload.userId, limits.maxIdBytes, allowEmpty: false);
        if (record.payload.keys.isEmpty ||
            record.payload.keys.toSet().length != record.payload.keys.length) {
          throw const ChroniclerEncodingException('property keys must be nonempty and distinct');
        }
        for (final key in record.payload.keys) {
          _validateModelString(key, limits.maxKeyBytes, allowEmpty: false);
        }
      case SpanRecord():
        if (envelope.traceId == null) {
          throw const ChroniclerEncodingException('span needs trace IDs');
        }
        _validateLabelAndAttributes(record.payload.name, record.payload.attributes);
        _validatePortableInt(record.payload.durationMicros);
      case ErrorRecord():
        _validateErrorDetails(record.payload.error);
        if (record.payload.causes.length > limits.maxCauses) {
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
        _validateMetric(record.payload);
        if (record.envelope.timestamp.toUtc() != record.payload.intervalEnd.toUtc()) {
          throw const ChroniclerEncodingException('metric timestamp must equal interval end');
        }
    }
  }

  void _validateMetric(MetricPayload payload) {
    _validateModelString(payload.name, limits.maxLabelBytes, allowEmpty: false);
    _validateModelString(payload.unit, limits.maxLabelBytes, allowEmpty: false);
    _recordValidator.snapshotAttributes(payload.attributes);
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
            buckets.any((value) => value < 0) ||
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
    _validateModelString(label, limits.maxLabelBytes, allowEmpty: false);
    _recordValidator.snapshotAttributes(attributes);
  }

  void _validateErrorDetails(ErrorDetails error) {
    _validateModelString(error.type, limits.maxLabelBytes, allowEmpty: false);
    _validateModelString(error.message, limits.maxErrorMessageBytes, allowEmpty: true);
    if (error.stackTrace case final stack?) {
      _validateModelString(stack, limits.maxStackTraceBytes, allowEmpty: true);
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

  Map<String, Object?> _recordMap(ChroniclerRecord record) => {
    'schemaVersion': 1,
    'eventId': record.envelope.eventId,
    'appId': record.envelope.appId,
    'release': record.envelope.release,
    'source': record.envelope.source.name,
    'timestamp': _formatTimestamp(record.envelope.timestamp),
    'buildId': ?record.envelope.buildId,
    'userId': ?record.envelope.userId,
    'anonymousId': ?record.envelope.anonymousId,
    'sessionId': ?record.envelope.sessionId,
    'traceId': ?record.envelope.traceId,
    'spanId': ?record.envelope.spanId,
    'parentSpanId': ?record.envelope.parentSpanId,
    'kind': record.kind,
    'payload': _payloadMap(record),
  };

  Map<String, Object?> _payloadMap(ChroniclerRecord record) => switch (record) {
    LogRecord() => {
      'severity': record.payload.severity.name,
      'message': record.payload.message,
      'attributes': record.payload.attributes,
      if (record.payload.error case final error?) 'error': _errorMap(error),
      'stackTrace': ?record.payload.stackTrace,
    },
    ProductEventRecord() => {'name': record.payload.name, 'properties': record.payload.properties},
    IdentityLinkRecord() => {
      'anonymousId': record.payload.anonymousId,
      'userId': record.payload.userId,
    },
    UserPropertiesSetRecord() => {
      'userId': record.payload.userId,
      'properties': record.payload.properties,
    },
    UserPropertiesUnsetRecord() => {'userId': record.payload.userId, 'keys': record.payload.keys},
    SpanRecord() => {
      'name': record.payload.name,
      'spanKind': record.payload.spanKind.name,
      'status': record.payload.status.name,
      'durationMicros': record.payload.durationMicros,
      'attributes': record.payload.attributes,
    },
    ErrorRecord() => {
      'error': _errorMap(record.payload.error),
      'handled': record.payload.handled,
      'causes': record.payload.causes.map(_errorMap).toList(growable: false),
      'attributes': record.payload.attributes,
    },
    MetricRecord() => {
      'name': record.payload.name,
      'instrument': record.payload.instrument == MetricInstrument.upDownCounter
          ? 'up_down_counter'
          : record.payload.instrument.name,
      'unit': record.payload.unit,
      'attributes': record.payload.attributes,
      'intervalStart': _formatTimestamp(record.payload.intervalStart),
      'intervalEnd': _formatTimestamp(record.payload.intervalEnd),
      'durationMicros': record.payload.durationMicros,
      'observationCount': record.payload.observationCount,
      'temporality': ?record.payload.temporality?.name,
      'sum': ?record.payload.sum,
      'boundaries': ?record.payload.boundaries,
      'bucketCounts': ?record.payload.bucketCounts,
      'count': ?record.payload.count,
      'min': ?record.payload.min,
      'max': ?record.payload.max,
      'value': ?record.payload.value,
      if (record.payload.observedAt case final observedAt?)
        'observedAt': _formatTimestamp(observedAt),
    },
  };

  Map<String, Object?> _errorMap(ErrorDetails error) => {
    'type': error.type,
    'message': error.message,
    'stackTrace': ?error.stackTrace,
  };

  Map<String, Object?> _attributes(Map<String, Object?> map, String key) =>
      _recordValidator.snapshotAttributes(_map(map[key]));

  Map<String, Object?> _nonemptyAttributes(Map<String, Object?> map, String key) {
    final value = _attributes(map, key);
    if (value.isEmpty) throw const _CodecFailure(DecodeFailureReason.invalidField);
    return value;
  }

  List<String> _propertyKeys(Map<String, Object?> map) {
    final value = map['keys'];
    if (value is! List<Object?> || value.isEmpty || value.any((item) => item is! String)) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final keys = value.cast<String>();
    if (keys.toSet().length != keys.length) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    for (final key in keys) {
      if (key.isEmpty) throw const _CodecFailure(DecodeFailureReason.invalidField);
      _recordValidator.validateString(key, limits.maxKeyBytes, 'property key');
    }
    return List.unmodifiable(keys);
  }

  List<double>? _optionalDoubleList(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! List<Object?>) throw const _CodecFailure(DecodeFailureReason.invalidField);
    return List.unmodifiable(
      value.map((item) {
        if (item is! num || !item.toDouble().isFinite) {
          throw const _CodecFailure(DecodeFailureReason.invalidField);
        }
        return item.toDouble() == 0 ? 0.0 : item.toDouble();
      }),
    );
  }

  List<int>? _optionalIntList(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! List<Object?>) throw const _CodecFailure(DecodeFailureReason.invalidField);
    return List.unmodifiable(
      value.map((item) {
        if (item is! int || item < 0 || item > 9007199254740991) {
          throw const _CodecFailure(DecodeFailureReason.invalidField);
        }
        return item;
      }),
    );
  }

  double? _optionalFiniteDouble(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! num || !value.toDouble().isFinite) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final result = value.toDouble();
    return result == 0 ? 0 : result;
  }

  int _portableInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    return value;
  }

  int? _optionalPortableInt(Map<String, Object?> map, String key) =>
      map[key] == null ? null : _portableInt(map, key);

  DateTime _timestamp(Map<String, Object?> map, String key) {
    final text = _string(map, key, 32);
    if (!_timestampPattern.hasMatch(text)) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    try {
      final value = DateTime.parse(text);
      if (!value.isUtc || value.year < 1 || value.year > 9999 || _formatTimestamp(value) != text) {
        throw const _CodecFailure(DecodeFailureReason.invalidField);
      }
      return value;
    } on FormatException {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
  }

  String _id(Map<String, Object?> map, String key) => _string(map, key, limits.maxIdBytes);
  String? _optionalId(Map<String, Object?> map, String key) =>
      _optionalString(map, key, limits.maxIdBytes);
  String _label(Map<String, Object?> map, String key) => _string(map, key, limits.maxLabelBytes);
  String? _optionalLabel(Map<String, Object?> map, String key) =>
      _optionalString(map, key, limits.maxLabelBytes);

  String _string(
    Map<String, Object?> map,
    String key,
    int maxBytes, {
    bool allowEmpty = false,
  }) {
    final value = map[key];
    if (value is! String || !allowEmpty && value.isEmpty) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    _recordValidator.validateString(value, maxBytes, key);
    return value;
  }

  String? _optionalString(
    Map<String, Object?> map,
    String key,
    int maxBytes, {
    bool allowEmpty = false,
  }) => map[key] == null ? null : _string(map, key, maxBytes, allowEmpty: allowEmpty);

  void _version(Map<String, Object?> map) {
    if (map['schemaVersion'] != 1) {
      throw const _CodecFailure(DecodeFailureReason.unsupportedVersion);
    }
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map<Object?, Object?> || value.keys.any((key) => key is! String)) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    return Map.unmodifiable(value.cast<String, Object?>());
  }

  Uint8List _encodeObject(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(_sortObject(value))));

  Object? _sortObject(Object? value) => switch (value) {
    Map<Object?, Object?>() => <String, Object?>{
      for (final key in value.keys.cast<String>().toList()..sort()) key: _sortObject(value[key]),
    },
    List<Object?>() => value.map(_sortObject).toList(growable: false),
    _ => value,
  };

  String _formatTimestamp(DateTime value) {
    final utc = value.toUtc();
    final base = utc.toIso8601String();
    final separator = base.indexOf('.');
    final seconds = separator == -1
        ? base.substring(0, base.length - 1)
        : base.substring(0, separator);
    final micros = utc.millisecond * 1000 + utc.microsecond;
    return '$seconds.${micros.toString().padLeft(6, '0')}Z';
  }

  static const _knownKinds = {
    'log',
    'event',
    'identity_link',
    'user_properties_set',
    'user_properties_unset',
    'span',
    'error',
    'metric',
  };
  static final _traceId = RegExp(r'^(?!0{32}$)[0-9a-f]{32}$');
  static final _spanId = RegExp(r'^(?!0{16}$)[0-9a-f]{16}$');
  static final _timestampPattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
  );
}

final class _CodecFailure implements Exception {
  const _CodecFailure(this.reason);
  final DecodeFailureReason reason;
}

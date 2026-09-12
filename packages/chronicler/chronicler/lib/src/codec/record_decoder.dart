import 'dart:convert';
import 'dart:typed_data';

import 'package:chronicler/src/codec/canonical_json.dart';
import 'package:chronicler/src/codec/record_schema.dart';
import 'package:chronicler/src/codec/results.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chrono_id/chrono_id.dart';

/// Parses untrusted version-one bytes and reports payload-free failures.
final class RecordDecoder {
  /// Creates a decoder with the same limits used for encoding.
  const RecordDecoder({
    required this._limits,
    required this._metricOptions,
    required this._maxRecordBytes,
    required this._maxBatchBytes,
    required this._maxBatchRecords,
  });

  final ChroniclerLimits _limits;
  final MetricOptions _metricOptions;
  final int _maxRecordBytes;
  final int _maxBatchBytes;
  final int _maxBatchRecords;

  RecordValidator get _recordValidator =>
      RecordValidator(_limits, maxSnapshotBytes: _maxRecordBytes);
  RecordSchema get _schema =>
      RecordSchema(limits: _limits, metricOptions: _metricOptions, maxRecordBytes: _maxRecordBytes);

  /// Decodes one version-one record without throwing for malformed input.
  DecodeResult<ChroniclerRecord> decodeRecord(Uint8List bytes) {
    if (bytes.length > _maxRecordBytes) {
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

  /// Decodes one nonempty version-one batch atomically.
  DecodeResult<ChroniclerBatch> decodeBatch(Uint8List bytes) {
    if (bytes.length > _maxBatchBytes) {
      return const DecodeFailure(DecodeFailureReason.limitExceeded);
    }
    final parsed = _parse(bytes);
    if (parsed case final DecodeFailure<Object?> failure) return DecodeFailure(failure.reason);
    try {
      final map = _map((parsed as Decoded<Object?>).value);
      _version(map);
      final rawRecords = map['records'];
      if (rawRecords is! List<Object?> ||
          rawRecords.isEmpty ||
          rawRecords.length > _maxBatchRecords) {
        throw const _CodecFailure(DecodeFailureReason.invalidField);
      }
      final records = <ChroniclerRecord>[];
      for (final raw in rawRecords) {
        final recordMap = _map(raw);
        if (encodeCanonicalJson(recordMap).length > _maxRecordBytes) {
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
    final kind = _string(map, 'kind', _limits.maxLabelBytes);
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
    _schema.validate(record);
    return record;
  }

  RecordEnvelope _decodeEnvelope(Map<String, Object?> map, String kind) {
    final eventId = _string(map, 'eventId', _limits.maxIdBytes);
    if (!ChronoID.isValid(eventId, prefix: 'evt')) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final traceId = _optionalString(map, 'traceId', _limits.maxIdBytes);
    final spanId = _optionalString(map, 'spanId', _limits.maxIdBytes);
    if ((traceId == null) != (spanId == null) ||
        traceId != null && !_schema.isTraceId(traceId) ||
        spanId != null && !_schema.isSpanId(spanId)) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final parentSpanId = _optionalString(map, 'parentSpanId', _limits.maxIdBytes);
    if (parentSpanId != null && (kind != 'span' || !_schema.isSpanId(parentSpanId))) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    if (kind == 'span' && traceId == null || kind == 'metric' && traceId != null) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    final source = switch (_string(map, 'source', _limits.maxLabelBytes)) {
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
    final severity = switch (_string(map, 'severity', _limits.maxLabelBytes)) {
      'debug' => LogSeverity.debug,
      'info' => LogSeverity.info,
      'warning' => LogSeverity.warning,
      'error' => LogSeverity.error,
      _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
    };
    final errorValue = map['error'];
    final error = errorValue == null ? null : _decodeErrorDetails(_map(errorValue));
    final stack = _optionalString(map, 'stackTrace', _limits.maxStackTraceBytes, allowEmpty: true);
    if (error != null && stack != null) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    return LogPayload(
      severity: severity,
      message: _string(map, 'message', _limits.maxStringBytes, allowEmpty: true),
      attributes: _attributes(map, 'attributes'),
      error: error,
      stackTrace: stack,
    );
  }

  SpanPayload _decodeSpan(Map<String, Object?> map) => SpanPayload(
    name: _label(map, 'name'),
    spanKind: switch (_string(map, 'spanKind', _limits.maxLabelBytes)) {
      'internal' => SpanKind.internal,
      'server' => SpanKind.server,
      'client' => SpanKind.client,
      'producer' => SpanKind.producer,
      'consumer' => SpanKind.consumer,
      _ => throw const _CodecFailure(DecodeFailureReason.invalidField),
    },
    status: switch (_string(map, 'status', _limits.maxLabelBytes)) {
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
    if (causesValue is! List<Object?> || causesValue.length > _limits.maxCauses) {
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
    type: _string(map, 'type', _limits.maxLabelBytes),
    message: _string(map, 'message', _limits.maxErrorMessageBytes, allowEmpty: true),
    stackTrace: _optionalString(map, 'stackTrace', _limits.maxStackTraceBytes, allowEmpty: true),
  );

  MetricPayload _decodeMetric(Map<String, Object?> map) {
    final instrument = switch (_string(map, 'instrument', _limits.maxLabelBytes)) {
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
      attributes: _metricAttributes(map, 'attributes'),
      intervalStart: _timestamp(map, 'intervalStart'),
      intervalEnd: _timestamp(map, 'intervalEnd'),
      durationMicros: _portableInt(map, 'durationMicros'),
      observationCount: _portableInt(map, 'observationCount'),
      temporality: map['temporality'] == null
          ? null
          : switch (_string(map, 'temporality', _limits.maxLabelBytes)) {
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
    _schema.validateMetric(payload);
    return payload;
  }

  Map<String, Object?> _attributes(Map<String, Object?> map, String key) =>
      _recordValidator.snapshotAttributes(_map(map[key]));

  Map<String, Object?> _metricAttributes(Map<String, Object?> map, String key) =>
      _recordValidator.snapshotMetricAttributes(
        _map(map[key]),
        maxAttributes: _metricOptions.maxAttributes,
      );

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
    if (value.length > _limits.maxListItems) {
      throw const _CodecFailure(DecodeFailureReason.limitExceeded);
    }
    final keys = value.cast<String>();
    if (keys.toSet().length != keys.length) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    for (final key in keys) {
      if (key.isEmpty) throw const _CodecFailure(DecodeFailureReason.invalidField);
      _recordValidator.validateString(key, _limits.maxKeyBytes, 'property key');
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
      if (!value.isUtc ||
          value.year < 1 ||
          value.year > 9999 ||
          formatRecordTimestamp(value) != text) {
        throw const _CodecFailure(DecodeFailureReason.invalidField);
      }
      return value;
    } on FormatException {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
  }

  String _id(Map<String, Object?> map, String key) => _string(map, key, _limits.maxIdBytes);
  String? _optionalId(Map<String, Object?> map, String key) =>
      _optionalString(map, key, _limits.maxIdBytes);
  String _label(Map<String, Object?> map, String key) => _string(map, key, _limits.maxLabelBytes);
  String? _optionalLabel(Map<String, Object?> map, String key) =>
      _optionalString(map, key, _limits.maxLabelBytes);

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
  static final _timestampPattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
  );
}

final class _CodecFailure implements Exception {
  const _CodecFailure(this.reason);
  final DecodeFailureReason reason;
}

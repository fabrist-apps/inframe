import 'dart:typed_data';

import 'package:chronicler/src/codec/canonical_json.dart';
import 'package:chronicler/src/codec/record_decoder.dart';
import 'package:chronicler/src/codec/record_schema.dart';
import 'package:chronicler/src/codec/results.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';

export 'package:chronicler/src/codec/results.dart';

/// Canonical compact UTF-8 JSON codec for version-one records and batches.
final class ChroniclerCodec {
  /// Creates a version-one codec with explicit decode and encode limits.
  const ChroniclerCodec({
    this.limits = const ChroniclerLimits(),
    this.metricOptions = const MetricOptions(),
    this.maxRecordBytes = 64 * 1024,
    this.maxBatchBytes = 512 * 1024,
    this.maxBatchRecords = 100,
  });

  /// Record schema and caller-data limits.
  final ChroniclerLimits limits;

  /// Metric-specific schema and dimension limits.
  final MetricOptions metricOptions;

  /// Maximum bytes accepted or produced for one record.
  final int maxRecordBytes;

  /// Maximum bytes accepted or produced for one batch.
  final int maxBatchBytes;

  /// Maximum records accepted or produced in one batch.
  final int maxBatchRecords;

  RecordSchema get _schema =>
      RecordSchema(limits: limits, metricOptions: metricOptions, maxRecordBytes: maxRecordBytes);

  RecordDecoder get _decoder => RecordDecoder(
    limits: limits,
    metricOptions: metricOptions,
    maxRecordBytes: maxRecordBytes,
    maxBatchBytes: maxBatchBytes,
    maxBatchRecords: maxBatchRecords,
  );

  /// Validates record fields without applying the complete encoded-record limit.
  void validateRecord(ChroniclerRecord record) {
    try {
      _schema.validate(record);
    } on ChroniclerEncodingException {
      rethrow;
    } on Object {
      throw const ChroniclerEncodingException('record is invalid');
    }
  }

  /// Encodes [record] as canonical compact version-one UTF-8 JSON.
  Uint8List encodeRecord(ChroniclerRecord record) {
    try {
      validateRecord(record);
      final encoded = encodeCanonicalJson(_recordMap(record));
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

  /// Encodes a nonempty [batch] as canonical compact version-one UTF-8 JSON.
  Uint8List encodeBatch(ChroniclerBatch batch) {
    if (batch.records.isEmpty || batch.records.length > maxBatchRecords) {
      throw const ChroniclerEncodingException('batch record count is invalid');
    }
    final recordMaps = batch.records
        .map((record) {
          validateRecord(record);
          final map = _recordMap(record);
          if (encodeCanonicalJson(map).length > maxRecordBytes) {
            throw const ChroniclerEncodingException('record byte limit exceeded');
          }
          return map;
        })
        .toList(growable: false);
    final encoded = encodeCanonicalJson({
      'schemaVersion': 1,
      'records': recordMaps,
    });
    if (encoded.length > maxBatchBytes) {
      throw const ChroniclerEncodingException('batch byte limit exceeded');
    }
    return encoded;
  }

  /// Decodes one version-one record without throwing for malformed input.
  DecodeResult<ChroniclerRecord> decodeRecord(Uint8List bytes) => _decoder.decodeRecord(bytes);

  /// Decodes one nonempty version-one batch atomically.
  DecodeResult<ChroniclerBatch> decodeBatch(Uint8List bytes) => _decoder.decodeBatch(bytes);

  Map<String, Object?> _recordMap(ChroniclerRecord record) {
    final kind = record.toMap()['kind'];
    if (kind is! String) {
      throw const ChroniclerEncodingException('record kind is invalid');
    }
    return {
      'schemaVersion': 1,
      'eventId': record.envelope.eventId,
      'appId': record.envelope.appId,
      'release': record.envelope.release,
      'source': record.envelope.source.name,
      'timestamp': formatRecordTimestamp(record.envelope.timestamp),
      'buildId': ?record.envelope.buildId,
      'userId': ?record.envelope.userId,
      'anonymousId': ?record.envelope.anonymousId,
      'sessionId': ?record.envelope.sessionId,
      'traceId': ?record.envelope.traceId,
      'spanId': ?record.envelope.spanId,
      'parentSpanId': ?record.envelope.parentSpanId,
      'kind': kind,
      'payload': _payloadMap(record),
    };
  }

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
      'intervalStart': formatRecordTimestamp(record.payload.intervalStart),
      'intervalEnd': formatRecordTimestamp(record.payload.intervalEnd),
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
        'observedAt': formatRecordTimestamp(observedAt),
    },
  };

  Map<String, Object?> _errorMap(ErrorDetails error) => {
    'type': error.type,
    'message': error.message,
    'stackTrace': ?error.stackTrace,
  };
}

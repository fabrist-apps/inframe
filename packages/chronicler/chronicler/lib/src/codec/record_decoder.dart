import 'dart:convert';
import 'dart:typed_data';

import 'package:chronicler/src/codec/canonical_json.dart';
import 'package:chronicler/src/codec/record_schema.dart';
import 'package:chronicler/src/codec/results.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';

/// Parses untrusted version-one bytes and reports payload-free failures.
final class RecordDecoder {
  /// Creates a decoder with the same limits used for encoding.
  const RecordDecoder({
    required this._metricOptions,
    required this._maxRecordBytes,
    required this._maxBatchBytes,
    required this._maxBatchRecords,
  });

  final MetricOptions _metricOptions;
  final int _maxRecordBytes;
  final int _maxBatchBytes;
  final int _maxBatchRecords;

  RecordValidator get _recordValidator => RecordValidator(maxSnapshotBytes: _maxRecordBytes);
  RecordSchema get _schema =>
      RecordSchema(metricOptions: _metricOptions, maxRecordBytes: _maxRecordBytes);

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
      return DecodeFailure(_validationFailure(failure.reason));
    } on ChroniclerEncodingException catch (failure) {
      return DecodeFailure(_validationFailure(failure.reason));
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
      return DecodeFailure(_validationFailure(failure.reason));
    } on ChroniclerEncodingException catch (failure) {
      return DecodeFailure(_validationFailure(failure.reason));
    } on Object {
      return const DecodeFailure(DecodeFailureReason.invalidField);
    }
  }

  DecodeFailureReason _validationFailure(String reason) => reason.contains('limit')
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
    final kind = map['kind'];
    final payload = {..._map(map['payload'])};
    if (kind == 'metric') {
      payload['attributes'] = _metricAttributes(payload, 'attributes');
    } else if (kind == 'event' || kind == 'user_properties_set') {
      payload['properties'] = _attributes(payload, 'properties');
    } else if (kind == 'log' || kind == 'span' || kind == 'error') {
      payload['attributes'] = _attributes(payload, 'attributes');
    }
    // Version one flattens the envelope alongside kind and payload.
    final record = ChroniclerRecord.fromMap({'kind': kind, 'envelope': map, 'payload': payload});
    _schema.validate(record);
    return record;
  }

  Map<String, Object?> _attributes(Map<String, Object?> map, String key) =>
      _recordValidator.snapshotAttributes(_map(map[key]));

  Map<String, Object?> _metricAttributes(Map<String, Object?> map, String key) =>
      _recordValidator.snapshotMetricAttributes(
        _map(map[key]),
        maxAttributes: _metricOptions.maxAttributes,
      );

  void _version(Map<String, Object?> map) {
    if (map['schemaVersion'] != 1) {
      throw const _CodecFailure(DecodeFailureReason.unsupportedVersion);
    }
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const _CodecFailure(DecodeFailureReason.invalidField);
    }
    return value;
  }
}

final class _CodecFailure implements Exception {
  const _CodecFailure(this.reason);
  final DecodeFailureReason reason;
}

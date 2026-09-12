import 'package:chronicler/src/codec.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/lifecycle.dart';
import 'package:chronicler/src/models.dart';
import 'package:chronicler/src/record_validation.dart';

/// Validates, redacts, and applies the application hook before queue admission.
///
/// Caller data is validated before redaction can hide it. Hook results must
/// preserve protected fields and pass validation before a second redaction.
final class RecordProcessor {
  /// Creates processing policy from immutable runtime configuration.
  RecordProcessor({required this._codec, required this._redaction, required this._maxRecordBytes});

  final ChroniclerCodec _codec;
  final RedactionOptions _redaction;
  final int _maxRecordBytes;
  bool _insideHook = false;

  /// Whether the application hook is currently running synchronously.
  bool get insideHook => _insideHook;

  /// Returns a validated record and its encoded size, or its rejection reason.
  RecordPreparation prepare(ChroniclerRecord original) {
    try {
      // Validate caller data before field-name rules can hide it.
      _codec.validateRecord(original);
      var record = _redactRecord(original);
      final hook = _redaction.beforeRecord;
      if (hook != null) {
        ChroniclerRecord? changed;
        _insideHook = true;
        try {
          changed = hook(record);
        } on Object {
          return const RejectedRecord(DropReason.hookFailed);
        } finally {
          _insideHook = false;
        }
        if (changed == null) {
          return const RejectedRecord(DropReason.hookDropped);
        }
        if (!_preservesProtectedFields(original, changed)) {
          return const RejectedRecord(DropReason.invalidRecord);
        }
        try {
          _codec.validateRecord(changed);
        } on Object {
          return const RejectedRecord(DropReason.invalidRecord);
        }
        record = changed;
      }
      record = _redactRecord(record);
      final bytes = _codec.encodeRecord(record);
      if (bytes.length > _maxRecordBytes) {
        return const RejectedRecord(DropReason.recordTooLarge);
      }
      return PreparedRecord(record, bytes.length);
    } on RecordValidationException {
      return const RejectedRecord(DropReason.invalidRecord);
    } on ChroniclerEncodingException catch (error) {
      return RejectedRecord(
        error.reason == 'record byte limit exceeded'
            ? DropReason.recordTooLarge
            : DropReason.invalidRecord,
      );
    } on Object {
      return const RejectedRecord(DropReason.invalidRecord);
    }
  }

  ChroniclerRecord _redactRecord(ChroniclerRecord record) => switch (record) {
    LogRecord() => LogRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: redactAttributes(record.payload.attributes)),
    ),
    ProductEventRecord() => ProductEventRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(properties: redactAttributes(record.payload.properties)),
    ),
    UserPropertiesSetRecord() => UserPropertiesSetRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(properties: redactAttributes(record.payload.properties)),
    ),
    SpanRecord() => SpanRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: redactAttributes(record.payload.attributes)),
    ),
    ErrorRecord() => ErrorRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: redactAttributes(record.payload.attributes)),
    ),
    MetricRecord() => MetricRecord(
      envelope: record.envelope,
      payload: record.payload.copyWith(attributes: redactAttributes(record.payload.attributes)),
    ),
    IdentityLinkRecord() || UserPropertiesUnsetRecord() => record,
  };

  /// Redacts a validated attribute snapshot before spans or metrics retain it.
  Map<String, Object?> redactAttributes(Map<Object?, Object?> source) => Map.unmodifiable(
    source.map((key, value) {
      final stringKey = key! as String;
      return MapEntry(
        stringKey,
        _redaction.fieldTerms.any(stringKey.toLowerCase().contains)
            ? '[REDACTED]'
            : _redactValue(value),
      );
    }),
  );

  Object? _redactValue(Object? value) => switch (value) {
    Map<Object?, Object?>() => redactAttributes(value),
    List<Object?>() => List<Object?>.unmodifiable(value.map(_redactValue)),
    _ => value,
  };

  bool _preservesProtectedFields(ChroniclerRecord original, ChroniclerRecord changed) {
    if (original.runtimeType != changed.runtimeType) return false;
    final before = original.envelope;
    final after = changed.envelope;
    if (before.eventId != after.eventId ||
        before.timestamp != after.timestamp ||
        before.appId != after.appId ||
        before.source != after.source ||
        before.release != after.release ||
        before.buildId != after.buildId ||
        before.traceId != after.traceId ||
        before.spanId != after.spanId ||
        before.parentSpanId != after.parentSpanId ||
        !_identityPreserved(before.userId, after.userId) ||
        !_identityPreserved(before.anonymousId, after.anonymousId) ||
        !_identityPreserved(before.sessionId, after.sessionId)) {
      return false;
    }
    if (original case MetricRecord(payload: final beforeMetric)) {
      final afterMetric = (changed as MetricRecord).payload;
      return beforeMetric.name == afterMetric.name &&
          beforeMetric.instrument == afterMetric.instrument &&
          beforeMetric.unit == afterMetric.unit &&
          beforeMetric.intervalStart == afterMetric.intervalStart &&
          beforeMetric.intervalEnd == afterMetric.intervalEnd &&
          beforeMetric.durationMicros == afterMetric.durationMicros &&
          beforeMetric.temporality == afterMetric.temporality &&
          _sameList(beforeMetric.boundaries, afterMetric.boundaries);
    }
    return true;
  }

  bool _identityPreserved(String? before, String? after) => after == null || after == before;

  bool _sameList<T>(List<T>? before, List<T>? after) {
    if (before == null || after == null) return before == after;
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (before[index] != after[index]) return false;
    }
    return true;
  }
}

/// Result of applying capture policy before delivery admission.
sealed class RecordPreparation {
  const RecordPreparation();
}

/// A record ready for queue admission with exact encoded-byte accounting.
final class PreparedRecord extends RecordPreparation {
  /// Retains the final validated record and its encoded size.
  const PreparedRecord(this.record, this.encodedBytes);

  /// Validated and redacted record, including permitted application hook edits.
  final ChroniclerRecord record;

  /// Exact encoded record size used for queue and batch limits.
  final int encodedBytes;
}

/// A record rejected by validation, size limits, or the application hook.
final class RejectedRecord extends RecordPreparation {
  /// Retains the terminal reason for diagnostic and lifecycle accounting.
  const RejectedRecord(this.reason);

  /// Why processing rejected the record.
  final DropReason reason;
}

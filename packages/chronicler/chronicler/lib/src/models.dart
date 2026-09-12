import 'dart:collection';

import 'package:dart_mappable/dart_mappable.dart';

part 'models.mapper.dart';

/// Identifies where a telemetry record originated.
@MappableEnum()
enum ChroniclerSource { client, server }

/// Severity attached to a structured log.
@MappableEnum()
enum LogSeverity { debug, info, warning, error }

/// Fields shared by every version-one record.
@MappableClass()
final class RecordEnvelope with RecordEnvelopeMappable {
  const RecordEnvelope({
    required this.eventId,
    required this.appId,
    required this.release,
    required this.source,
    required this.timestamp,
    this.buildId,
    this.userId,
    this.anonymousId,
    this.sessionId,
    this.traceId,
    this.spanId,
    this.parentSpanId,
  });

  final String eventId;
  final String appId;
  final String release;
  final ChroniclerSource source;
  final DateTime timestamp;
  final String? buildId;
  final String? userId;
  final String? anonymousId;
  final String? sessionId;
  final String? traceId;
  final String? spanId;
  final String? parentSpanId;
}

/// Defensive text extracted from an application error.
@MappableClass()
final class ErrorDetails with ErrorDetailsMappable {
  const ErrorDetails({required this.type, required this.message, this.stackTrace});

  final String type;
  final String message;
  final String? stackTrace;
}

/// Payload carried by a structured log record.
@MappableClass()
final class LogPayload with LogPayloadMappable {
  LogPayload({
    required this.severity,
    required this.message,
    Map<String, Object?> attributes = const {},
    this.error,
    this.stackTrace,
  }) : attributes = UnmodifiableMapView(attributes);

  final LogSeverity severity;
  final String message;
  final Map<String, Object?> attributes;
  final ErrorDetails? error;
  final String? stackTrace;
}

/// Closed version-one record family.
sealed class ChroniclerRecord {
  const ChroniclerRecord();

  RecordEnvelope get envelope;
  ChroniclerSignalKind get signalKind;
  String get kind;
}

/// Internal signal classification stored with immutable records.
enum ChroniclerSignalKind { logs, events, traces, errors, metrics }

/// A version-one structured log record.
@MappableClass()
final class LogRecord extends ChroniclerRecord with LogRecordMappable {
  const LogRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final LogPayload payload;

  @override
  String get kind => 'log';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.logs;
}

/// An immutable ordered collection submitted to an exporter.
final class ChroniclerBatch {
  ChroniclerBatch(Iterable<ChroniclerRecord> records) : records = List.unmodifiable(records);

  final List<ChroniclerRecord> records;
}

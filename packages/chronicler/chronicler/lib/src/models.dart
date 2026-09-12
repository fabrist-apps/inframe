import 'package:dart_mappable/dart_mappable.dart';

part 'models.mapper.dart';

/// Identifies where a telemetry record originated.
@MappableEnum()
enum ChroniclerSource { client, server }

/// Severity attached to a structured log.
@MappableEnum()
enum LogSeverity { debug, info, warning, error }

/// Kind attached to a completed span.
@MappableEnum()
enum SpanKind { internal, server, client, producer, consumer }

/// Result attached to a completed span.
@MappableEnum()
enum SpanStatus { success, error, cancelled }

/// Instrument represented by a metric aggregate.
@MappableEnum()
enum MetricInstrument { counter, upDownCounter, histogram, gauge }

/// Aggregation temporality for sum instruments.
@MappableEnum()
enum MetricTemporality { delta }

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
  }) : attributes = _immutableJsonMap(attributes);

  final LogSeverity severity;
  final String message;
  final Map<String, Object?> attributes;
  final ErrorDetails? error;
  final String? stackTrace;
}

/// Payload carried by an ordinary named product event.
@MappableClass()
final class ProductEventPayload with ProductEventPayloadMappable {
  ProductEventPayload({
    required this.name,
    Map<String, Object?> properties = const {},
  }) : properties = _immutableJsonMap(properties);

  final String name;
  final Map<String, Object?> properties;
}

/// Payload linking one anonymous identity to a known user.
@MappableClass()
final class IdentityLinkPayload with IdentityLinkPayloadMappable {
  const IdentityLinkPayload({required this.anonymousId, required this.userId});

  final String anonymousId;
  final String userId;
}

/// Payload setting explicit user properties.
@MappableClass()
final class UserPropertiesSetPayload with UserPropertiesSetPayloadMappable {
  UserPropertiesSetPayload({
    required this.userId,
    required Map<String, Object?> properties,
  }) : properties = _immutableJsonMap(properties);

  final String userId;
  final Map<String, Object?> properties;
}

/// Payload removing explicit user-property keys.
@MappableClass()
final class UserPropertiesUnsetPayload with UserPropertiesUnsetPayloadMappable {
  UserPropertiesUnsetPayload({required this.userId, required Iterable<String> keys})
    : keys = List.unmodifiable(keys);

  final String userId;
  final List<String> keys;
}

/// Payload carried by a completed span.
@MappableClass()
final class SpanPayload with SpanPayloadMappable {
  SpanPayload({
    required this.name,
    required this.spanKind,
    required this.status,
    required this.durationMicros,
    Map<String, Object?> attributes = const {},
  }) : attributes = _immutableJsonMap(attributes);

  final String name;
  final SpanKind spanKind;
  final SpanStatus status;
  final int durationMicros;
  final Map<String, Object?> attributes;
}

/// Payload carried by an explicit error occurrence.
@MappableClass()
final class ErrorPayload with ErrorPayloadMappable {
  ErrorPayload({
    required this.error,
    required this.handled,
    Iterable<ErrorDetails> causes = const [],
    Map<String, Object?> attributes = const {},
  }) : causes = List.unmodifiable(causes),
       attributes = _immutableJsonMap(attributes);

  final ErrorDetails error;
  final bool handled;
  final List<ErrorDetails> causes;
  final Map<String, Object?> attributes;
}

/// Payload carried by one finalized metric series interval.
@MappableClass()
final class MetricPayload with MetricPayloadMappable {
  MetricPayload({
    required this.name,
    required this.instrument,
    required this.unit,
    required this.intervalStart,
    required this.intervalEnd,
    required this.durationMicros,
    required this.observationCount,
    Map<String, Object?> attributes = const {},
    this.temporality,
    this.sum,
    Iterable<double>? boundaries,
    Iterable<int>? bucketCounts,
    this.count,
    this.min,
    this.max,
    this.value,
    this.observedAt,
  }) : attributes = _immutableJsonMap(attributes),
       boundaries = boundaries == null ? null : List.unmodifiable(boundaries),
       bucketCounts = bucketCounts == null ? null : List.unmodifiable(bucketCounts);

  final String name;
  final MetricInstrument instrument;
  final String unit;
  final Map<String, Object?> attributes;
  final DateTime intervalStart;
  final DateTime intervalEnd;
  final int durationMicros;
  final int observationCount;
  final MetricTemporality? temporality;
  final double? sum;
  final List<double>? boundaries;
  final List<int>? bucketCounts;
  final int? count;
  final double? min;
  final double? max;
  final double? value;
  final DateTime? observedAt;
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

/// A version-one named product event.
@MappableClass()
final class ProductEventRecord extends ChroniclerRecord with ProductEventRecordMappable {
  const ProductEventRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final ProductEventPayload payload;

  @override
  String get kind => 'event';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;
}

/// A version-one anonymous-to-user identity link.
@MappableClass()
final class IdentityLinkRecord extends ChroniclerRecord with IdentityLinkRecordMappable {
  const IdentityLinkRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final IdentityLinkPayload payload;

  @override
  String get kind => 'identity_link';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;
}

/// A version-one user-property set operation.
@MappableClass()
final class UserPropertiesSetRecord extends ChroniclerRecord with UserPropertiesSetRecordMappable {
  const UserPropertiesSetRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final UserPropertiesSetPayload payload;

  @override
  String get kind => 'user_properties_set';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;
}

/// A version-one user-property unset operation.
@MappableClass()
final class UserPropertiesUnsetRecord extends ChroniclerRecord
    with UserPropertiesUnsetRecordMappable {
  const UserPropertiesUnsetRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final UserPropertiesUnsetPayload payload;

  @override
  String get kind => 'user_properties_unset';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;
}

/// A version-one completed span.
@MappableClass()
final class SpanRecord extends ChroniclerRecord with SpanRecordMappable {
  const SpanRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final SpanPayload payload;

  @override
  String get kind => 'span';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.traces;
}

/// A version-one explicit error occurrence.
@MappableClass()
final class ErrorRecord extends ChroniclerRecord with ErrorRecordMappable {
  const ErrorRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final ErrorPayload payload;

  @override
  String get kind => 'error';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.errors;
}

/// A version-one finalized metric aggregate.
@MappableClass()
final class MetricRecord extends ChroniclerRecord with MetricRecordMappable {
  const MetricRecord({required this.envelope, required this.payload});

  @override
  final RecordEnvelope envelope;
  final MetricPayload payload;

  @override
  String get kind => 'metric';

  @override
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.metrics;
}

/// An immutable ordered collection submitted to an exporter.
final class ChroniclerBatch {
  ChroniclerBatch(Iterable<ChroniclerRecord> records) : records = List.unmodifiable(records);

  final List<ChroniclerRecord> records;
}

Map<String, Object?> _immutableJsonMap(Map<String, Object?> value) => Map.unmodifiable(
  value.map((key, item) => MapEntry(key, _immutableJsonValue(item))),
);

Object? _immutableJsonValue(Object? value) => switch (value) {
  Map<String, Object?>() => _immutableJsonMap(value),
  List<Object?>() => List<Object?>.unmodifiable(value.map(_immutableJsonValue)),
  _ => value,
};

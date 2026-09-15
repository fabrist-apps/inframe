import 'package:ack/ack.dart';
import 'package:ack_chrono_id/ack_chrono_id.dart';
import 'package:chronicler/src/configuration.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:conflux/moment.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:dart_mappable_conflux/dart_mappable_conflux.dart';

part 'models.mapper.dart';

/// Identifies where a telemetry record originated.
@MappableEnum()
enum ChroniclerSource {
  /// An App Client runtime.
  client,

  /// An App Server runtime.
  server,
}

/// Severity attached to a structured log.
@MappableEnum()
enum LogSeverity {
  /// Detailed diagnostic information.
  debug,

  /// Normal operational information.
  info,

  /// A condition that may require attention.
  warning,

  /// A failed operation or degraded condition.
  error,
}

/// Kind attached to a completed span.
@MappableEnum()
enum SpanKind {
  /// Work internal to one component.
  internal,

  /// Work serving an inbound request.
  server,

  /// Work issuing an outbound request.
  client,

  /// Work publishing a message.
  producer,

  /// Work consuming a message.
  consumer,
}

/// Result attached to a completed span.
@MappableEnum()
enum SpanStatus {
  /// The operation completed successfully.
  success,

  /// The operation completed with an error.
  error,

  /// The operation was cancelled.
  cancelled,
}

/// Instrument represented by a metric aggregate.
@MappableEnum()
enum MetricInstrument {
  /// A monotonically increasing sum.
  counter,

  /// A sum that may increase or decrease.
  upDownCounter,

  /// A distribution grouped into configured buckets.
  histogram,

  /// The most recently observed value.
  gauge,
}

/// Aggregation temporality for sum instruments.
@MappableEnum()
enum MetricTemporality {
  /// Values describe change during the recorded interval.
  delta,
}

/// Fields shared by every version-one record.
@MappableClass(includeCustomMappers: [MomentMapper()])
final class RecordEnvelope with RecordEnvelopeMappable {
  /// Creates the shared identity and attribution for one record.
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

  /// Stable Chrono ID used to deduplicate retries.
  final String eventId;

  /// App that produced the record.
  final String appId;

  /// App release that produced the record.
  final String release;

  /// Runtime category that produced the record.
  final ChroniclerSource source;

  /// Occurrence time preserved across retries and encoded in UTC.
  final Moment timestamp;

  /// Optional build identifier within the release.
  final String? buildId;

  /// Known End User identifier, when available.
  final String? userId;

  /// Anonymous End User identifier, when available.
  final String? anonymousId;

  /// App session identifier, when available.
  final String? sessionId;

  /// Distributed trace Chrono ID with the `trc` prefix, when correlated.
  final String? traceId;

  /// Current span Chrono ID with the `spn` prefix, when correlated.
  final String? spanId;

  /// Parent span's `spn`-prefixed Chrono ID for span records.
  final String? parentSpanId;

  /// Decodes a [RecordEnvelope] from a map.
  static const fromMap = RecordEnvelopeMapper.fromMap;

  /// Decodes a [RecordEnvelope] from JSON.
  static const fromJson = RecordEnvelopeMapper.fromJson;

  /// Validates the mapped envelope, including Chrono IDs and trace pairing.
  static AckSchema<JsonMap, JsonMap> schema() =>
      Ack.object({
        'eventId': Ack.string().chronoId(prefix: 'evt'),
        'appId': Ack.string().notEmpty(),
        'release': Ack.string().notEmpty(),
        'source': Ack.enumString(ChroniclerSource.values.map((value) => value.name).toList()),
        'timestamp': Ack.string(),
        'buildId': Ack.string().notEmpty().nullable().optional(),
        'userId': Ack.string().notEmpty().nullable().optional(),
        'anonymousId': Ack.string().notEmpty().nullable().optional(),
        'sessionId': Ack.string().notEmpty().nullable().optional(),
        'traceId': Ack.string().chronoId(prefix: 'trc').nullable().optional(),
        'spanId': Ack.string().chronoId(prefix: 'spn').nullable().optional(),
        'parentSpanId': Ack.string().chronoId(prefix: 'spn').nullable().optional(),
      }).passthrough().refine(
        (value) => (value['traceId'] == null) == (value['spanId'] == null),
        message: 'trace correlation is invalid',
      );
}

/// Defensive text extracted from an application error.
@MappableClass()
final class ErrorDetails with ErrorDetailsMappable {
  /// Creates defensively converted error details.
  const ErrorDetails({required this.type, required this.message, this.stackTrace});

  /// Runtime error type or fallback label.
  final String type;

  /// Error text or a payload-safe fallback.
  final String message;

  /// Optional stack trace text.
  final String? stackTrace;

  /// Decodes [ErrorDetails] from a map.
  static const fromMap = ErrorDetailsMapper.fromMap;

  /// Decodes [ErrorDetails] from JSON.
  static const fromJson = ErrorDetailsMapper.fromJson;

  /// Validates mapped error details.
  static ObjectSchema schema() => Ack.object({
    'type': Ack.string().notEmpty(),
    'message': Ack.string(),
    'stackTrace': Ack.string().nullable().optional(),
  }).passthrough();
}

/// Payload carried by a structured log record.
@MappableClass()
final class LogPayload with LogPayloadMappable {
  /// Creates an immutable structured log payload.
  LogPayload({
    required this.severity,
    required this.message,
    Map<String, Object?> attributes = const {},
    this.error,
    this.stackTrace,
  }) : attributes = _immutableJsonMap(attributes);

  /// Severity assigned by the caller.
  final LogSeverity severity;

  /// Caller-supplied log message.
  final String message;

  /// Immutable structured attributes.
  final Map<String, Object?> attributes;

  /// Optional converted application error.
  final ErrorDetails? error;

  /// Optional standalone stack trace, independent of [error].
  final String? stackTrace;

  /// Decodes a [LogPayload] from a map.
  static const fromMap = LogPayloadMapper.fromMap;

  /// Decodes a [LogPayload] from JSON.
  static const fromJson = LogPayloadMapper.fromJson;

  /// Validates mapped log fields and bounded attributes.
  static ObjectSchema schema({int maxRecordBytes = 64 * 1024}) => Ack.object({
    'severity': Ack.enumString(LogSeverity.values.map((value) => value.name).toList()),
    'message': Ack.string(),
    'attributes': RecordValidator(maxSnapshotBytes: maxRecordBytes).attributesSchema(),
    'error': ErrorDetails.schema().nullable().optional(),
    'stackTrace': Ack.string().nullable().optional(),
  }).passthrough();
}

/// Payload carried by an ordinary named product event.
@MappableClass()
final class ProductEventPayload with ProductEventPayloadMappable {
  /// Creates an immutable named event payload.
  ProductEventPayload({
    required this.name,
    Map<String, Object?> properties = const {},
  }) : properties = _immutableJsonMap(properties);

  /// Product event name.
  final String name;

  /// Immutable event properties.
  final Map<String, Object?> properties;

  /// Decodes a [ProductEventPayload] from a map.
  static const fromMap = ProductEventPayloadMapper.fromMap;

  /// Decodes a [ProductEventPayload] from JSON.
  static const fromJson = ProductEventPayloadMapper.fromJson;

  /// Validates mapped event fields and bounded properties.
  static ObjectSchema schema({int maxRecordBytes = 64 * 1024}) => Ack.object({
    'name': Ack.string().notEmpty(),
    'properties': RecordValidator(maxSnapshotBytes: maxRecordBytes).attributesSchema(),
  }).passthrough();
}

/// Payload linking one anonymous identity to a known user.
@MappableClass()
final class IdentityLinkPayload with IdentityLinkPayloadMappable {
  /// Creates an anonymous-to-known identity link.
  const IdentityLinkPayload({required this.anonymousId, required this.userId});

  /// Anonymous identifier being linked.
  final String anonymousId;

  /// Known End User identifier receiving the link.
  final String userId;

  /// Decodes an [IdentityLinkPayload] from a map.
  static const fromMap = IdentityLinkPayloadMapper.fromMap;

  /// Decodes an [IdentityLinkPayload] from JSON.
  static const fromJson = IdentityLinkPayloadMapper.fromJson;

  /// Validates mapped identity-link targets.
  static ObjectSchema schema() => Ack.object({
    'anonymousId': Ack.string().notEmpty(),
    'userId': Ack.string().notEmpty(),
  }).passthrough();
}

/// Payload setting explicit user properties.
@MappableClass()
final class UserPropertiesSetPayload with UserPropertiesSetPayloadMappable {
  /// Creates an immutable user-property update.
  UserPropertiesSetPayload({
    required this.userId,
    required Map<String, Object?> properties,
  }) : properties = _immutableJsonMap(properties);

  /// Known End User identifier to update.
  final String userId;

  /// Nonempty immutable properties to set.
  final Map<String, Object?> properties;

  /// Decodes a [UserPropertiesSetPayload] from a map.
  static const fromMap = UserPropertiesSetPayloadMapper.fromMap;

  /// Decodes a [UserPropertiesSetPayload] from JSON.
  static const fromJson = UserPropertiesSetPayloadMapper.fromJson;

  /// Validates mapped user-property updates.
  static ObjectSchema schema({int maxRecordBytes = 64 * 1024}) => Ack.object({
    'userId': Ack.string().notEmpty(),
    'properties': RecordValidator(maxSnapshotBytes: maxRecordBytes)
        .attributesSchema()
        .refine((value) => value.isNotEmpty, message: 'properties must be nonempty'),
  }).passthrough();
}

/// Payload removing explicit user-property keys.
@MappableClass()
final class UserPropertiesUnsetPayload with UserPropertiesUnsetPayloadMappable {
  /// Creates an immutable user-property removal.
  UserPropertiesUnsetPayload({required this.userId, required List<String> keys})
    : keys = List.unmodifiable(keys);

  /// Known End User identifier to update.
  final String userId;

  /// Distinct property keys to remove.
  final List<String> keys;

  /// Decodes a [UserPropertiesUnsetPayload] from a map.
  static const fromMap = UserPropertiesUnsetPayloadMapper.fromMap;

  /// Decodes a [UserPropertiesUnsetPayload] from JSON.
  static const fromJson = UserPropertiesUnsetPayloadMapper.fromJson;

  /// Validates mapped property removals.
  static ObjectSchema schema() => Ack.object({
    'userId': Ack.string().notEmpty(),
    'keys': Ack.list(Ack.string()).notEmpty().unique(),
  }).passthrough();
}

/// Payload carried by a completed span.
@MappableClass()
final class SpanPayload with SpanPayloadMappable {
  /// Creates an immutable completed-span payload.
  SpanPayload({
    required this.name,
    required this.spanKind,
    required this.status,
    required this.durationMicros,
    Map<String, Object?> attributes = const {},
  }) : attributes = _immutableJsonMap(attributes);

  /// Operation name.
  final String name;

  /// Relationship between the operation and other components.
  final SpanKind spanKind;

  /// Final operation status.
  final SpanStatus status;

  /// Monotonic elapsed duration in microseconds.
  final int durationMicros;

  /// Immutable span attributes.
  final Map<String, Object?> attributes;

  /// Decodes a [SpanPayload] from a map.
  static const fromMap = SpanPayloadMapper.fromMap;

  /// Decodes a [SpanPayload] from JSON.
  static const fromJson = SpanPayloadMapper.fromJson;

  /// Validates mapped completed-span fields.
  static ObjectSchema schema({int maxRecordBytes = 64 * 1024}) => Ack.object({
    'name': Ack.string().notEmpty(),
    'spanKind': Ack.enumString(SpanKind.values.map((value) => value.name).toList()),
    'status': Ack.enumString(SpanStatus.values.map((value) => value.name).toList()),
    'durationMicros': Ack.integer().min(0),
    'attributes': RecordValidator(maxSnapshotBytes: maxRecordBytes).attributesSchema(),
  }).passthrough();
}

/// Payload carried by an explicit error occurrence.
@MappableClass()
final class ErrorPayload with ErrorPayloadMappable {
  /// Creates an immutable error-occurrence payload.
  ErrorPayload({
    required this.error,
    required this.handled,
    List<ErrorDetails> causes = const [],
    Map<String, Object?> attributes = const {},
  }) : causes = List.unmodifiable(causes),
       attributes = _immutableJsonMap(attributes);

  /// Primary converted error details.
  final ErrorDetails error;

  /// Whether application code handled the error.
  final bool handled;

  /// Ordered converted causes, nearest first.
  final List<ErrorDetails> causes;

  /// Immutable error attributes.
  final Map<String, Object?> attributes;

  /// Decodes an [ErrorPayload] from a map.
  static const fromMap = ErrorPayloadMapper.fromMap;

  /// Decodes an [ErrorPayload] from JSON.
  static const fromJson = ErrorPayloadMapper.fromJson;

  /// Validates mapped error occurrences and their bounded cause list.
  static ObjectSchema schema({int maxRecordBytes = 64 * 1024}) => Ack.object({
    'error': ErrorDetails.schema(),
    'handled': Ack.boolean(),
    'causes': Ack.list(ErrorDetails.schema()).maxItems(maxErrorCauses),
    'attributes': RecordValidator(maxSnapshotBytes: maxRecordBytes).attributesSchema(),
  }).passthrough();
}

/// Payload carried by one finalized metric series interval.
@MappableClass(includeCustomMappers: [MomentMapper()])
final class MetricPayload with MetricPayloadMappable {
  /// Creates an immutable finalized metric interval.
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
    List<double>? boundaries,
    List<int>? bucketCounts,
    this.count,
    this.min,
    this.max,
    this.value,
    this.observedAt,
  }) : attributes = _immutableJsonMap(attributes),
       boundaries = boundaries == null ? null : List.unmodifiable(boundaries),
       bucketCounts = bucketCounts == null ? null : List.unmodifiable(bucketCounts);

  /// Metric instrument name.
  final String name;

  /// Instrument aggregation form.
  final MetricInstrument instrument;

  /// Unit attached to values.
  final String unit;

  /// Immutable series attributes.
  final Map<String, Object?> attributes;

  /// Inclusive start of the aggregation interval.
  final Moment intervalStart;

  /// End of the aggregation interval and record occurrence time.
  final Moment intervalEnd;

  /// Monotonic interval duration in microseconds.
  final int durationMicros;

  /// Number of measurements represented by this aggregate.
  final int observationCount;

  /// Sum aggregation temporality, when applicable.
  final MetricTemporality? temporality;

  /// Aggregated sum for counter, up/down counter, and histogram instruments.
  final double? sum;

  /// Ordered upper bounds for histogram buckets.
  final List<double>? boundaries;

  /// Counts for histogram buckets, including the overflow bucket.
  final List<int>? bucketCounts;

  /// Total histogram observation count.
  final int? count;

  /// Minimum histogram observation.
  final double? min;

  /// Maximum histogram observation.
  final double? max;

  /// Most recent gauge value.
  final double? value;

  /// Occurrence time of the most recent gauge value.
  final Moment? observedAt;

  /// Decodes a [MetricPayload] from a map.
  static const fromMap = MetricPayloadMapper.fromMap;

  /// Decodes a [MetricPayload] from JSON.
  static const fromJson = MetricPayloadMapper.fromJson;

  /// Validates mapped metric fields using the instrument as discriminator.
  static AckSchema<JsonMap, JsonMap> schema({
    MetricOptions metricOptions = const MetricOptions(),
    int maxRecordBytes = 64 * 1024,
  }) {
    final absent = Ack.any().nullable().optional().refine(
      (_) => false,
      message: 'field is not used by this instrument',
    );
    final common = Ack.object({
      'name': Ack.string().notEmpty(),
      'unit': Ack.string().notEmpty(),
      'attributes': RecordValidator(maxSnapshotBytes: maxRecordBytes)
          .attributesSchema(maxMetricAttributes: metricOptions.maxAttributes),
      'intervalStart': Ack.string(),
      'intervalEnd': Ack.string(),
      'durationMicros': Ack.integer().min(0),
      'observationCount': Ack.integer().positive(),
      'temporality': absent,
      'sum': absent,
      'boundaries': absent,
      'bucketCounts': absent,
      'count': absent,
      'min': absent,
      'max': absent,
      'value': absent,
      'observedAt': absent,
    }).passthrough();
    final sum = common.extend({
      'temporality': Ack.literal('delta'),
      'sum': Ack.double().finite(),
    });
    return Ack.discriminated<JsonMap>(
      discriminatorKey: 'instrument',
      schemas: {
        'counter': sum.extend({'sum': Ack.double().finite().min(0)}),
        'upDownCounter': sum,
        'gauge': common.extend({
          'value': Ack.double().finite(),
          'observedAt': Ack.string(),
        }),
        'histogram': sum
            .extend({
              'boundaries': Ack.list(Ack.double().finite())
                  .notEmpty()
                  .maxItems(metricOptions.maxHistogramBoundaries)
                  .refine(_strictlyIncreasing, message: 'histogram boundaries must increase'),
              'bucketCounts': Ack.list(Ack.integer().min(0)),
              'count': Ack.integer().positive(),
              'min': Ack.double().finite(),
              'max': Ack.double().finite(),
            })
            .refine((value) {
              final buckets = value['bucketCounts']! as List<int>;
              return buckets.length == (value['boundaries']! as List<double>).length + 1 &&
                  value['count'] == value['observationCount'] &&
                  buckets.fold<BigInt>(BigInt.zero, (sum, count) => sum + BigInt.from(count)) ==
                      BigInt.from(value['count']! as int) &&
                  (value['min']! as double) <= (value['max']! as double);
            }, message: 'histogram aggregates are inconsistent'),
      },
    );
  }

  static bool _strictlyIncreasing(List<double> values) {
    for (var index = 1; index < values.length; index++) {
      if (values[index - 1] >= values[index]) return false;
    }
    return true;
  }
}

/// Closed version-one record family.
@MappableClass(discriminatorKey: 'kind')
sealed class ChroniclerRecord with ChroniclerRecordMappable {
  /// Creates the base type for a version-one record.
  const ChroniclerRecord();

  /// Shared record identity and attribution.
  RecordEnvelope get envelope;

  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind;

  /// Decodes a [ChroniclerRecord] from a map.
  static const fromMap = ChroniclerRecordMapper.fromMap;

  /// Decodes a [ChroniclerRecord] from JSON.
  static const fromJson = ChroniclerRecordMapper.fromJson;

  /// Validates mapped records through their kind-specific payload schemas.
  ///
  /// Use `ChroniclerRecord.schema().safeParse(record.toMap())` for mapped data.
  /// Use `ChroniclerCodec.validateRecord` at runtime to also bound attributes
  /// before serialization.
  static AckSchema<JsonMap, JsonMap> schema({
    MetricOptions metricOptions = const MetricOptions(),
    int maxRecordBytes = 64 * 1024,
  }) {
    final envelope = RecordEnvelope.schema();
    ObjectSchema record(AckSchema<JsonMap, JsonMap> payload) => Ack.object({
      'envelope': envelope,
      'payload': payload,
    }).passthrough();
    return Ack.discriminated<JsonMap>(
      discriminatorKey: 'kind',
      schemas: {
        'log': record(LogPayload.schema(maxRecordBytes: maxRecordBytes)),
        'event': record(ProductEventPayload.schema(maxRecordBytes: maxRecordBytes)),
        'identity_link': record(IdentityLinkPayload.schema()),
        'user_properties_set': record(
          UserPropertiesSetPayload.schema(maxRecordBytes: maxRecordBytes),
        ),
        'user_properties_unset': record(UserPropertiesUnsetPayload.schema()),
        'span': record(SpanPayload.schema(maxRecordBytes: maxRecordBytes)).refine(
          (value) => (value['envelope']! as JsonMap)['traceId'] != null,
          message: 'span needs trace IDs',
        ),
        'error': record(ErrorPayload.schema(maxRecordBytes: maxRecordBytes)),
        'metric':
            record(
              MetricPayload.schema(metricOptions: metricOptions, maxRecordBytes: maxRecordBytes),
            ).refine((value) {
              final envelope = value['envelope']! as JsonMap;
              final payload = value['payload']! as JsonMap;
              return [
                    'userId',
                    'anonymousId',
                    'sessionId',
                    'traceId',
                  ].every((key) => envelope[key] == null) &&
                  envelope['timestamp'] == payload['intervalEnd'];
            }, message: 'metric envelope is inconsistent'),
      },
    ).refine(
      (value) => (value['envelope']! as JsonMap)['parentSpanId'] == null || value['kind'] == 'span',
      message: 'parent span is invalid',
    );
  }
}

/// Internal signal classification stored with immutable records.
enum ChroniclerSignalKind {
  /// Structured logs.
  logs,

  /// Product analytics and identity operations.
  events,

  /// Distributed tracing spans.
  traces,

  /// Error occurrences.
  errors,

  /// Metric aggregates.
  metrics,
}

/// A version-one structured log record.
@MappableClass(discriminatorValue: 'log')
final class LogRecord extends ChroniclerRecord with LogRecordMappable {
  /// Creates a structured log record.
  const LogRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// Structured log data.
  final LogPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.logs;

  /// Decodes a [LogRecord] from a map.
  static const fromMap = LogRecordMapper.fromMap;

  /// Decodes a [LogRecord] from JSON.
  static const fromJson = LogRecordMapper.fromJson;
}

/// A version-one named product event.
@MappableClass(discriminatorValue: 'event')
final class ProductEventRecord extends ChroniclerRecord with ProductEventRecordMappable {
  /// Creates a named product event record.
  const ProductEventRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// Named event data.
  final ProductEventPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;

  /// Decodes a [ProductEventRecord] from a map.
  static const fromMap = ProductEventRecordMapper.fromMap;

  /// Decodes a [ProductEventRecord] from JSON.
  static const fromJson = ProductEventRecordMapper.fromJson;
}

/// A version-one anonymous-to-user identity link.
@MappableClass(discriminatorValue: 'identity_link')
final class IdentityLinkRecord extends ChroniclerRecord with IdentityLinkRecordMappable {
  /// Creates an identity-link record.
  const IdentityLinkRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// Anonymous-to-known identity link.
  final IdentityLinkPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;

  /// Decodes an [IdentityLinkRecord] from a map.
  static const fromMap = IdentityLinkRecordMapper.fromMap;

  /// Decodes an [IdentityLinkRecord] from JSON.
  static const fromJson = IdentityLinkRecordMapper.fromJson;
}

/// A version-one user-property set operation.
@MappableClass(discriminatorValue: 'user_properties_set')
final class UserPropertiesSetRecord extends ChroniclerRecord with UserPropertiesSetRecordMappable {
  /// Creates a user-property set record.
  const UserPropertiesSetRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// User-property update.
  final UserPropertiesSetPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;

  /// Decodes a [UserPropertiesSetRecord] from a map.
  static const fromMap = UserPropertiesSetRecordMapper.fromMap;

  /// Decodes a [UserPropertiesSetRecord] from JSON.
  static const fromJson = UserPropertiesSetRecordMapper.fromJson;
}

/// A version-one user-property unset operation.
@MappableClass(discriminatorValue: 'user_properties_unset')
final class UserPropertiesUnsetRecord extends ChroniclerRecord
    with UserPropertiesUnsetRecordMappable {
  /// Creates a user-property unset record.
  const UserPropertiesUnsetRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// User-property removal.
  final UserPropertiesUnsetPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.events;

  /// Decodes a [UserPropertiesUnsetRecord] from a map.
  static const fromMap = UserPropertiesUnsetRecordMapper.fromMap;

  /// Decodes a [UserPropertiesUnsetRecord] from JSON.
  static const fromJson = UserPropertiesUnsetRecordMapper.fromJson;
}

/// A version-one completed span.
@MappableClass(discriminatorValue: 'span')
final class SpanRecord extends ChroniclerRecord with SpanRecordMappable {
  /// Creates a completed span record.
  const SpanRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// Completed operation data.
  final SpanPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.traces;

  /// Decodes a [SpanRecord] from a map.
  static const fromMap = SpanRecordMapper.fromMap;

  /// Decodes a [SpanRecord] from JSON.
  static const fromJson = SpanRecordMapper.fromJson;
}

/// A version-one explicit error occurrence.
@MappableClass(discriminatorValue: 'error')
final class ErrorRecord extends ChroniclerRecord with ErrorRecordMappable {
  /// Creates an explicit error-occurrence record.
  const ErrorRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// Error-occurrence data.
  final ErrorPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.errors;

  /// Decodes an [ErrorRecord] from a map.
  static const fromMap = ErrorRecordMapper.fromMap;

  /// Decodes an [ErrorRecord] from JSON.
  static const fromJson = ErrorRecordMapper.fromJson;
}

/// A version-one finalized metric aggregate.
@MappableClass(discriminatorValue: 'metric')
final class MetricRecord extends ChroniclerRecord with MetricRecordMappable {
  /// Creates a finalized metric aggregate record.
  const MetricRecord({required this.envelope, required this.payload});

  @override
  /// Shared record identity and attribution.
  final RecordEnvelope envelope;

  /// Finalized metric data.
  final MetricPayload payload;

  @override
  /// Signal used by collection controls.
  ChroniclerSignalKind get signalKind => ChroniclerSignalKind.metrics;

  /// Decodes a [MetricRecord] from a map.
  static const fromMap = MetricRecordMapper.fromMap;

  /// Decodes a [MetricRecord] from JSON.
  static const fromJson = MetricRecordMapper.fromJson;
}

/// An immutable ordered collection submitted to an exporter.
final class ChroniclerBatch {
  /// Creates an immutable ordered batch from [records].
  ChroniclerBatch(Iterable<ChroniclerRecord> records) : records = List.unmodifiable(records);

  /// Records submitted together to one exporter attempt.
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

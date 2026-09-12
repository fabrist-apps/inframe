// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'models.dart';

class ChroniclerSourceMapper extends EnumMapper<ChroniclerSource> {
  ChroniclerSourceMapper._();

  static ChroniclerSourceMapper? _instance;
  static ChroniclerSourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChroniclerSourceMapper._());
    }
    return _instance!;
  }

  static ChroniclerSource fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ChroniclerSource decode(dynamic value) {
    switch (value) {
      case r'client':
        return ChroniclerSource.client;
      case r'server':
        return ChroniclerSource.server;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ChroniclerSource self) {
    switch (self) {
      case ChroniclerSource.client:
        return r'client';
      case ChroniclerSource.server:
        return r'server';
    }
  }
}
extension ChroniclerSourceMapperExtension on ChroniclerSource {
  String toValue() {
    ChroniclerSourceMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ChroniclerSource>(this) as String;
  }
}

class LogSeverityMapper extends EnumMapper<LogSeverity> {
  LogSeverityMapper._();

  static LogSeverityMapper? _instance;
  static LogSeverityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LogSeverityMapper._());
    }
    return _instance!;
  }

  static LogSeverity fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  LogSeverity decode(dynamic value) {
    switch (value) {
      case r'debug':
        return LogSeverity.debug;
      case r'info':
        return LogSeverity.info;
      case r'warning':
        return LogSeverity.warning;
      case r'error':
        return LogSeverity.error;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(LogSeverity self) {
    switch (self) {
      case LogSeverity.debug:
        return r'debug';
      case LogSeverity.info:
        return r'info';
      case LogSeverity.warning:
        return r'warning';
      case LogSeverity.error:
        return r'error';
    }
  }
}

extension LogSeverityMapperExtension on LogSeverity {
  String toValue() {
    LogSeverityMapper.ensureInitialized();
    return MapperContainer.globals.toValue<LogSeverity>(this) as String;
  }
}

class SpanKindMapper extends EnumMapper<SpanKind> {
  SpanKindMapper._();

  static SpanKindMapper? _instance;
  static SpanKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SpanKindMapper._());
    }
    return _instance!;
  }

  static SpanKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  SpanKind decode(dynamic value) {
    switch (value) {
      case r'internal':
        return SpanKind.internal;
      case r'server':
        return SpanKind.server;
      case r'client':
        return SpanKind.client;
      case r'producer':
        return SpanKind.producer;
      case r'consumer':
        return SpanKind.consumer;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(SpanKind self) {
    switch (self) {
      case SpanKind.internal:
        return r'internal';
      case SpanKind.server:
        return r'server';
      case SpanKind.client:
        return r'client';
      case SpanKind.producer:
        return r'producer';
      case SpanKind.consumer:
        return r'consumer';
    }
  }
}

extension SpanKindMapperExtension on SpanKind {
  String toValue() {
    SpanKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<SpanKind>(this) as String;
  }
}

class SpanStatusMapper extends EnumMapper<SpanStatus> {
  SpanStatusMapper._();

  static SpanStatusMapper? _instance;
  static SpanStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SpanStatusMapper._());
    }
    return _instance!;
  }

  static SpanStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  SpanStatus decode(dynamic value) {
    switch (value) {
      case r'success':
        return SpanStatus.success;
      case r'error':
        return SpanStatus.error;
      case r'cancelled':
        return SpanStatus.cancelled;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(SpanStatus self) {
    switch (self) {
      case SpanStatus.success:
        return r'success';
      case SpanStatus.error:
        return r'error';
      case SpanStatus.cancelled:
        return r'cancelled';
    }
  }
}

extension SpanStatusMapperExtension on SpanStatus {
  String toValue() {
    SpanStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<SpanStatus>(this) as String;
  }
}

class MetricInstrumentMapper extends EnumMapper<MetricInstrument> {
  MetricInstrumentMapper._();

  static MetricInstrumentMapper? _instance;
  static MetricInstrumentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MetricInstrumentMapper._());
    }
    return _instance!;
  }

  static MetricInstrument fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  MetricInstrument decode(dynamic value) {
    switch (value) {
      case r'counter':
        return MetricInstrument.counter;
      case r'upDownCounter':
        return MetricInstrument.upDownCounter;
      case r'histogram':
        return MetricInstrument.histogram;
      case r'gauge':
        return MetricInstrument.gauge;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(MetricInstrument self) {
    switch (self) {
      case MetricInstrument.counter:
        return r'counter';
      case MetricInstrument.upDownCounter:
        return r'upDownCounter';
      case MetricInstrument.histogram:
        return r'histogram';
      case MetricInstrument.gauge:
        return r'gauge';
    }
  }
}

extension MetricInstrumentMapperExtension on MetricInstrument {
  String toValue() {
    MetricInstrumentMapper.ensureInitialized();
    return MapperContainer.globals.toValue<MetricInstrument>(this) as String;
  }
}

class MetricTemporalityMapper extends EnumMapper<MetricTemporality> {
  MetricTemporalityMapper._();

  static MetricTemporalityMapper? _instance;
  static MetricTemporalityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MetricTemporalityMapper._());
    }
    return _instance!;
  }

  static MetricTemporality fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  MetricTemporality decode(dynamic value) {
    switch (value) {
      case r'delta':
        return MetricTemporality.delta;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(MetricTemporality self) {
    switch (self) {
      case MetricTemporality.delta:
        return r'delta';
    }
  }
}

extension MetricTemporalityMapperExtension on MetricTemporality {
  String toValue() {
    MetricTemporalityMapper.ensureInitialized();
    return MapperContainer.globals.toValue<MetricTemporality>(this) as String;
  }
}

class RecordEnvelopeMapper extends ClassMapperBase<RecordEnvelope> {
  RecordEnvelopeMapper._();

  static RecordEnvelopeMapper? _instance;
  static RecordEnvelopeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecordEnvelopeMapper._());
      ChroniclerSourceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RecordEnvelope';

  static String _$eventId(RecordEnvelope v) => v.eventId;
  static const Field<RecordEnvelope, String> _f$eventId = Field(
    'eventId',
    _$eventId,
  );
  static String _$appId(RecordEnvelope v) => v.appId;
  static const Field<RecordEnvelope, String> _f$appId = Field('appId', _$appId);
  static String _$release(RecordEnvelope v) => v.release;
  static const Field<RecordEnvelope, String> _f$release = Field(
    'release',
    _$release,
  );
  static ChroniclerSource _$source(RecordEnvelope v) => v.source;
  static const Field<RecordEnvelope, ChroniclerSource> _f$source = Field(
    'source',
    _$source,
  );
  static DateTime _$timestamp(RecordEnvelope v) => v.timestamp;
  static const Field<RecordEnvelope, DateTime> _f$timestamp = Field(
    'timestamp',
    _$timestamp,
  );
  static String? _$buildId(RecordEnvelope v) => v.buildId;
  static const Field<RecordEnvelope, String> _f$buildId = Field(
    'buildId',
    _$buildId,
    opt: true,
  );
  static String? _$userId(RecordEnvelope v) => v.userId;
  static const Field<RecordEnvelope, String> _f$userId = Field(
    'userId',
    _$userId,
    opt: true,
  );
  static String? _$anonymousId(RecordEnvelope v) => v.anonymousId;
  static const Field<RecordEnvelope, String> _f$anonymousId = Field(
    'anonymousId',
    _$anonymousId,
    opt: true,
  );
  static String? _$sessionId(RecordEnvelope v) => v.sessionId;
  static const Field<RecordEnvelope, String> _f$sessionId = Field(
    'sessionId',
    _$sessionId,
    opt: true,
  );
  static String? _$traceId(RecordEnvelope v) => v.traceId;
  static const Field<RecordEnvelope, String> _f$traceId = Field(
    'traceId',
    _$traceId,
    opt: true,
  );
  static String? _$spanId(RecordEnvelope v) => v.spanId;
  static const Field<RecordEnvelope, String> _f$spanId = Field(
    'spanId',
    _$spanId,
    opt: true,
  );
  static String? _$parentSpanId(RecordEnvelope v) => v.parentSpanId;
  static const Field<RecordEnvelope, String> _f$parentSpanId = Field(
    'parentSpanId',
    _$parentSpanId,
    opt: true,
  );

  @override
  final MappableFields<RecordEnvelope> fields = const {
    #eventId: _f$eventId,
    #appId: _f$appId,
    #release: _f$release,
    #source: _f$source,
    #timestamp: _f$timestamp,
    #buildId: _f$buildId,
    #userId: _f$userId,
    #anonymousId: _f$anonymousId,
    #sessionId: _f$sessionId,
    #traceId: _f$traceId,
    #spanId: _f$spanId,
    #parentSpanId: _f$parentSpanId,
  };

  static RecordEnvelope _instantiate(DecodingData data) {
    return RecordEnvelope(
      eventId: data.dec(_f$eventId),
      appId: data.dec(_f$appId),
      release: data.dec(_f$release),
      source: data.dec(_f$source),
      timestamp: data.dec(_f$timestamp),
      buildId: data.dec(_f$buildId),
      userId: data.dec(_f$userId),
      anonymousId: data.dec(_f$anonymousId),
      sessionId: data.dec(_f$sessionId),
      traceId: data.dec(_f$traceId),
      spanId: data.dec(_f$spanId),
      parentSpanId: data.dec(_f$parentSpanId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RecordEnvelope fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RecordEnvelope>(map);
  }

  static RecordEnvelope fromJson(String json) {
    return ensureInitialized().decodeJson<RecordEnvelope>(json);
  }
}

mixin RecordEnvelopeMappable {
  String toJson() {
    return RecordEnvelopeMapper.ensureInitialized().encodeJson<RecordEnvelope>(
      this as RecordEnvelope,
    );
  }

  Map<String, dynamic> toMap() {
    return RecordEnvelopeMapper.ensureInitialized().encodeMap<RecordEnvelope>(
      this as RecordEnvelope,
    );
  }

  RecordEnvelopeCopyWith<RecordEnvelope, RecordEnvelope, RecordEnvelope>
  get copyWith => _RecordEnvelopeCopyWithImpl<RecordEnvelope, RecordEnvelope>(
    this as RecordEnvelope,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RecordEnvelopeMapper.ensureInitialized().stringifyValue(
      this as RecordEnvelope,
    );
  }

  @override
  bool operator ==(Object other) {
    return RecordEnvelopeMapper.ensureInitialized().equalsValue(
      this as RecordEnvelope,
      other,
    );
  }

  @override
  int get hashCode {
    return RecordEnvelopeMapper.ensureInitialized().hashValue(
      this as RecordEnvelope,
    );
  }
}

extension RecordEnvelopeValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RecordEnvelope, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, $Out> get $asRecordEnvelope =>
      $base.as((v, t, t2) => _RecordEnvelopeCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RecordEnvelopeCopyWith<$R, $In extends RecordEnvelope, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? eventId,
    String? appId,
    String? release,
    ChroniclerSource? source,
    DateTime? timestamp,
    String? buildId,
    String? userId,
    String? anonymousId,
    String? sessionId,
    String? traceId,
    String? spanId,
    String? parentSpanId,
  });
  RecordEnvelopeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RecordEnvelopeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RecordEnvelope, $Out>
    implements RecordEnvelopeCopyWith<$R, RecordEnvelope, $Out> {
  _RecordEnvelopeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RecordEnvelope> $mapper =
      RecordEnvelopeMapper.ensureInitialized();
  @override
  $R call({
    String? eventId,
    String? appId,
    String? release,
    ChroniclerSource? source,
    DateTime? timestamp,
    Object? buildId = $none,
    Object? userId = $none,
    Object? anonymousId = $none,
    Object? sessionId = $none,
    Object? traceId = $none,
    Object? spanId = $none,
    Object? parentSpanId = $none,
  }) => $apply(
    FieldCopyWithData({
      if (eventId != null) #eventId: eventId,
      if (appId != null) #appId: appId,
      if (release != null) #release: release,
      if (source != null) #source: source,
      if (timestamp != null) #timestamp: timestamp,
      if (buildId != $none) #buildId: buildId,
      if (userId != $none) #userId: userId,
      if (anonymousId != $none) #anonymousId: anonymousId,
      if (sessionId != $none) #sessionId: sessionId,
      if (traceId != $none) #traceId: traceId,
      if (spanId != $none) #spanId: spanId,
      if (parentSpanId != $none) #parentSpanId: parentSpanId,
    }),
  );
  @override
  RecordEnvelope $make(CopyWithData data) => RecordEnvelope(
    eventId: data.get(#eventId, or: $value.eventId),
    appId: data.get(#appId, or: $value.appId),
    release: data.get(#release, or: $value.release),
    source: data.get(#source, or: $value.source),
    timestamp: data.get(#timestamp, or: $value.timestamp),
    buildId: data.get(#buildId, or: $value.buildId),
    userId: data.get(#userId, or: $value.userId),
    anonymousId: data.get(#anonymousId, or: $value.anonymousId),
    sessionId: data.get(#sessionId, or: $value.sessionId),
    traceId: data.get(#traceId, or: $value.traceId),
    spanId: data.get(#spanId, or: $value.spanId),
    parentSpanId: data.get(#parentSpanId, or: $value.parentSpanId),
  );

  @override
  RecordEnvelopeCopyWith<$R2, RecordEnvelope, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RecordEnvelopeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ErrorDetailsMapper extends ClassMapperBase<ErrorDetails> {
  ErrorDetailsMapper._();

  static ErrorDetailsMapper? _instance;
  static ErrorDetailsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ErrorDetailsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ErrorDetails';

  static String _$type(ErrorDetails v) => v.type;
  static const Field<ErrorDetails, String> _f$type = Field('type', _$type);
  static String _$message(ErrorDetails v) => v.message;
  static const Field<ErrorDetails, String> _f$message = Field(
    'message',
    _$message,
  );
  static String? _$stackTrace(ErrorDetails v) => v.stackTrace;
  static const Field<ErrorDetails, String> _f$stackTrace = Field(
    'stackTrace',
    _$stackTrace,
    opt: true,
  );

  @override
  final MappableFields<ErrorDetails> fields = const {
    #type: _f$type,
    #message: _f$message,
    #stackTrace: _f$stackTrace,
  };

  static ErrorDetails _instantiate(DecodingData data) {
    return ErrorDetails(
      type: data.dec(_f$type),
      message: data.dec(_f$message),
      stackTrace: data.dec(_f$stackTrace),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ErrorDetails fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ErrorDetails>(map);
  }

  static ErrorDetails fromJson(String json) {
    return ensureInitialized().decodeJson<ErrorDetails>(json);
  }
}

mixin ErrorDetailsMappable {
  String toJson() {
    return ErrorDetailsMapper.ensureInitialized().encodeJson<ErrorDetails>(
      this as ErrorDetails,
    );
  }

  Map<String, dynamic> toMap() {
    return ErrorDetailsMapper.ensureInitialized().encodeMap<ErrorDetails>(
      this as ErrorDetails,
    );
  }

  ErrorDetailsCopyWith<ErrorDetails, ErrorDetails, ErrorDetails> get copyWith =>
      _ErrorDetailsCopyWithImpl<ErrorDetails, ErrorDetails>(
        this as ErrorDetails,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ErrorDetailsMapper.ensureInitialized().stringifyValue(
      this as ErrorDetails,
    );
  }

  @override
  bool operator ==(Object other) {
    return ErrorDetailsMapper.ensureInitialized().equalsValue(
      this as ErrorDetails,
      other,
    );
  }

  @override
  int get hashCode {
    return ErrorDetailsMapper.ensureInitialized().hashValue(
      this as ErrorDetails,
    );
  }
}

extension ErrorDetailsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ErrorDetails, $Out> {
  ErrorDetailsCopyWith<$R, ErrorDetails, $Out> get $asErrorDetails =>
      $base.as((v, t, t2) => _ErrorDetailsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ErrorDetailsCopyWith<$R, $In extends ErrorDetails, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? type, String? message, String? stackTrace});
  ErrorDetailsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ErrorDetailsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ErrorDetails, $Out>
    implements ErrorDetailsCopyWith<$R, ErrorDetails, $Out> {
  _ErrorDetailsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ErrorDetails> $mapper =
      ErrorDetailsMapper.ensureInitialized();
  @override
  $R call({String? type, String? message, Object? stackTrace = $none}) =>
      $apply(
        FieldCopyWithData({
          if (type != null) #type: type,
          if (message != null) #message: message,
          if (stackTrace != $none) #stackTrace: stackTrace,
        }),
      );
  @override
  ErrorDetails $make(CopyWithData data) => ErrorDetails(
    type: data.get(#type, or: $value.type),
    message: data.get(#message, or: $value.message),
    stackTrace: data.get(#stackTrace, or: $value.stackTrace),
  );

  @override
  ErrorDetailsCopyWith<$R2, ErrorDetails, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ErrorDetailsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LogPayloadMapper extends ClassMapperBase<LogPayload> {
  LogPayloadMapper._();

  static LogPayloadMapper? _instance;
  static LogPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LogPayloadMapper._());
      LogSeverityMapper.ensureInitialized();
      ErrorDetailsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LogPayload';

  static LogSeverity _$severity(LogPayload v) => v.severity;
  static const Field<LogPayload, LogSeverity> _f$severity = Field(
    'severity',
    _$severity,
  );
  static String _$message(LogPayload v) => v.message;
  static const Field<LogPayload, String> _f$message = Field(
    'message',
    _$message,
  );
  static Map<String, Object?> _$attributes(LogPayload v) => v.attributes;
  static const Field<LogPayload, Map<String, Object?>> _f$attributes = Field(
    'attributes',
    _$attributes,
    opt: true,
    def: const {},
  );
  static ErrorDetails? _$error(LogPayload v) => v.error;
  static const Field<LogPayload, ErrorDetails> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );
  static String? _$stackTrace(LogPayload v) => v.stackTrace;
  static const Field<LogPayload, String> _f$stackTrace = Field(
    'stackTrace',
    _$stackTrace,
    opt: true,
  );

  @override
  final MappableFields<LogPayload> fields = const {
    #severity: _f$severity,
    #message: _f$message,
    #attributes: _f$attributes,
    #error: _f$error,
    #stackTrace: _f$stackTrace,
  };

  static LogPayload _instantiate(DecodingData data) {
    return LogPayload(
      severity: data.dec(_f$severity),
      message: data.dec(_f$message),
      attributes: data.dec(_f$attributes),
      error: data.dec(_f$error),
      stackTrace: data.dec(_f$stackTrace),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LogPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LogPayload>(map);
  }

  static LogPayload fromJson(String json) {
    return ensureInitialized().decodeJson<LogPayload>(json);
  }
}

mixin LogPayloadMappable {
  String toJson() {
    return LogPayloadMapper.ensureInitialized().encodeJson<LogPayload>(
      this as LogPayload,
    );
  }

  Map<String, dynamic> toMap() {
    return LogPayloadMapper.ensureInitialized().encodeMap<LogPayload>(
      this as LogPayload,
    );
  }

  LogPayloadCopyWith<LogPayload, LogPayload, LogPayload> get copyWith =>
      _LogPayloadCopyWithImpl<LogPayload, LogPayload>(
        this as LogPayload,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LogPayloadMapper.ensureInitialized().stringifyValue(
      this as LogPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return LogPayloadMapper.ensureInitialized().equalsValue(
      this as LogPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return LogPayloadMapper.ensureInitialized().hashValue(this as LogPayload);
  }
}

extension LogPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LogPayload, $Out> {
  LogPayloadCopyWith<$R, LogPayload, $Out> get $asLogPayload =>
      $base.as((v, t, t2) => _LogPayloadCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LogPayloadCopyWith<$R, $In extends LogPayload, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes;
  ErrorDetailsCopyWith<$R, ErrorDetails, ErrorDetails>? get error;
  $R call({
    LogSeverity? severity,
    String? message,
    Map<String, Object?>? attributes,
    ErrorDetails? error,
    String? stackTrace,
  });
  LogPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LogPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LogPayload, $Out>
    implements LogPayloadCopyWith<$R, LogPayload, $Out> {
  _LogPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LogPayload> $mapper =
      LogPayloadMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes => MapCopyWith(
    $value.attributes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(attributes: v),
  );
  @override
  ErrorDetailsCopyWith<$R, ErrorDetails, ErrorDetails>? get error =>
      $value.error?.copyWith.$chain((v) => call(error: v));
  @override
  $R call({
    LogSeverity? severity,
    String? message,
    Map<String, Object?>? attributes,
    Object? error = $none,
    Object? stackTrace = $none,
  }) => $apply(
    FieldCopyWithData({
      if (severity != null) #severity: severity,
      if (message != null) #message: message,
      if (attributes != null) #attributes: attributes,
      if (error != $none) #error: error,
      if (stackTrace != $none) #stackTrace: stackTrace,
    }),
  );
  @override
  LogPayload $make(CopyWithData data) => LogPayload(
    severity: data.get(#severity, or: $value.severity),
    message: data.get(#message, or: $value.message),
    attributes: data.get(#attributes, or: $value.attributes),
    error: data.get(#error, or: $value.error),
    stackTrace: data.get(#stackTrace, or: $value.stackTrace),
  );

  @override
  LogPayloadCopyWith<$R2, LogPayload, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LogPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ProductEventPayloadMapper extends ClassMapperBase<ProductEventPayload> {
  ProductEventPayloadMapper._();

  static ProductEventPayloadMapper? _instance;
  static ProductEventPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProductEventPayloadMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProductEventPayload';

  static String _$name(ProductEventPayload v) => v.name;
  static const Field<ProductEventPayload, String> _f$name = Field(
    'name',
    _$name,
  );
  static Map<String, Object?> _$properties(ProductEventPayload v) =>
      v.properties;
  static const Field<ProductEventPayload, Map<String, Object?>> _f$properties =
      Field('properties', _$properties, opt: true, def: const {});

  @override
  final MappableFields<ProductEventPayload> fields = const {
    #name: _f$name,
    #properties: _f$properties,
  };

  static ProductEventPayload _instantiate(DecodingData data) {
    return ProductEventPayload(
      name: data.dec(_f$name),
      properties: data.dec(_f$properties),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProductEventPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProductEventPayload>(map);
  }

  static ProductEventPayload fromJson(String json) {
    return ensureInitialized().decodeJson<ProductEventPayload>(json);
  }
}

mixin ProductEventPayloadMappable {
  String toJson() {
    return ProductEventPayloadMapper.ensureInitialized()
        .encodeJson<ProductEventPayload>(this as ProductEventPayload);
  }

  Map<String, dynamic> toMap() {
    return ProductEventPayloadMapper.ensureInitialized()
        .encodeMap<ProductEventPayload>(this as ProductEventPayload);
  }

  ProductEventPayloadCopyWith<
    ProductEventPayload,
    ProductEventPayload,
    ProductEventPayload
  >
  get copyWith =>
      _ProductEventPayloadCopyWithImpl<
        ProductEventPayload,
        ProductEventPayload
      >(this as ProductEventPayload, $identity, $identity);
  @override
  String toString() {
    return ProductEventPayloadMapper.ensureInitialized().stringifyValue(
      this as ProductEventPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProductEventPayloadMapper.ensureInitialized().equalsValue(
      this as ProductEventPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return ProductEventPayloadMapper.ensureInitialized().hashValue(
      this as ProductEventPayload,
    );
  }
}

extension ProductEventPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProductEventPayload, $Out> {
  ProductEventPayloadCopyWith<$R, ProductEventPayload, $Out>
  get $asProductEventPayload => $base.as(
    (v, t, t2) => _ProductEventPayloadCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ProductEventPayloadCopyWith<
  $R,
  $In extends ProductEventPayload,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get properties;
  $R call({String? name, Map<String, Object?>? properties});
  ProductEventPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ProductEventPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProductEventPayload, $Out>
    implements ProductEventPayloadCopyWith<$R, ProductEventPayload, $Out> {
  _ProductEventPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProductEventPayload> $mapper =
      ProductEventPayloadMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get properties => MapCopyWith(
    $value.properties,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(properties: v),
  );
  @override
  $R call({String? name, Map<String, Object?>? properties}) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (properties != null) #properties: properties,
    }),
  );
  @override
  ProductEventPayload $make(CopyWithData data) => ProductEventPayload(
    name: data.get(#name, or: $value.name),
    properties: data.get(#properties, or: $value.properties),
  );

  @override
  ProductEventPayloadCopyWith<$R2, ProductEventPayload, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ProductEventPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IdentityLinkPayloadMapper extends ClassMapperBase<IdentityLinkPayload> {
  IdentityLinkPayloadMapper._();

  static IdentityLinkPayloadMapper? _instance;
  static IdentityLinkPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IdentityLinkPayloadMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'IdentityLinkPayload';

  static String _$anonymousId(IdentityLinkPayload v) => v.anonymousId;
  static const Field<IdentityLinkPayload, String> _f$anonymousId = Field(
    'anonymousId',
    _$anonymousId,
  );
  static String _$userId(IdentityLinkPayload v) => v.userId;
  static const Field<IdentityLinkPayload, String> _f$userId = Field(
    'userId',
    _$userId,
  );

  @override
  final MappableFields<IdentityLinkPayload> fields = const {
    #anonymousId: _f$anonymousId,
    #userId: _f$userId,
  };

  static IdentityLinkPayload _instantiate(DecodingData data) {
    return IdentityLinkPayload(
      anonymousId: data.dec(_f$anonymousId),
      userId: data.dec(_f$userId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IdentityLinkPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IdentityLinkPayload>(map);
  }

  static IdentityLinkPayload fromJson(String json) {
    return ensureInitialized().decodeJson<IdentityLinkPayload>(json);
  }
}

mixin IdentityLinkPayloadMappable {
  String toJson() {
    return IdentityLinkPayloadMapper.ensureInitialized()
        .encodeJson<IdentityLinkPayload>(this as IdentityLinkPayload);
  }

  Map<String, dynamic> toMap() {
    return IdentityLinkPayloadMapper.ensureInitialized()
        .encodeMap<IdentityLinkPayload>(this as IdentityLinkPayload);
  }

  IdentityLinkPayloadCopyWith<
    IdentityLinkPayload,
    IdentityLinkPayload,
    IdentityLinkPayload
  >
  get copyWith =>
      _IdentityLinkPayloadCopyWithImpl<
        IdentityLinkPayload,
        IdentityLinkPayload
      >(this as IdentityLinkPayload, $identity, $identity);
  @override
  String toString() {
    return IdentityLinkPayloadMapper.ensureInitialized().stringifyValue(
      this as IdentityLinkPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return IdentityLinkPayloadMapper.ensureInitialized().equalsValue(
      this as IdentityLinkPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return IdentityLinkPayloadMapper.ensureInitialized().hashValue(
      this as IdentityLinkPayload,
    );
  }
}

extension IdentityLinkPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IdentityLinkPayload, $Out> {
  IdentityLinkPayloadCopyWith<$R, IdentityLinkPayload, $Out>
  get $asIdentityLinkPayload => $base.as(
    (v, t, t2) => _IdentityLinkPayloadCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class IdentityLinkPayloadCopyWith<
  $R,
  $In extends IdentityLinkPayload,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? anonymousId, String? userId});
  IdentityLinkPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _IdentityLinkPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IdentityLinkPayload, $Out>
    implements IdentityLinkPayloadCopyWith<$R, IdentityLinkPayload, $Out> {
  _IdentityLinkPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IdentityLinkPayload> $mapper =
      IdentityLinkPayloadMapper.ensureInitialized();
  @override
  $R call({String? anonymousId, String? userId}) => $apply(
    FieldCopyWithData({
      if (anonymousId != null) #anonymousId: anonymousId,
      if (userId != null) #userId: userId,
    }),
  );
  @override
  IdentityLinkPayload $make(CopyWithData data) => IdentityLinkPayload(
    anonymousId: data.get(#anonymousId, or: $value.anonymousId),
    userId: data.get(#userId, or: $value.userId),
  );

  @override
  IdentityLinkPayloadCopyWith<$R2, IdentityLinkPayload, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _IdentityLinkPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class UserPropertiesSetPayloadMapper
    extends ClassMapperBase<UserPropertiesSetPayload> {
  UserPropertiesSetPayloadMapper._();

  static UserPropertiesSetPayloadMapper? _instance;
  static UserPropertiesSetPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = UserPropertiesSetPayloadMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'UserPropertiesSetPayload';

  static String _$userId(UserPropertiesSetPayload v) => v.userId;
  static const Field<UserPropertiesSetPayload, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static Map<String, Object?> _$properties(UserPropertiesSetPayload v) =>
      v.properties;
  static const Field<UserPropertiesSetPayload, Map<String, Object?>>
  _f$properties = Field('properties', _$properties);

  @override
  final MappableFields<UserPropertiesSetPayload> fields = const {
    #userId: _f$userId,
    #properties: _f$properties,
  };

  static UserPropertiesSetPayload _instantiate(DecodingData data) {
    return UserPropertiesSetPayload(
      userId: data.dec(_f$userId),
      properties: data.dec(_f$properties),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static UserPropertiesSetPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UserPropertiesSetPayload>(map);
  }

  static UserPropertiesSetPayload fromJson(String json) {
    return ensureInitialized().decodeJson<UserPropertiesSetPayload>(json);
  }
}

mixin UserPropertiesSetPayloadMappable {
  String toJson() {
    return UserPropertiesSetPayloadMapper.ensureInitialized()
        .encodeJson<UserPropertiesSetPayload>(this as UserPropertiesSetPayload);
  }

  Map<String, dynamic> toMap() {
    return UserPropertiesSetPayloadMapper.ensureInitialized()
        .encodeMap<UserPropertiesSetPayload>(this as UserPropertiesSetPayload);
  }

  UserPropertiesSetPayloadCopyWith<
    UserPropertiesSetPayload,
    UserPropertiesSetPayload,
    UserPropertiesSetPayload
  >
  get copyWith =>
      _UserPropertiesSetPayloadCopyWithImpl<
        UserPropertiesSetPayload,
        UserPropertiesSetPayload
      >(this as UserPropertiesSetPayload, $identity, $identity);
  @override
  String toString() {
    return UserPropertiesSetPayloadMapper.ensureInitialized().stringifyValue(
      this as UserPropertiesSetPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return UserPropertiesSetPayloadMapper.ensureInitialized().equalsValue(
      this as UserPropertiesSetPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return UserPropertiesSetPayloadMapper.ensureInitialized().hashValue(
      this as UserPropertiesSetPayload,
    );
  }
}

extension UserPropertiesSetPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, UserPropertiesSetPayload, $Out> {
  UserPropertiesSetPayloadCopyWith<$R, UserPropertiesSetPayload, $Out>
  get $asUserPropertiesSetPayload => $base.as(
    (v, t, t2) => _UserPropertiesSetPayloadCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class UserPropertiesSetPayloadCopyWith<
  $R,
  $In extends UserPropertiesSetPayload,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get properties;
  $R call({String? userId, Map<String, Object?>? properties});
  UserPropertiesSetPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _UserPropertiesSetPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, UserPropertiesSetPayload, $Out>
    implements
        UserPropertiesSetPayloadCopyWith<$R, UserPropertiesSetPayload, $Out> {
  _UserPropertiesSetPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<UserPropertiesSetPayload> $mapper =
      UserPropertiesSetPayloadMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get properties => MapCopyWith(
    $value.properties,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(properties: v),
  );
  @override
  $R call({String? userId, Map<String, Object?>? properties}) => $apply(
    FieldCopyWithData({
      if (userId != null) #userId: userId,
      if (properties != null) #properties: properties,
    }),
  );
  @override
  UserPropertiesSetPayload $make(CopyWithData data) => UserPropertiesSetPayload(
    userId: data.get(#userId, or: $value.userId),
    properties: data.get(#properties, or: $value.properties),
  );

  @override
  UserPropertiesSetPayloadCopyWith<$R2, UserPropertiesSetPayload, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _UserPropertiesSetPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class UserPropertiesUnsetPayloadMapper
    extends ClassMapperBase<UserPropertiesUnsetPayload> {
  UserPropertiesUnsetPayloadMapper._();

  static UserPropertiesUnsetPayloadMapper? _instance;
  static UserPropertiesUnsetPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = UserPropertiesUnsetPayloadMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'UserPropertiesUnsetPayload';

  static String _$userId(UserPropertiesUnsetPayload v) => v.userId;
  static const Field<UserPropertiesUnsetPayload, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static List<String> _$keys(UserPropertiesUnsetPayload v) => v.keys;
  static dynamic _arg$keys(f) => f<List<String>>();
  static const Field<UserPropertiesUnsetPayload, Iterable<String>> _f$keys =
      Field('keys', _$keys, arg: _arg$keys);

  @override
  final MappableFields<UserPropertiesUnsetPayload> fields = const {
    #userId: _f$userId,
    #keys: _f$keys,
  };

  static UserPropertiesUnsetPayload _instantiate(DecodingData data) {
    return UserPropertiesUnsetPayload(
      userId: data.dec(_f$userId),
      keys: data.dec(_f$keys),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static UserPropertiesUnsetPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UserPropertiesUnsetPayload>(map);
  }

  static UserPropertiesUnsetPayload fromJson(String json) {
    return ensureInitialized().decodeJson<UserPropertiesUnsetPayload>(json);
  }
}

mixin UserPropertiesUnsetPayloadMappable {
  String toJson() {
    return UserPropertiesUnsetPayloadMapper.ensureInitialized()
        .encodeJson<UserPropertiesUnsetPayload>(
          this as UserPropertiesUnsetPayload,
        );
  }

  Map<String, dynamic> toMap() {
    return UserPropertiesUnsetPayloadMapper.ensureInitialized()
        .encodeMap<UserPropertiesUnsetPayload>(
          this as UserPropertiesUnsetPayload,
        );
  }

  UserPropertiesUnsetPayloadCopyWith<
    UserPropertiesUnsetPayload,
    UserPropertiesUnsetPayload,
    UserPropertiesUnsetPayload
  >
  get copyWith =>
      _UserPropertiesUnsetPayloadCopyWithImpl<
        UserPropertiesUnsetPayload,
        UserPropertiesUnsetPayload
      >(this as UserPropertiesUnsetPayload, $identity, $identity);
  @override
  String toString() {
    return UserPropertiesUnsetPayloadMapper.ensureInitialized().stringifyValue(
      this as UserPropertiesUnsetPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return UserPropertiesUnsetPayloadMapper.ensureInitialized().equalsValue(
      this as UserPropertiesUnsetPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return UserPropertiesUnsetPayloadMapper.ensureInitialized().hashValue(
      this as UserPropertiesUnsetPayload,
    );
  }
}

extension UserPropertiesUnsetPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, UserPropertiesUnsetPayload, $Out> {
  UserPropertiesUnsetPayloadCopyWith<$R, UserPropertiesUnsetPayload, $Out>
  get $asUserPropertiesUnsetPayload => $base.as(
    (v, t, t2) => _UserPropertiesUnsetPayloadCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class UserPropertiesUnsetPayloadCopyWith<
  $R,
  $In extends UserPropertiesUnsetPayload,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? userId, Iterable<String>? keys});
  UserPropertiesUnsetPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _UserPropertiesUnsetPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, UserPropertiesUnsetPayload, $Out>
    implements
        UserPropertiesUnsetPayloadCopyWith<
          $R,
          UserPropertiesUnsetPayload,
          $Out
        > {
  _UserPropertiesUnsetPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<UserPropertiesUnsetPayload> $mapper =
      UserPropertiesUnsetPayloadMapper.ensureInitialized();
  @override
  $R call({String? userId, Iterable<String>? keys}) => $apply(
    FieldCopyWithData({
      if (userId != null) #userId: userId,
      if (keys != null) #keys: keys,
    }),
  );
  @override
  UserPropertiesUnsetPayload $make(CopyWithData data) =>
      UserPropertiesUnsetPayload(
        userId: data.get(#userId, or: $value.userId),
        keys: data.get(#keys, or: $value.keys),
      );

  @override
  UserPropertiesUnsetPayloadCopyWith<$R2, UserPropertiesUnsetPayload, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _UserPropertiesUnsetPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SpanPayloadMapper extends ClassMapperBase<SpanPayload> {
  SpanPayloadMapper._();

  static SpanPayloadMapper? _instance;
  static SpanPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SpanPayloadMapper._());
      SpanKindMapper.ensureInitialized();
      SpanStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SpanPayload';

  static String _$name(SpanPayload v) => v.name;
  static const Field<SpanPayload, String> _f$name = Field('name', _$name);
  static SpanKind _$spanKind(SpanPayload v) => v.spanKind;
  static const Field<SpanPayload, SpanKind> _f$spanKind = Field(
    'spanKind',
    _$spanKind,
  );
  static SpanStatus _$status(SpanPayload v) => v.status;
  static const Field<SpanPayload, SpanStatus> _f$status = Field(
    'status',
    _$status,
  );
  static int _$durationMicros(SpanPayload v) => v.durationMicros;
  static const Field<SpanPayload, int> _f$durationMicros = Field(
    'durationMicros',
    _$durationMicros,
  );
  static Map<String, Object?> _$attributes(SpanPayload v) => v.attributes;
  static const Field<SpanPayload, Map<String, Object?>> _f$attributes = Field(
    'attributes',
    _$attributes,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<SpanPayload> fields = const {
    #name: _f$name,
    #spanKind: _f$spanKind,
    #status: _f$status,
    #durationMicros: _f$durationMicros,
    #attributes: _f$attributes,
  };

  static SpanPayload _instantiate(DecodingData data) {
    return SpanPayload(
      name: data.dec(_f$name),
      spanKind: data.dec(_f$spanKind),
      status: data.dec(_f$status),
      durationMicros: data.dec(_f$durationMicros),
      attributes: data.dec(_f$attributes),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SpanPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SpanPayload>(map);
  }

  static SpanPayload fromJson(String json) {
    return ensureInitialized().decodeJson<SpanPayload>(json);
  }
}

mixin SpanPayloadMappable {
  String toJson() {
    return SpanPayloadMapper.ensureInitialized().encodeJson<SpanPayload>(
      this as SpanPayload,
    );
  }

  Map<String, dynamic> toMap() {
    return SpanPayloadMapper.ensureInitialized().encodeMap<SpanPayload>(
      this as SpanPayload,
    );
  }

  SpanPayloadCopyWith<SpanPayload, SpanPayload, SpanPayload> get copyWith =>
      _SpanPayloadCopyWithImpl<SpanPayload, SpanPayload>(
        this as SpanPayload,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SpanPayloadMapper.ensureInitialized().stringifyValue(
      this as SpanPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return SpanPayloadMapper.ensureInitialized().equalsValue(
      this as SpanPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return SpanPayloadMapper.ensureInitialized().hashValue(this as SpanPayload);
  }
}

extension SpanPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SpanPayload, $Out> {
  SpanPayloadCopyWith<$R, SpanPayload, $Out> get $asSpanPayload =>
      $base.as((v, t, t2) => _SpanPayloadCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SpanPayloadCopyWith<$R, $In extends SpanPayload, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes;
  $R call({
    String? name,
    SpanKind? spanKind,
    SpanStatus? status,
    int? durationMicros,
    Map<String, Object?>? attributes,
  });
  SpanPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SpanPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SpanPayload, $Out>
    implements SpanPayloadCopyWith<$R, SpanPayload, $Out> {
  _SpanPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SpanPayload> $mapper =
      SpanPayloadMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes => MapCopyWith(
    $value.attributes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(attributes: v),
  );
  @override
  $R call({
    String? name,
    SpanKind? spanKind,
    SpanStatus? status,
    int? durationMicros,
    Map<String, Object?>? attributes,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (spanKind != null) #spanKind: spanKind,
      if (status != null) #status: status,
      if (durationMicros != null) #durationMicros: durationMicros,
      if (attributes != null) #attributes: attributes,
    }),
  );
  @override
  SpanPayload $make(CopyWithData data) => SpanPayload(
    name: data.get(#name, or: $value.name),
    spanKind: data.get(#spanKind, or: $value.spanKind),
    status: data.get(#status, or: $value.status),
    durationMicros: data.get(#durationMicros, or: $value.durationMicros),
    attributes: data.get(#attributes, or: $value.attributes),
  );

  @override
  SpanPayloadCopyWith<$R2, SpanPayload, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SpanPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ErrorPayloadMapper extends ClassMapperBase<ErrorPayload> {
  ErrorPayloadMapper._();

  static ErrorPayloadMapper? _instance;
  static ErrorPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ErrorPayloadMapper._());
      ErrorDetailsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ErrorPayload';

  static ErrorDetails _$error(ErrorPayload v) => v.error;
  static const Field<ErrorPayload, ErrorDetails> _f$error = Field(
    'error',
    _$error,
  );
  static bool _$handled(ErrorPayload v) => v.handled;
  static const Field<ErrorPayload, bool> _f$handled = Field(
    'handled',
    _$handled,
  );
  static List<ErrorDetails> _$causes(ErrorPayload v) => v.causes;
  static dynamic _arg$causes(f) => f<List<ErrorDetails>>();
  static const Field<ErrorPayload, Iterable<ErrorDetails>> _f$causes = Field(
    'causes',
    _$causes,
    opt: true,
    def: const [],
    arg: _arg$causes,
  );
  static Map<String, Object?> _$attributes(ErrorPayload v) => v.attributes;
  static const Field<ErrorPayload, Map<String, Object?>> _f$attributes = Field(
    'attributes',
    _$attributes,
    opt: true,
    def: const {},
  );

  @override
  final MappableFields<ErrorPayload> fields = const {
    #error: _f$error,
    #handled: _f$handled,
    #causes: _f$causes,
    #attributes: _f$attributes,
  };

  static ErrorPayload _instantiate(DecodingData data) {
    return ErrorPayload(
      error: data.dec(_f$error),
      handled: data.dec(_f$handled),
      causes: data.dec(_f$causes),
      attributes: data.dec(_f$attributes),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ErrorPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ErrorPayload>(map);
  }

  static ErrorPayload fromJson(String json) {
    return ensureInitialized().decodeJson<ErrorPayload>(json);
  }
}

mixin ErrorPayloadMappable {
  String toJson() {
    return ErrorPayloadMapper.ensureInitialized().encodeJson<ErrorPayload>(
      this as ErrorPayload,
    );
  }

  Map<String, dynamic> toMap() {
    return ErrorPayloadMapper.ensureInitialized().encodeMap<ErrorPayload>(
      this as ErrorPayload,
    );
  }

  ErrorPayloadCopyWith<ErrorPayload, ErrorPayload, ErrorPayload> get copyWith =>
      _ErrorPayloadCopyWithImpl<ErrorPayload, ErrorPayload>(
        this as ErrorPayload,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ErrorPayloadMapper.ensureInitialized().stringifyValue(
      this as ErrorPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return ErrorPayloadMapper.ensureInitialized().equalsValue(
      this as ErrorPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return ErrorPayloadMapper.ensureInitialized().hashValue(
      this as ErrorPayload,
    );
  }
}

extension ErrorPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ErrorPayload, $Out> {
  ErrorPayloadCopyWith<$R, ErrorPayload, $Out> get $asErrorPayload =>
      $base.as((v, t, t2) => _ErrorPayloadCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ErrorPayloadCopyWith<$R, $In extends ErrorPayload, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ErrorDetailsCopyWith<$R, ErrorDetails, ErrorDetails> get error;
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes;
  $R call({
    ErrorDetails? error,
    bool? handled,
    Iterable<ErrorDetails>? causes,
    Map<String, Object?>? attributes,
  });
  ErrorPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ErrorPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ErrorPayload, $Out>
    implements ErrorPayloadCopyWith<$R, ErrorPayload, $Out> {
  _ErrorPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ErrorPayload> $mapper =
      ErrorPayloadMapper.ensureInitialized();
  @override
  ErrorDetailsCopyWith<$R, ErrorDetails, ErrorDetails> get error =>
      $value.error.copyWith.$chain((v) => call(error: v));
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes => MapCopyWith(
    $value.attributes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(attributes: v),
  );
  @override
  $R call({
    ErrorDetails? error,
    bool? handled,
    Iterable<ErrorDetails>? causes,
    Map<String, Object?>? attributes,
  }) => $apply(
    FieldCopyWithData({
      if (error != null) #error: error,
      if (handled != null) #handled: handled,
      if (causes != null) #causes: causes,
      if (attributes != null) #attributes: attributes,
    }),
  );
  @override
  ErrorPayload $make(CopyWithData data) => ErrorPayload(
    error: data.get(#error, or: $value.error),
    handled: data.get(#handled, or: $value.handled),
    causes: data.get(#causes, or: $value.causes),
    attributes: data.get(#attributes, or: $value.attributes),
  );

  @override
  ErrorPayloadCopyWith<$R2, ErrorPayload, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ErrorPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class MetricPayloadMapper extends ClassMapperBase<MetricPayload> {
  MetricPayloadMapper._();

  static MetricPayloadMapper? _instance;
  static MetricPayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MetricPayloadMapper._());
      MetricInstrumentMapper.ensureInitialized();
      MetricTemporalityMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'MetricPayload';

  static String _$name(MetricPayload v) => v.name;
  static const Field<MetricPayload, String> _f$name = Field('name', _$name);
  static MetricInstrument _$instrument(MetricPayload v) => v.instrument;
  static const Field<MetricPayload, MetricInstrument> _f$instrument = Field(
    'instrument',
    _$instrument,
  );
  static String _$unit(MetricPayload v) => v.unit;
  static const Field<MetricPayload, String> _f$unit = Field('unit', _$unit);
  static DateTime _$intervalStart(MetricPayload v) => v.intervalStart;
  static const Field<MetricPayload, DateTime> _f$intervalStart = Field(
    'intervalStart',
    _$intervalStart,
  );
  static DateTime _$intervalEnd(MetricPayload v) => v.intervalEnd;
  static const Field<MetricPayload, DateTime> _f$intervalEnd = Field(
    'intervalEnd',
    _$intervalEnd,
  );
  static int _$durationMicros(MetricPayload v) => v.durationMicros;
  static const Field<MetricPayload, int> _f$durationMicros = Field(
    'durationMicros',
    _$durationMicros,
  );
  static int _$observationCount(MetricPayload v) => v.observationCount;
  static const Field<MetricPayload, int> _f$observationCount = Field(
    'observationCount',
    _$observationCount,
  );
  static Map<String, Object?> _$attributes(MetricPayload v) => v.attributes;
  static const Field<MetricPayload, Map<String, Object?>> _f$attributes = Field(
    'attributes',
    _$attributes,
    opt: true,
    def: const {},
  );
  static MetricTemporality? _$temporality(MetricPayload v) => v.temporality;
  static const Field<MetricPayload, MetricTemporality> _f$temporality = Field(
    'temporality',
    _$temporality,
    opt: true,
  );
  static double? _$sum(MetricPayload v) => v.sum;
  static const Field<MetricPayload, double> _f$sum = Field(
    'sum',
    _$sum,
    opt: true,
  );
  static List<double>? _$boundaries(MetricPayload v) => v.boundaries;
  static dynamic _arg$boundaries(f) => f<List<double>>();
  static const Field<MetricPayload, Iterable<double>> _f$boundaries = Field(
    'boundaries',
    _$boundaries,
    opt: true,
    arg: _arg$boundaries,
  );
  static List<int>? _$bucketCounts(MetricPayload v) => v.bucketCounts;
  static dynamic _arg$bucketCounts(f) => f<List<int>>();
  static const Field<MetricPayload, Iterable<int>> _f$bucketCounts = Field(
    'bucketCounts',
    _$bucketCounts,
    opt: true,
    arg: _arg$bucketCounts,
  );
  static int? _$count(MetricPayload v) => v.count;
  static const Field<MetricPayload, int> _f$count = Field(
    'count',
    _$count,
    opt: true,
  );
  static double? _$min(MetricPayload v) => v.min;
  static const Field<MetricPayload, double> _f$min = Field(
    'min',
    _$min,
    opt: true,
  );
  static double? _$max(MetricPayload v) => v.max;
  static const Field<MetricPayload, double> _f$max = Field(
    'max',
    _$max,
    opt: true,
  );
  static double? _$value(MetricPayload v) => v.value;
  static const Field<MetricPayload, double> _f$value = Field(
    'value',
    _$value,
    opt: true,
  );
  static DateTime? _$observedAt(MetricPayload v) => v.observedAt;
  static const Field<MetricPayload, DateTime> _f$observedAt = Field(
    'observedAt',
    _$observedAt,
    opt: true,
  );

  @override
  final MappableFields<MetricPayload> fields = const {
    #name: _f$name,
    #instrument: _f$instrument,
    #unit: _f$unit,
    #intervalStart: _f$intervalStart,
    #intervalEnd: _f$intervalEnd,
    #durationMicros: _f$durationMicros,
    #observationCount: _f$observationCount,
    #attributes: _f$attributes,
    #temporality: _f$temporality,
    #sum: _f$sum,
    #boundaries: _f$boundaries,
    #bucketCounts: _f$bucketCounts,
    #count: _f$count,
    #min: _f$min,
    #max: _f$max,
    #value: _f$value,
    #observedAt: _f$observedAt,
  };

  static MetricPayload _instantiate(DecodingData data) {
    return MetricPayload(
      name: data.dec(_f$name),
      instrument: data.dec(_f$instrument),
      unit: data.dec(_f$unit),
      intervalStart: data.dec(_f$intervalStart),
      intervalEnd: data.dec(_f$intervalEnd),
      durationMicros: data.dec(_f$durationMicros),
      observationCount: data.dec(_f$observationCount),
      attributes: data.dec(_f$attributes),
      temporality: data.dec(_f$temporality),
      sum: data.dec(_f$sum),
      boundaries: data.dec(_f$boundaries),
      bucketCounts: data.dec(_f$bucketCounts),
      count: data.dec(_f$count),
      min: data.dec(_f$min),
      max: data.dec(_f$max),
      value: data.dec(_f$value),
      observedAt: data.dec(_f$observedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MetricPayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MetricPayload>(map);
  }

  static MetricPayload fromJson(String json) {
    return ensureInitialized().decodeJson<MetricPayload>(json);
  }
}

mixin MetricPayloadMappable {
  String toJson() {
    return MetricPayloadMapper.ensureInitialized().encodeJson<MetricPayload>(
      this as MetricPayload,
    );
  }

  Map<String, dynamic> toMap() {
    return MetricPayloadMapper.ensureInitialized().encodeMap<MetricPayload>(
      this as MetricPayload,
    );
  }

  MetricPayloadCopyWith<MetricPayload, MetricPayload, MetricPayload>
  get copyWith => _MetricPayloadCopyWithImpl<MetricPayload, MetricPayload>(
    this as MetricPayload,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return MetricPayloadMapper.ensureInitialized().stringifyValue(
      this as MetricPayload,
    );
  }

  @override
  bool operator ==(Object other) {
    return MetricPayloadMapper.ensureInitialized().equalsValue(
      this as MetricPayload,
      other,
    );
  }

  @override
  int get hashCode {
    return MetricPayloadMapper.ensureInitialized().hashValue(
      this as MetricPayload,
    );
  }
}

extension MetricPayloadValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MetricPayload, $Out> {
  MetricPayloadCopyWith<$R, MetricPayload, $Out> get $asMetricPayload =>
      $base.as((v, t, t2) => _MetricPayloadCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MetricPayloadCopyWith<$R, $In extends MetricPayload, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes;
  $R call({
    String? name,
    MetricInstrument? instrument,
    String? unit,
    DateTime? intervalStart,
    DateTime? intervalEnd,
    int? durationMicros,
    int? observationCount,
    Map<String, Object?>? attributes,
    MetricTemporality? temporality,
    double? sum,
    Iterable<double>? boundaries,
    Iterable<int>? bucketCounts,
    int? count,
    double? min,
    double? max,
    double? value,
    DateTime? observedAt,
  });
  MetricPayloadCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MetricPayloadCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MetricPayload, $Out>
    implements MetricPayloadCopyWith<$R, MetricPayload, $Out> {
  _MetricPayloadCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MetricPayload> $mapper =
      MetricPayloadMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get attributes => MapCopyWith(
    $value.attributes,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(attributes: v),
  );
  @override
  $R call({
    String? name,
    MetricInstrument? instrument,
    String? unit,
    DateTime? intervalStart,
    DateTime? intervalEnd,
    int? durationMicros,
    int? observationCount,
    Map<String, Object?>? attributes,
    Object? temporality = $none,
    Object? sum = $none,
    Object? boundaries = $none,
    Object? bucketCounts = $none,
    Object? count = $none,
    Object? min = $none,
    Object? max = $none,
    Object? value = $none,
    Object? observedAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (instrument != null) #instrument: instrument,
      if (unit != null) #unit: unit,
      if (intervalStart != null) #intervalStart: intervalStart,
      if (intervalEnd != null) #intervalEnd: intervalEnd,
      if (durationMicros != null) #durationMicros: durationMicros,
      if (observationCount != null) #observationCount: observationCount,
      if (attributes != null) #attributes: attributes,
      if (temporality != $none) #temporality: temporality,
      if (sum != $none) #sum: sum,
      if (boundaries != $none) #boundaries: boundaries,
      if (bucketCounts != $none) #bucketCounts: bucketCounts,
      if (count != $none) #count: count,
      if (min != $none) #min: min,
      if (max != $none) #max: max,
      if (value != $none) #value: value,
      if (observedAt != $none) #observedAt: observedAt,
    }),
  );
  @override
  MetricPayload $make(CopyWithData data) => MetricPayload(
    name: data.get(#name, or: $value.name),
    instrument: data.get(#instrument, or: $value.instrument),
    unit: data.get(#unit, or: $value.unit),
    intervalStart: data.get(#intervalStart, or: $value.intervalStart),
    intervalEnd: data.get(#intervalEnd, or: $value.intervalEnd),
    durationMicros: data.get(#durationMicros, or: $value.durationMicros),
    observationCount: data.get(#observationCount, or: $value.observationCount),
    attributes: data.get(#attributes, or: $value.attributes),
    temporality: data.get(#temporality, or: $value.temporality),
    sum: data.get(#sum, or: $value.sum),
    boundaries: data.get(#boundaries, or: $value.boundaries),
    bucketCounts: data.get(#bucketCounts, or: $value.bucketCounts),
    count: data.get(#count, or: $value.count),
    min: data.get(#min, or: $value.min),
    max: data.get(#max, or: $value.max),
    value: data.get(#value, or: $value.value),
    observedAt: data.get(#observedAt, or: $value.observedAt),
  );

  @override
  MetricPayloadCopyWith<$R2, MetricPayload, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MetricPayloadCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LogRecordMapper extends ClassMapperBase<LogRecord> {
  LogRecordMapper._();

  static LogRecordMapper? _instance;
  static LogRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LogRecordMapper._());
      RecordEnvelopeMapper.ensureInitialized();
      LogPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LogRecord';

  static RecordEnvelope _$envelope(LogRecord v) => v.envelope;
  static const Field<LogRecord, RecordEnvelope> _f$envelope = Field(
    'envelope',
    _$envelope,
  );
  static LogPayload _$payload(LogRecord v) => v.payload;
  static const Field<LogRecord, LogPayload> _f$payload = Field(
    'payload',
    _$payload,
  );

  @override
  final MappableFields<LogRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static LogRecord _instantiate(DecodingData data) {
    return LogRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LogRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LogRecord>(map);
  }

  static LogRecord fromJson(String json) {
    return ensureInitialized().decodeJson<LogRecord>(json);
  }
}

mixin LogRecordMappable {
  String toJson() {
    return LogRecordMapper.ensureInitialized().encodeJson<LogRecord>(
      this as LogRecord,
    );
  }

  Map<String, dynamic> toMap() {
    return LogRecordMapper.ensureInitialized().encodeMap<LogRecord>(
      this as LogRecord,
    );
  }

  LogRecordCopyWith<LogRecord, LogRecord, LogRecord> get copyWith =>
      _LogRecordCopyWithImpl<LogRecord, LogRecord>(
        this as LogRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LogRecordMapper.ensureInitialized().stringifyValue(
      this as LogRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return LogRecordMapper.ensureInitialized().equalsValue(
      this as LogRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return LogRecordMapper.ensureInitialized().hashValue(this as LogRecord);
  }
}

extension LogRecordValueCopy<$R, $Out> on ObjectCopyWith<$R, LogRecord, $Out> {
  LogRecordCopyWith<$R, LogRecord, $Out> get $asLogRecord =>
      $base.as((v, t, t2) => _LogRecordCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LogRecordCopyWith<$R, $In extends LogRecord, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  LogPayloadCopyWith<$R, LogPayload, LogPayload> get payload;
  $R call({RecordEnvelope? envelope, LogPayload? payload});
  LogRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LogRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LogRecord, $Out>
    implements LogRecordCopyWith<$R, LogRecord, $Out> {
  _LogRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LogRecord> $mapper =
      LogRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  LogPayloadCopyWith<$R, LogPayload, LogPayload> get payload =>
      $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, LogPayload? payload}) => $apply(
    FieldCopyWithData({
      if (envelope != null) #envelope: envelope,
      if (payload != null) #payload: payload,
    }),
  );
  @override
  LogRecord $make(CopyWithData data) => LogRecord(
    envelope: data.get(#envelope, or: $value.envelope),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  LogRecordCopyWith<$R2, LogRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LogRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ProductEventRecordMapper extends ClassMapperBase<ProductEventRecord> {
  ProductEventRecordMapper._();

  static ProductEventRecordMapper? _instance;
  static ProductEventRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProductEventRecordMapper._());
      RecordEnvelopeMapper.ensureInitialized();
      ProductEventPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProductEventRecord';

  static RecordEnvelope _$envelope(ProductEventRecord v) => v.envelope;
  static const Field<ProductEventRecord, RecordEnvelope> _f$envelope = Field(
    'envelope',
    _$envelope,
  );
  static ProductEventPayload _$payload(ProductEventRecord v) => v.payload;
  static const Field<ProductEventRecord, ProductEventPayload> _f$payload =
      Field('payload', _$payload);

  @override
  final MappableFields<ProductEventRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static ProductEventRecord _instantiate(DecodingData data) {
    return ProductEventRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProductEventRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProductEventRecord>(map);
  }

  static ProductEventRecord fromJson(String json) {
    return ensureInitialized().decodeJson<ProductEventRecord>(json);
  }
}

mixin ProductEventRecordMappable {
  String toJson() {
    return ProductEventRecordMapper.ensureInitialized()
        .encodeJson<ProductEventRecord>(this as ProductEventRecord);
  }

  Map<String, dynamic> toMap() {
    return ProductEventRecordMapper.ensureInitialized()
        .encodeMap<ProductEventRecord>(this as ProductEventRecord);
  }

  ProductEventRecordCopyWith<
    ProductEventRecord,
    ProductEventRecord,
    ProductEventRecord
  >
  get copyWith =>
      _ProductEventRecordCopyWithImpl<ProductEventRecord, ProductEventRecord>(
        this as ProductEventRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProductEventRecordMapper.ensureInitialized().stringifyValue(
      this as ProductEventRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProductEventRecordMapper.ensureInitialized().equalsValue(
      this as ProductEventRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return ProductEventRecordMapper.ensureInitialized().hashValue(
      this as ProductEventRecord,
    );
  }
}

extension ProductEventRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProductEventRecord, $Out> {
  ProductEventRecordCopyWith<$R, ProductEventRecord, $Out>
  get $asProductEventRecord => $base.as(
    (v, t, t2) => _ProductEventRecordCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ProductEventRecordCopyWith<
  $R,
  $In extends ProductEventRecord,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  ProductEventPayloadCopyWith<$R, ProductEventPayload, ProductEventPayload>
  get payload;
  $R call({RecordEnvelope? envelope, ProductEventPayload? payload});
  ProductEventRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ProductEventRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProductEventRecord, $Out>
    implements ProductEventRecordCopyWith<$R, ProductEventRecord, $Out> {
  _ProductEventRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProductEventRecord> $mapper =
      ProductEventRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  ProductEventPayloadCopyWith<$R, ProductEventPayload, ProductEventPayload>
  get payload => $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, ProductEventPayload? payload}) => $apply(
    FieldCopyWithData({
      if (envelope != null) #envelope: envelope,
      if (payload != null) #payload: payload,
    }),
  );
  @override
  ProductEventRecord $make(CopyWithData data) => ProductEventRecord(
    envelope: data.get(#envelope, or: $value.envelope),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  ProductEventRecordCopyWith<$R2, ProductEventRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ProductEventRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class IdentityLinkRecordMapper extends ClassMapperBase<IdentityLinkRecord> {
  IdentityLinkRecordMapper._();

  static IdentityLinkRecordMapper? _instance;
  static IdentityLinkRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IdentityLinkRecordMapper._());
      RecordEnvelopeMapper.ensureInitialized();
      IdentityLinkPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IdentityLinkRecord';

  static RecordEnvelope _$envelope(IdentityLinkRecord v) => v.envelope;
  static const Field<IdentityLinkRecord, RecordEnvelope> _f$envelope = Field(
    'envelope',
    _$envelope,
  );
  static IdentityLinkPayload _$payload(IdentityLinkRecord v) => v.payload;
  static const Field<IdentityLinkRecord, IdentityLinkPayload> _f$payload =
      Field('payload', _$payload);

  @override
  final MappableFields<IdentityLinkRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static IdentityLinkRecord _instantiate(DecodingData data) {
    return IdentityLinkRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IdentityLinkRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IdentityLinkRecord>(map);
  }

  static IdentityLinkRecord fromJson(String json) {
    return ensureInitialized().decodeJson<IdentityLinkRecord>(json);
  }
}

mixin IdentityLinkRecordMappable {
  String toJson() {
    return IdentityLinkRecordMapper.ensureInitialized()
        .encodeJson<IdentityLinkRecord>(this as IdentityLinkRecord);
  }

  Map<String, dynamic> toMap() {
    return IdentityLinkRecordMapper.ensureInitialized()
        .encodeMap<IdentityLinkRecord>(this as IdentityLinkRecord);
  }

  IdentityLinkRecordCopyWith<
    IdentityLinkRecord,
    IdentityLinkRecord,
    IdentityLinkRecord
  >
  get copyWith =>
      _IdentityLinkRecordCopyWithImpl<IdentityLinkRecord, IdentityLinkRecord>(
        this as IdentityLinkRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IdentityLinkRecordMapper.ensureInitialized().stringifyValue(
      this as IdentityLinkRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return IdentityLinkRecordMapper.ensureInitialized().equalsValue(
      this as IdentityLinkRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return IdentityLinkRecordMapper.ensureInitialized().hashValue(
      this as IdentityLinkRecord,
    );
  }
}

extension IdentityLinkRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IdentityLinkRecord, $Out> {
  IdentityLinkRecordCopyWith<$R, IdentityLinkRecord, $Out>
  get $asIdentityLinkRecord => $base.as(
    (v, t, t2) => _IdentityLinkRecordCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class IdentityLinkRecordCopyWith<
  $R,
  $In extends IdentityLinkRecord,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  IdentityLinkPayloadCopyWith<$R, IdentityLinkPayload, IdentityLinkPayload>
  get payload;
  $R call({RecordEnvelope? envelope, IdentityLinkPayload? payload});
  IdentityLinkRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _IdentityLinkRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IdentityLinkRecord, $Out>
    implements IdentityLinkRecordCopyWith<$R, IdentityLinkRecord, $Out> {
  _IdentityLinkRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IdentityLinkRecord> $mapper =
      IdentityLinkRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  IdentityLinkPayloadCopyWith<$R, IdentityLinkPayload, IdentityLinkPayload>
  get payload => $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, IdentityLinkPayload? payload}) => $apply(
    FieldCopyWithData({
      if (envelope != null) #envelope: envelope,
      if (payload != null) #payload: payload,
    }),
  );
  @override
  IdentityLinkRecord $make(CopyWithData data) => IdentityLinkRecord(
    envelope: data.get(#envelope, or: $value.envelope),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  IdentityLinkRecordCopyWith<$R2, IdentityLinkRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IdentityLinkRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class UserPropertiesSetRecordMapper
    extends ClassMapperBase<UserPropertiesSetRecord> {
  UserPropertiesSetRecordMapper._();

  static UserPropertiesSetRecordMapper? _instance;
  static UserPropertiesSetRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = UserPropertiesSetRecordMapper._(),
      );
      RecordEnvelopeMapper.ensureInitialized();
      UserPropertiesSetPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'UserPropertiesSetRecord';

  static RecordEnvelope _$envelope(UserPropertiesSetRecord v) => v.envelope;
  static const Field<UserPropertiesSetRecord, RecordEnvelope> _f$envelope =
      Field('envelope', _$envelope);
  static UserPropertiesSetPayload _$payload(UserPropertiesSetRecord v) =>
      v.payload;
  static const Field<UserPropertiesSetRecord, UserPropertiesSetPayload>
  _f$payload = Field('payload', _$payload);

  @override
  final MappableFields<UserPropertiesSetRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static UserPropertiesSetRecord _instantiate(DecodingData data) {
    return UserPropertiesSetRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static UserPropertiesSetRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UserPropertiesSetRecord>(map);
  }

  static UserPropertiesSetRecord fromJson(String json) {
    return ensureInitialized().decodeJson<UserPropertiesSetRecord>(json);
  }
}

mixin UserPropertiesSetRecordMappable {
  String toJson() {
    return UserPropertiesSetRecordMapper.ensureInitialized()
        .encodeJson<UserPropertiesSetRecord>(this as UserPropertiesSetRecord);
  }

  Map<String, dynamic> toMap() {
    return UserPropertiesSetRecordMapper.ensureInitialized()
        .encodeMap<UserPropertiesSetRecord>(this as UserPropertiesSetRecord);
  }

  UserPropertiesSetRecordCopyWith<
    UserPropertiesSetRecord,
    UserPropertiesSetRecord,
    UserPropertiesSetRecord
  >
  get copyWith =>
      _UserPropertiesSetRecordCopyWithImpl<
        UserPropertiesSetRecord,
        UserPropertiesSetRecord
      >(this as UserPropertiesSetRecord, $identity, $identity);
  @override
  String toString() {
    return UserPropertiesSetRecordMapper.ensureInitialized().stringifyValue(
      this as UserPropertiesSetRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return UserPropertiesSetRecordMapper.ensureInitialized().equalsValue(
      this as UserPropertiesSetRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return UserPropertiesSetRecordMapper.ensureInitialized().hashValue(
      this as UserPropertiesSetRecord,
    );
  }
}

extension UserPropertiesSetRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, UserPropertiesSetRecord, $Out> {
  UserPropertiesSetRecordCopyWith<$R, UserPropertiesSetRecord, $Out>
  get $asUserPropertiesSetRecord => $base.as(
    (v, t, t2) => _UserPropertiesSetRecordCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class UserPropertiesSetRecordCopyWith<
  $R,
  $In extends UserPropertiesSetRecord,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  UserPropertiesSetPayloadCopyWith<
    $R,
    UserPropertiesSetPayload,
    UserPropertiesSetPayload
  >
  get payload;
  $R call({RecordEnvelope? envelope, UserPropertiesSetPayload? payload});
  UserPropertiesSetRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _UserPropertiesSetRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, UserPropertiesSetRecord, $Out>
    implements
        UserPropertiesSetRecordCopyWith<$R, UserPropertiesSetRecord, $Out> {
  _UserPropertiesSetRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<UserPropertiesSetRecord> $mapper =
      UserPropertiesSetRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  UserPropertiesSetPayloadCopyWith<
    $R,
    UserPropertiesSetPayload,
    UserPropertiesSetPayload
  >
  get payload => $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, UserPropertiesSetPayload? payload}) =>
      $apply(
        FieldCopyWithData({
          if (envelope != null) #envelope: envelope,
          if (payload != null) #payload: payload,
        }),
      );
  @override
  UserPropertiesSetRecord $make(CopyWithData data) => UserPropertiesSetRecord(
    envelope: data.get(#envelope, or: $value.envelope),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  UserPropertiesSetRecordCopyWith<$R2, UserPropertiesSetRecord, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _UserPropertiesSetRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class UserPropertiesUnsetRecordMapper
    extends ClassMapperBase<UserPropertiesUnsetRecord> {
  UserPropertiesUnsetRecordMapper._();

  static UserPropertiesUnsetRecordMapper? _instance;
  static UserPropertiesUnsetRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = UserPropertiesUnsetRecordMapper._(),
      );
      RecordEnvelopeMapper.ensureInitialized();
      UserPropertiesUnsetPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'UserPropertiesUnsetRecord';

  static RecordEnvelope _$envelope(UserPropertiesUnsetRecord v) => v.envelope;
  static const Field<UserPropertiesUnsetRecord, RecordEnvelope> _f$envelope =
      Field('envelope', _$envelope);
  static UserPropertiesUnsetPayload _$payload(UserPropertiesUnsetRecord v) =>
      v.payload;
  static const Field<UserPropertiesUnsetRecord, UserPropertiesUnsetPayload>
  _f$payload = Field('payload', _$payload);

  @override
  final MappableFields<UserPropertiesUnsetRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static UserPropertiesUnsetRecord _instantiate(DecodingData data) {
    return UserPropertiesUnsetRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static UserPropertiesUnsetRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UserPropertiesUnsetRecord>(map);
  }

  static UserPropertiesUnsetRecord fromJson(String json) {
    return ensureInitialized().decodeJson<UserPropertiesUnsetRecord>(json);
  }
}

mixin UserPropertiesUnsetRecordMappable {
  String toJson() {
    return UserPropertiesUnsetRecordMapper.ensureInitialized()
        .encodeJson<UserPropertiesUnsetRecord>(
          this as UserPropertiesUnsetRecord,
        );
  }

  Map<String, dynamic> toMap() {
    return UserPropertiesUnsetRecordMapper.ensureInitialized()
        .encodeMap<UserPropertiesUnsetRecord>(
          this as UserPropertiesUnsetRecord,
        );
  }

  UserPropertiesUnsetRecordCopyWith<
    UserPropertiesUnsetRecord,
    UserPropertiesUnsetRecord,
    UserPropertiesUnsetRecord
  >
  get copyWith =>
      _UserPropertiesUnsetRecordCopyWithImpl<
        UserPropertiesUnsetRecord,
        UserPropertiesUnsetRecord
      >(this as UserPropertiesUnsetRecord, $identity, $identity);
  @override
  String toString() {
    return UserPropertiesUnsetRecordMapper.ensureInitialized().stringifyValue(
      this as UserPropertiesUnsetRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return UserPropertiesUnsetRecordMapper.ensureInitialized().equalsValue(
      this as UserPropertiesUnsetRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return UserPropertiesUnsetRecordMapper.ensureInitialized().hashValue(
      this as UserPropertiesUnsetRecord,
    );
  }
}

extension UserPropertiesUnsetRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, UserPropertiesUnsetRecord, $Out> {
  UserPropertiesUnsetRecordCopyWith<$R, UserPropertiesUnsetRecord, $Out>
  get $asUserPropertiesUnsetRecord => $base.as(
    (v, t, t2) => _UserPropertiesUnsetRecordCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class UserPropertiesUnsetRecordCopyWith<
  $R,
  $In extends UserPropertiesUnsetRecord,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  UserPropertiesUnsetPayloadCopyWith<
    $R,
    UserPropertiesUnsetPayload,
    UserPropertiesUnsetPayload
  >
  get payload;
  $R call({RecordEnvelope? envelope, UserPropertiesUnsetPayload? payload});
  UserPropertiesUnsetRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _UserPropertiesUnsetRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, UserPropertiesUnsetRecord, $Out>
    implements
        UserPropertiesUnsetRecordCopyWith<$R, UserPropertiesUnsetRecord, $Out> {
  _UserPropertiesUnsetRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<UserPropertiesUnsetRecord> $mapper =
      UserPropertiesUnsetRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  UserPropertiesUnsetPayloadCopyWith<
    $R,
    UserPropertiesUnsetPayload,
    UserPropertiesUnsetPayload
  >
  get payload => $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, UserPropertiesUnsetPayload? payload}) =>
      $apply(
        FieldCopyWithData({
          if (envelope != null) #envelope: envelope,
          if (payload != null) #payload: payload,
        }),
      );
  @override
  UserPropertiesUnsetRecord $make(CopyWithData data) =>
      UserPropertiesUnsetRecord(
        envelope: data.get(#envelope, or: $value.envelope),
        payload: data.get(#payload, or: $value.payload),
      );

  @override
  UserPropertiesUnsetRecordCopyWith<$R2, UserPropertiesUnsetRecord, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _UserPropertiesUnsetRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SpanRecordMapper extends ClassMapperBase<SpanRecord> {
  SpanRecordMapper._();

  static SpanRecordMapper? _instance;
  static SpanRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SpanRecordMapper._());
      RecordEnvelopeMapper.ensureInitialized();
      SpanPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SpanRecord';

  static RecordEnvelope _$envelope(SpanRecord v) => v.envelope;
  static const Field<SpanRecord, RecordEnvelope> _f$envelope = Field(
    'envelope',
    _$envelope,
  );
  static SpanPayload _$payload(SpanRecord v) => v.payload;
  static const Field<SpanRecord, SpanPayload> _f$payload = Field(
    'payload',
    _$payload,
  );

  @override
  final MappableFields<SpanRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static SpanRecord _instantiate(DecodingData data) {
    return SpanRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SpanRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SpanRecord>(map);
  }

  static SpanRecord fromJson(String json) {
    return ensureInitialized().decodeJson<SpanRecord>(json);
  }
}

mixin SpanRecordMappable {
  String toJson() {
    return SpanRecordMapper.ensureInitialized().encodeJson<SpanRecord>(
      this as SpanRecord,
    );
  }

  Map<String, dynamic> toMap() {
    return SpanRecordMapper.ensureInitialized().encodeMap<SpanRecord>(
      this as SpanRecord,
    );
  }

  SpanRecordCopyWith<SpanRecord, SpanRecord, SpanRecord> get copyWith =>
      _SpanRecordCopyWithImpl<SpanRecord, SpanRecord>(
        this as SpanRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SpanRecordMapper.ensureInitialized().stringifyValue(
      this as SpanRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return SpanRecordMapper.ensureInitialized().equalsValue(
      this as SpanRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return SpanRecordMapper.ensureInitialized().hashValue(this as SpanRecord);
  }
}

extension SpanRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SpanRecord, $Out> {
  SpanRecordCopyWith<$R, SpanRecord, $Out> get $asSpanRecord =>
      $base.as((v, t, t2) => _SpanRecordCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SpanRecordCopyWith<$R, $In extends SpanRecord, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  SpanPayloadCopyWith<$R, SpanPayload, SpanPayload> get payload;
  $R call({RecordEnvelope? envelope, SpanPayload? payload});
  SpanRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SpanRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SpanRecord, $Out>
    implements SpanRecordCopyWith<$R, SpanRecord, $Out> {
  _SpanRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SpanRecord> $mapper =
      SpanRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  SpanPayloadCopyWith<$R, SpanPayload, SpanPayload> get payload =>
      $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, SpanPayload? payload}) => $apply(
    FieldCopyWithData({
      if (envelope != null) #envelope: envelope,
      if (payload != null) #payload: payload,
    }),
  );
  @override
  SpanRecord $make(CopyWithData data) => SpanRecord(
    envelope: data.get(#envelope, or: $value.envelope),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  SpanRecordCopyWith<$R2, SpanRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SpanRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ErrorRecordMapper extends ClassMapperBase<ErrorRecord> {
  ErrorRecordMapper._();

  static ErrorRecordMapper? _instance;
  static ErrorRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ErrorRecordMapper._());
      RecordEnvelopeMapper.ensureInitialized();
      ErrorPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ErrorRecord';

  static RecordEnvelope _$envelope(ErrorRecord v) => v.envelope;
  static const Field<ErrorRecord, RecordEnvelope> _f$envelope = Field(
    'envelope',
    _$envelope,
  );
  static ErrorPayload _$payload(ErrorRecord v) => v.payload;
  static const Field<ErrorRecord, ErrorPayload> _f$payload = Field(
    'payload',
    _$payload,
  );

  @override
  final MappableFields<ErrorRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static ErrorRecord _instantiate(DecodingData data) {
    return ErrorRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ErrorRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ErrorRecord>(map);
  }

  static ErrorRecord fromJson(String json) {
    return ensureInitialized().decodeJson<ErrorRecord>(json);
  }
}

mixin ErrorRecordMappable {
  String toJson() {
    return ErrorRecordMapper.ensureInitialized().encodeJson<ErrorRecord>(
      this as ErrorRecord,
    );
  }

  Map<String, dynamic> toMap() {
    return ErrorRecordMapper.ensureInitialized().encodeMap<ErrorRecord>(
      this as ErrorRecord,
    );
  }

  ErrorRecordCopyWith<ErrorRecord, ErrorRecord, ErrorRecord> get copyWith =>
      _ErrorRecordCopyWithImpl<ErrorRecord, ErrorRecord>(
        this as ErrorRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ErrorRecordMapper.ensureInitialized().stringifyValue(
      this as ErrorRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return ErrorRecordMapper.ensureInitialized().equalsValue(
      this as ErrorRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return ErrorRecordMapper.ensureInitialized().hashValue(this as ErrorRecord);
  }
}

extension ErrorRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ErrorRecord, $Out> {
  ErrorRecordCopyWith<$R, ErrorRecord, $Out> get $asErrorRecord =>
      $base.as((v, t, t2) => _ErrorRecordCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ErrorRecordCopyWith<$R, $In extends ErrorRecord, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  ErrorPayloadCopyWith<$R, ErrorPayload, ErrorPayload> get payload;
  $R call({RecordEnvelope? envelope, ErrorPayload? payload});
  ErrorRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ErrorRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ErrorRecord, $Out>
    implements ErrorRecordCopyWith<$R, ErrorRecord, $Out> {
  _ErrorRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ErrorRecord> $mapper =
      ErrorRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  ErrorPayloadCopyWith<$R, ErrorPayload, ErrorPayload> get payload =>
      $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, ErrorPayload? payload}) => $apply(
    FieldCopyWithData({
      if (envelope != null) #envelope: envelope,
      if (payload != null) #payload: payload,
    }),
  );
  @override
  ErrorRecord $make(CopyWithData data) => ErrorRecord(
    envelope: data.get(#envelope, or: $value.envelope),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  ErrorRecordCopyWith<$R2, ErrorRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ErrorRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class MetricRecordMapper extends ClassMapperBase<MetricRecord> {
  MetricRecordMapper._();

  static MetricRecordMapper? _instance;
  static MetricRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MetricRecordMapper._());
      RecordEnvelopeMapper.ensureInitialized();
      MetricPayloadMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'MetricRecord';

  static RecordEnvelope _$envelope(MetricRecord v) => v.envelope;
  static const Field<MetricRecord, RecordEnvelope> _f$envelope = Field(
    'envelope',
    _$envelope,
  );
  static MetricPayload _$payload(MetricRecord v) => v.payload;
  static const Field<MetricRecord, MetricPayload> _f$payload = Field(
    'payload',
    _$payload,
  );

  @override
  final MappableFields<MetricRecord> fields = const {
    #envelope: _f$envelope,
    #payload: _f$payload,
  };

  static MetricRecord _instantiate(DecodingData data) {
    return MetricRecord(
      envelope: data.dec(_f$envelope),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MetricRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MetricRecord>(map);
  }

  static MetricRecord fromJson(String json) {
    return ensureInitialized().decodeJson<MetricRecord>(json);
  }
}

mixin MetricRecordMappable {
  String toJson() {
    return MetricRecordMapper.ensureInitialized().encodeJson<MetricRecord>(
      this as MetricRecord,
    );
  }

  Map<String, dynamic> toMap() {
    return MetricRecordMapper.ensureInitialized().encodeMap<MetricRecord>(
      this as MetricRecord,
    );
  }

  MetricRecordCopyWith<MetricRecord, MetricRecord, MetricRecord> get copyWith =>
      _MetricRecordCopyWithImpl<MetricRecord, MetricRecord>(
        this as MetricRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return MetricRecordMapper.ensureInitialized().stringifyValue(
      this as MetricRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return MetricRecordMapper.ensureInitialized().equalsValue(
      this as MetricRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return MetricRecordMapper.ensureInitialized().hashValue(
      this as MetricRecord,
    );
  }
}

extension MetricRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MetricRecord, $Out> {
  MetricRecordCopyWith<$R, MetricRecord, $Out> get $asMetricRecord =>
      $base.as((v, t, t2) => _MetricRecordCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MetricRecordCopyWith<$R, $In extends MetricRecord, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope;
  MetricPayloadCopyWith<$R, MetricPayload, MetricPayload> get payload;
  $R call({RecordEnvelope? envelope, MetricPayload? payload});
  MetricRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MetricRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MetricRecord, $Out>
    implements MetricRecordCopyWith<$R, MetricRecord, $Out> {
  _MetricRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MetricRecord> $mapper =
      MetricRecordMapper.ensureInitialized();
  @override
  RecordEnvelopeCopyWith<$R, RecordEnvelope, RecordEnvelope> get envelope =>
      $value.envelope.copyWith.$chain((v) => call(envelope: v));
  @override
  MetricPayloadCopyWith<$R, MetricPayload, MetricPayload> get payload =>
      $value.payload.copyWith.$chain((v) => call(payload: v));
  @override
  $R call({RecordEnvelope? envelope, MetricPayload? payload}) => $apply(
    FieldCopyWithData({
      if (envelope != null) #envelope: envelope,
      if (payload != null) #payload: payload,
    }),
  );
  @override
  MetricRecord $make(CopyWithData data) => MetricRecord(
    envelope: data.get(#envelope, or: $value.envelope),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  MetricRecordCopyWith<$R2, MetricRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MetricRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

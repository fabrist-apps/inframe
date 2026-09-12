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


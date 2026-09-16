// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'observations.dart';

class ProviderObservationKindMapper
    extends EnumMapper<ProviderObservationKind> {
  ProviderObservationKindMapper._();

  static ProviderObservationKindMapper? _instance;
  static ProviderObservationKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ProviderObservationKindMapper._(),
      );
    }
    return _instance!;
  }

  static ProviderObservationKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProviderObservationKind decode(dynamic value) {
    switch (value) {
      case r'started':
        return ProviderObservationKind.started;
      case r'response':
        return ProviderObservationKind.response;
      case r'usage':
        return ProviderObservationKind.usage;
      case r'verdict':
        return ProviderObservationKind.verdict;
      case r'finished':
        return ProviderObservationKind.finished;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ProviderObservationKind self) {
    switch (self) {
      case ProviderObservationKind.started:
        return r'started';
      case ProviderObservationKind.response:
        return r'response';
      case ProviderObservationKind.usage:
        return r'usage';
      case ProviderObservationKind.verdict:
        return r'verdict';
      case ProviderObservationKind.finished:
        return r'finished';
    }
  }
}

extension ProviderObservationKindMapperExtension on ProviderObservationKind {
  String toValue() {
    ProviderObservationKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProviderObservationKind>(this)
        as String;
  }
}

class ProviderOutcomeMapper extends EnumMapper<ProviderOutcome> {
  ProviderOutcomeMapper._();

  static ProviderOutcomeMapper? _instance;
  static ProviderOutcomeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProviderOutcomeMapper._());
    }
    return _instance!;
  }

  static ProviderOutcome fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProviderOutcome decode(dynamic value) {
    switch (value) {
      case r'succeeded':
        return ProviderOutcome.succeeded;
      case r'failed':
        return ProviderOutcome.failed;
      case r'interrupted':
        return ProviderOutcome.interrupted;
      case r'defect':
        return ProviderOutcome.defect;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ProviderOutcome self) {
    switch (self) {
      case ProviderOutcome.succeeded:
        return r'succeeded';
      case ProviderOutcome.failed:
        return r'failed';
      case ProviderOutcome.interrupted:
        return r'interrupted';
      case ProviderOutcome.defect:
        return r'defect';
    }
  }
}

extension ProviderOutcomeMapperExtension on ProviderOutcome {
  String toValue() {
    ProviderOutcomeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProviderOutcome>(this) as String;
  }
}

class InvocationContextMapper extends ClassMapperBase<InvocationContext> {
  InvocationContextMapper._();

  static InvocationContextMapper? _instance;
  static InvocationContextMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = InvocationContextMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'InvocationContext';

  static String? _$operationId(InvocationContext v) => v.operationId;
  static const Field<InvocationContext, String> _f$operationId = Field(
    'operationId',
    _$operationId,
    opt: true,
  );
  static String? _$attemptId(InvocationContext v) => v.attemptId;
  static const Field<InvocationContext, String> _f$attemptId = Field(
    'attemptId',
    _$attemptId,
    opt: true,
  );

  @override
  final MappableFields<InvocationContext> fields = const {
    #operationId: _f$operationId,
    #attemptId: _f$attemptId,
  };

  static InvocationContext _instantiate(DecodingData data) {
    return InvocationContext(
      operationId: data.dec(_f$operationId),
      attemptId: data.dec(_f$attemptId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static InvocationContext fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<InvocationContext>(map);
  }

  static InvocationContext fromJson(String json) {
    return ensureInitialized().decodeJson<InvocationContext>(json);
  }
}

mixin InvocationContextMappable {
  String toJson() {
    return InvocationContextMapper.ensureInitialized()
        .encodeJson<InvocationContext>(this as InvocationContext);
  }

  Map<String, dynamic> toMap() {
    return InvocationContextMapper.ensureInitialized()
        .encodeMap<InvocationContext>(this as InvocationContext);
  }
}

class ProviderObservationMapper extends ClassMapperBase<ProviderObservation> {
  ProviderObservationMapper._();

  static ProviderObservationMapper? _instance;
  static ProviderObservationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProviderObservationMapper._());
      ProviderObservationKindMapper.ensureInitialized();
      UsageMapper.ensureInitialized();
      FinishReasonMapper.ensureInitialized();
      ProviderOutcomeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProviderObservation';

  static ProviderObservationKind _$kind(ProviderObservation v) => v.kind;
  static const Field<ProviderObservation, ProviderObservationKind> _f$kind =
      Field('kind', _$kind);
  static String _$attemptId(ProviderObservation v) => v.attemptId;
  static const Field<ProviderObservation, String> _f$attemptId = Field(
    'attemptId',
    _$attemptId,
  );
  static String? _$operationId(ProviderObservation v) => v.operationId;
  static const Field<ProviderObservation, String> _f$operationId = Field(
    'operationId',
    _$operationId,
    opt: true,
  );
  static String? _$providerId(ProviderObservation v) => v.providerId;
  static const Field<ProviderObservation, String> _f$providerId = Field(
    'providerId',
    _$providerId,
    opt: true,
  );
  static String? _$api(ProviderObservation v) => v.api;
  static const Field<ProviderObservation, String> _f$api = Field(
    'api',
    _$api,
    opt: true,
  );
  static String? _$modelId(ProviderObservation v) => v.modelId;
  static const Field<ProviderObservation, String> _f$modelId = Field(
    'modelId',
    _$modelId,
    opt: true,
  );
  static String? _$requestId(ProviderObservation v) => v.requestId;
  static const Field<ProviderObservation, String> _f$requestId = Field(
    'requestId',
    _$requestId,
    opt: true,
  );
  static int? _$statusCode(ProviderObservation v) => v.statusCode;
  static const Field<ProviderObservation, int> _f$statusCode = Field(
    'statusCode',
    _$statusCode,
    opt: true,
  );
  static Usage? _$usage(ProviderObservation v) => v.usage;
  static const Field<ProviderObservation, Usage> _f$usage = Field(
    'usage',
    _$usage,
    opt: true,
  );
  static FinishReason? _$verdict(ProviderObservation v) => v.verdict;
  static const Field<ProviderObservation, FinishReason> _f$verdict = Field(
    'verdict',
    _$verdict,
    opt: true,
  );
  static ProviderOutcome? _$outcome(ProviderObservation v) => v.outcome;
  static const Field<ProviderObservation, ProviderOutcome> _f$outcome = Field(
    'outcome',
    _$outcome,
    opt: true,
  );

  @override
  final MappableFields<ProviderObservation> fields = const {
    #kind: _f$kind,
    #attemptId: _f$attemptId,
    #operationId: _f$operationId,
    #providerId: _f$providerId,
    #api: _f$api,
    #modelId: _f$modelId,
    #requestId: _f$requestId,
    #statusCode: _f$statusCode,
    #usage: _f$usage,
    #verdict: _f$verdict,
    #outcome: _f$outcome,
  };

  static ProviderObservation _instantiate(DecodingData data) {
    return ProviderObservation(
      kind: data.dec(_f$kind),
      attemptId: data.dec(_f$attemptId),
      operationId: data.dec(_f$operationId),
      providerId: data.dec(_f$providerId),
      api: data.dec(_f$api),
      modelId: data.dec(_f$modelId),
      requestId: data.dec(_f$requestId),
      statusCode: data.dec(_f$statusCode),
      usage: data.dec(_f$usage),
      verdict: data.dec(_f$verdict),
      outcome: data.dec(_f$outcome),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProviderObservation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProviderObservation>(map);
  }

  static ProviderObservation fromJson(String json) {
    return ensureInitialized().decodeJson<ProviderObservation>(json);
  }
}

mixin ProviderObservationMappable {
  String toJson() {
    return ProviderObservationMapper.ensureInitialized()
        .encodeJson<ProviderObservation>(this as ProviderObservation);
  }

  Map<String, dynamic> toMap() {
    return ProviderObservationMapper.ensureInitialized()
        .encodeMap<ProviderObservation>(this as ProviderObservation);
  }
}


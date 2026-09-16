// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'errors.dart';

class DeliveryStateMapper extends EnumMapper<DeliveryState> {
  DeliveryStateMapper._();

  static DeliveryStateMapper? _instance;
  static DeliveryStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DeliveryStateMapper._());
    }
    return _instance!;
  }

  static DeliveryState fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  DeliveryState decode(dynamic value) {
    switch (value) {
      case r'notSent':
        return DeliveryState.notSent;
      case r'mayHaveReachedProvider':
        return DeliveryState.mayHaveReachedProvider;
      case r'responseStarted':
        return DeliveryState.responseStarted;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(DeliveryState self) {
    switch (self) {
      case DeliveryState.notSent:
        return r'notSent';
      case DeliveryState.mayHaveReachedProvider:
        return r'mayHaveReachedProvider';
      case DeliveryState.responseStarted:
        return r'responseStarted';
    }
  }
}

extension DeliveryStateMapperExtension on DeliveryState {
  String toValue() {
    DeliveryStateMapper.ensureInitialized();
    return MapperContainer.globals.toValue<DeliveryState>(this) as String;
  }
}

class AiErrorMapper extends ClassMapperBase<AiError> {
  AiErrorMapper._();

  static AiErrorMapper? _instance;
  static AiErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiErrorMapper._());
      InvalidRequestErrorMapper.ensureInitialized();
      UnsupportedFeatureErrorMapper.ensureInitialized();
      ProviderErrorMapper.ensureInitialized();
      TransportErrorMapper.ensureInitialized();
      ProtocolErrorMapper.ensureInitialized();
      ResponseLimitErrorMapper.ensureInitialized();
      ClientClosedErrorMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AiError';

  static String _$message(AiError v) => v.message;
  static const Field<AiError, String> _f$message = Field('message', _$message);

  @override
  final MappableFields<AiError> fields = const {#message: _f$message};

  static AiError _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'AiError',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiError>(map);
  }

  static AiError fromJson(String json) {
    return ensureInitialized().decodeJson<AiError>(json);
  }
}

mixin AiErrorMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class InvalidRequestErrorMapper
    extends SubClassMapperBase<InvalidRequestError> {
  InvalidRequestErrorMapper._();

  static InvalidRequestErrorMapper? _instance;
  static InvalidRequestErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = InvalidRequestErrorMapper._());
      AiErrorMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'InvalidRequestError';

  static String _$message(InvalidRequestError v) => v.message;
  static const Field<InvalidRequestError, String> _f$message = Field(
    'message',
    _$message,
  );

  @override
  final MappableFields<InvalidRequestError> fields = const {
    #message: _f$message,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'InvalidRequestError';
  @override
  late final ClassMapperBase superMapper = AiErrorMapper.ensureInitialized();

  static InvalidRequestError _instantiate(DecodingData data) {
    return InvalidRequestError(data.dec(_f$message));
  }

  @override
  final Function instantiate = _instantiate;

  static InvalidRequestError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<InvalidRequestError>(map);
  }

  static InvalidRequestError fromJson(String json) {
    return ensureInitialized().decodeJson<InvalidRequestError>(json);
  }
}

mixin InvalidRequestErrorMappable {
  String toJson() {
    return InvalidRequestErrorMapper.ensureInitialized()
        .encodeJson<InvalidRequestError>(this as InvalidRequestError);
  }

  Map<String, dynamic> toMap() {
    return InvalidRequestErrorMapper.ensureInitialized()
        .encodeMap<InvalidRequestError>(this as InvalidRequestError);
  }
}

class UnsupportedFeatureErrorMapper
    extends SubClassMapperBase<UnsupportedFeatureError> {
  UnsupportedFeatureErrorMapper._();

  static UnsupportedFeatureErrorMapper? _instance;
  static UnsupportedFeatureErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = UnsupportedFeatureErrorMapper._(),
      );
      AiErrorMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'UnsupportedFeatureError';

  static String _$message(UnsupportedFeatureError v) => v.message;
  static const Field<UnsupportedFeatureError, String> _f$message = Field(
    'message',
    _$message,
  );
  static String? _$feature(UnsupportedFeatureError v) => v.feature;
  static const Field<UnsupportedFeatureError, String> _f$feature = Field(
    'feature',
    _$feature,
    opt: true,
  );

  @override
  final MappableFields<UnsupportedFeatureError> fields = const {
    #message: _f$message,
    #feature: _f$feature,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'UnsupportedFeatureError';
  @override
  late final ClassMapperBase superMapper = AiErrorMapper.ensureInitialized();

  static UnsupportedFeatureError _instantiate(DecodingData data) {
    return UnsupportedFeatureError(
      data.dec(_f$message),
      feature: data.dec(_f$feature),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static UnsupportedFeatureError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UnsupportedFeatureError>(map);
  }

  static UnsupportedFeatureError fromJson(String json) {
    return ensureInitialized().decodeJson<UnsupportedFeatureError>(json);
  }
}

mixin UnsupportedFeatureErrorMappable {
  String toJson() {
    return UnsupportedFeatureErrorMapper.ensureInitialized()
        .encodeJson<UnsupportedFeatureError>(this as UnsupportedFeatureError);
  }

  Map<String, dynamic> toMap() {
    return UnsupportedFeatureErrorMapper.ensureInitialized()
        .encodeMap<UnsupportedFeatureError>(this as UnsupportedFeatureError);
  }
}

class ProviderErrorMapper extends SubClassMapperBase<ProviderError> {
  ProviderErrorMapper._();

  static ProviderErrorMapper? _instance;
  static ProviderErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProviderErrorMapper._());
      AiErrorMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ProviderError';

  static String _$message(ProviderError v) => v.message;
  static const Field<ProviderError, String> _f$message = Field(
    'message',
    _$message,
  );
  static int? _$statusCode(ProviderError v) => v.statusCode;
  static const Field<ProviderError, int> _f$statusCode = Field(
    'statusCode',
    _$statusCode,
    opt: true,
  );
  static String? _$code(ProviderError v) => v.code;
  static const Field<ProviderError, String> _f$code = Field(
    'code',
    _$code,
    opt: true,
  );
  static Object? _$details(ProviderError v) => v.details;
  static const Field<ProviderError, Object> _f$details = Field(
    'details',
    _$details,
    opt: true,
    hook: JsonValueHook(),
  );
  static String? _$requestId(ProviderError v) => v.requestId;
  static const Field<ProviderError, String> _f$requestId = Field(
    'requestId',
    _$requestId,
    opt: true,
  );
  static String? _$retryAfter(ProviderError v) => v.retryAfter;
  static const Field<ProviderError, String> _f$retryAfter = Field(
    'retryAfter',
    _$retryAfter,
    opt: true,
  );
  static Object? _$partialOutput(ProviderError v) => v.partialOutput;
  static const Field<ProviderError, Object> _f$partialOutput = Field(
    'partialOutput',
    _$partialOutput,
    opt: true,
  );

  @override
  final MappableFields<ProviderError> fields = const {
    #message: _f$message,
    #statusCode: _f$statusCode,
    #code: _f$code,
    #details: _f$details,
    #requestId: _f$requestId,
    #retryAfter: _f$retryAfter,
    #partialOutput: _f$partialOutput,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'ProviderError';
  @override
  late final ClassMapperBase superMapper = AiErrorMapper.ensureInitialized();

  static ProviderError _instantiate(DecodingData data) {
    return ProviderError(
      data.dec(_f$message),
      statusCode: data.dec(_f$statusCode),
      code: data.dec(_f$code),
      details: data.dec(_f$details),
      requestId: data.dec(_f$requestId),
      retryAfter: data.dec(_f$retryAfter),
      partialOutput: data.dec(_f$partialOutput),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProviderError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProviderError>(map);
  }

  static ProviderError fromJson(String json) {
    return ensureInitialized().decodeJson<ProviderError>(json);
  }
}

mixin ProviderErrorMappable {
  String toJson() {
    return ProviderErrorMapper.ensureInitialized().encodeJson<ProviderError>(
      this as ProviderError,
    );
  }

  Map<String, dynamic> toMap() {
    return ProviderErrorMapper.ensureInitialized().encodeMap<ProviderError>(
      this as ProviderError,
    );
  }
}

class TransportErrorMapper extends SubClassMapperBase<TransportError> {
  TransportErrorMapper._();

  static TransportErrorMapper? _instance;
  static TransportErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TransportErrorMapper._());
      AiErrorMapper.ensureInitialized().addSubMapper(_instance!);
      DeliveryStateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TransportError';

  static String _$message(TransportError v) => v.message;
  static const Field<TransportError, String> _f$message = Field(
    'message',
    _$message,
  );
  static DeliveryState _$deliveryState(TransportError v) => v.deliveryState;
  static const Field<TransportError, DeliveryState> _f$deliveryState = Field(
    'deliveryState',
    _$deliveryState,
    opt: true,
    def: DeliveryState.notSent,
  );

  @override
  final MappableFields<TransportError> fields = const {
    #message: _f$message,
    #deliveryState: _f$deliveryState,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'TransportError';
  @override
  late final ClassMapperBase superMapper = AiErrorMapper.ensureInitialized();

  static TransportError _instantiate(DecodingData data) {
    return TransportError(
      data.dec(_f$message),
      deliveryState: data.dec(_f$deliveryState),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TransportError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TransportError>(map);
  }

  static TransportError fromJson(String json) {
    return ensureInitialized().decodeJson<TransportError>(json);
  }
}

mixin TransportErrorMappable {
  String toJson() {
    return TransportErrorMapper.ensureInitialized().encodeJson<TransportError>(
      this as TransportError,
    );
  }

  Map<String, dynamic> toMap() {
    return TransportErrorMapper.ensureInitialized().encodeMap<TransportError>(
      this as TransportError,
    );
  }
}

class ProtocolErrorMapper extends SubClassMapperBase<ProtocolError> {
  ProtocolErrorMapper._();

  static ProtocolErrorMapper? _instance;
  static ProtocolErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProtocolErrorMapper._());
      AiErrorMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ProtocolError';

  static String _$message(ProtocolError v) => v.message;
  static const Field<ProtocolError, String> _f$message = Field(
    'message',
    _$message,
  );
  static Object? _$partialOutput(ProtocolError v) => v.partialOutput;
  static const Field<ProtocolError, Object> _f$partialOutput = Field(
    'partialOutput',
    _$partialOutput,
    opt: true,
  );

  @override
  final MappableFields<ProtocolError> fields = const {
    #message: _f$message,
    #partialOutput: _f$partialOutput,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'ProtocolError';
  @override
  late final ClassMapperBase superMapper = AiErrorMapper.ensureInitialized();

  static ProtocolError _instantiate(DecodingData data) {
    return ProtocolError(
      data.dec(_f$message),
      partialOutput: data.dec(_f$partialOutput),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProtocolError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProtocolError>(map);
  }

  static ProtocolError fromJson(String json) {
    return ensureInitialized().decodeJson<ProtocolError>(json);
  }
}

mixin ProtocolErrorMappable {
  String toJson() {
    return ProtocolErrorMapper.ensureInitialized().encodeJson<ProtocolError>(
      this as ProtocolError,
    );
  }

  Map<String, dynamic> toMap() {
    return ProtocolErrorMapper.ensureInitialized().encodeMap<ProtocolError>(
      this as ProtocolError,
    );
  }
}

class ResponseLimitErrorMapper extends SubClassMapperBase<ResponseLimitError> {
  ResponseLimitErrorMapper._();

  static ResponseLimitErrorMapper? _instance;
  static ResponseLimitErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ResponseLimitErrorMapper._());
      AiErrorMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ResponseLimitError';

  static String _$message(ResponseLimitError v) => v.message;
  static const Field<ResponseLimitError, String> _f$message = Field(
    'message',
    _$message,
  );
  static int? _$limit(ResponseLimitError v) => v.limit;
  static const Field<ResponseLimitError, int> _f$limit = Field(
    'limit',
    _$limit,
    opt: true,
  );
  static Object? _$partialOutput(ResponseLimitError v) => v.partialOutput;
  static const Field<ResponseLimitError, Object> _f$partialOutput = Field(
    'partialOutput',
    _$partialOutput,
    opt: true,
  );

  @override
  final MappableFields<ResponseLimitError> fields = const {
    #message: _f$message,
    #limit: _f$limit,
    #partialOutput: _f$partialOutput,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'ResponseLimitError';
  @override
  late final ClassMapperBase superMapper = AiErrorMapper.ensureInitialized();

  static ResponseLimitError _instantiate(DecodingData data) {
    return ResponseLimitError(
      data.dec(_f$message),
      limit: data.dec(_f$limit),
      partialOutput: data.dec(_f$partialOutput),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ResponseLimitError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResponseLimitError>(map);
  }

  static ResponseLimitError fromJson(String json) {
    return ensureInitialized().decodeJson<ResponseLimitError>(json);
  }
}

mixin ResponseLimitErrorMappable {
  String toJson() {
    return ResponseLimitErrorMapper.ensureInitialized()
        .encodeJson<ResponseLimitError>(this as ResponseLimitError);
  }

  Map<String, dynamic> toMap() {
    return ResponseLimitErrorMapper.ensureInitialized()
        .encodeMap<ResponseLimitError>(this as ResponseLimitError);
  }
}

class ClientClosedErrorMapper extends SubClassMapperBase<ClientClosedError> {
  ClientClosedErrorMapper._();

  static ClientClosedErrorMapper? _instance;
  static ClientClosedErrorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ClientClosedErrorMapper._());
      AiErrorMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ClientClosedError';

  static String _$message(ClientClosedError v) => v.message;
  static const Field<ClientClosedError, String> _f$message = Field(
    'message',
    _$message,
    opt: true,
    def: 'Provider client is closed.',
  );

  @override
  final MappableFields<ClientClosedError> fields = const {#message: _f$message};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'ClientClosedError';
  @override
  late final ClassMapperBase superMapper = AiErrorMapper.ensureInitialized();

  static ClientClosedError _instantiate(DecodingData data) {
    return ClientClosedError(data.dec(_f$message));
  }

  @override
  final Function instantiate = _instantiate;

  static ClientClosedError fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ClientClosedError>(map);
  }

  static ClientClosedError fromJson(String json) {
    return ensureInitialized().decodeJson<ClientClosedError>(json);
  }
}

mixin ClientClosedErrorMappable {
  String toJson() {
    return ClientClosedErrorMapper.ensureInitialized()
        .encodeJson<ClientClosedError>(this as ClientClosedError);
  }

  Map<String, dynamic> toMap() {
    return ClientClosedErrorMapper.ensureInitialized()
        .encodeMap<ClientClosedError>(this as ClientClosedError);
  }
}


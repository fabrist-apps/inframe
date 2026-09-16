// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'native.dart';

class ResponseMetadataMapper extends ClassMapperBase<ResponseMetadata> {
  ResponseMetadataMapper._();

  static ResponseMetadataMapper? _instance;
  static ResponseMetadataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ResponseMetadataMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ResponseMetadata';

  static int _$statusCode(ResponseMetadata v) => v.statusCode;
  static const Field<ResponseMetadata, int> _f$statusCode = Field(
    'statusCode',
    _$statusCode,
  );
  static String? _$requestId(ResponseMetadata v) => v.requestId;
  static const Field<ResponseMetadata, String> _f$requestId = Field(
    'requestId',
    _$requestId,
    opt: true,
  );
  static Map<String, List<String>> _$headers(ResponseMetadata v) => v.headers;
  static const Field<ResponseMetadata, Map<String, List<String>>> _f$headers =
      Field('headers', _$headers, opt: true, def: const {});

  @override
  final MappableFields<ResponseMetadata> fields = const {
    #statusCode: _f$statusCode,
    #requestId: _f$requestId,
    #headers: _f$headers,
  };

  static ResponseMetadata _instantiate(DecodingData data) {
    return ResponseMetadata(
      statusCode: data.dec(_f$statusCode),
      requestId: data.dec(_f$requestId),
      headers: data.dec(_f$headers),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ResponseMetadata fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResponseMetadata>(map);
  }

  static ResponseMetadata fromJson(String json) {
    return ensureInitialized().decodeJson<ResponseMetadata>(json);
  }
}

mixin ResponseMetadataMappable {
  String toJson() {
    return ResponseMetadataMapper.ensureInitialized()
        .encodeJson<ResponseMetadata>(this as ResponseMetadata);
  }

  Map<String, dynamic> toMap() {
    return ResponseMetadataMapper.ensureInitialized()
        .encodeMap<ResponseMetadata>(this as ResponseMetadata);
  }
}

class NativePayloadMapper extends ClassMapperBase<NativePayload> {
  NativePayloadMapper._();

  static NativePayloadMapper? _instance;
  static NativePayloadMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = NativePayloadMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'NativePayload';

  static String _$providerId(NativePayload v) => v.providerId;
  static const Field<NativePayload, String> _f$providerId = Field(
    'providerId',
    _$providerId,
  );
  static String _$api(NativePayload v) => v.api;
  static const Field<NativePayload, String> _f$api = Field('api', _$api);
  static String _$modelId(NativePayload v) => v.modelId;
  static const Field<NativePayload, String> _f$modelId = Field(
    'modelId',
    _$modelId,
  );
  static Object? _$data(NativePayload v) => v.data;
  static const Field<NativePayload, Object> _f$data = Field('data', _$data);
  static List<Map<String, Object?>> _$unknownEvents(NativePayload v) =>
      v.unknownEvents;
  static const Field<NativePayload, List<Map<String, Object?>>>
  _f$unknownEvents = Field(
    'unknownEvents',
    _$unknownEvents,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<NativePayload> fields = const {
    #providerId: _f$providerId,
    #api: _f$api,
    #modelId: _f$modelId,
    #data: _f$data,
    #unknownEvents: _f$unknownEvents,
  };

  static NativePayload _instantiate(DecodingData data) {
    return NativePayload(
      providerId: data.dec(_f$providerId),
      api: data.dec(_f$api),
      modelId: data.dec(_f$modelId),
      data: data.dec(_f$data),
      unknownEvents: data.dec(_f$unknownEvents),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static NativePayload fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NativePayload>(map);
  }

  static NativePayload fromJson(String json) {
    return ensureInitialized().decodeJson<NativePayload>(json);
  }
}

mixin NativePayloadMappable {
  String toJson() {
    return NativePayloadMapper.ensureInitialized().encodeJson<NativePayload>(
      this as NativePayload,
    );
  }

  Map<String, dynamic> toMap() {
    return NativePayloadMapper.ensureInitialized().encodeMap<NativePayload>(
      this as NativePayload,
    );
  }
}

class NativeResponseMapper extends ClassMapperBase<NativeResponse> {
  NativeResponseMapper._();

  static NativeResponseMapper? _instance;
  static NativeResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = NativeResponseMapper._());
      NativePayloadMapper.ensureInitialized();
      ResponseMetadataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'NativeResponse';
  @override
  Function get typeFactory =>
      <T>(f) => f<NativeResponse<T>>();

  static dynamic _$value(NativeResponse v) => v.value;
  static dynamic _arg$value<T>(f) => f<T>();
  static const Field<NativeResponse, dynamic> _f$value = Field(
    'value',
    _$value,
    arg: _arg$value,
  );
  static NativePayload _$raw(NativeResponse v) => v.raw;
  static const Field<NativeResponse, NativePayload> _f$raw = Field(
    'raw',
    _$raw,
  );
  static ResponseMetadata _$metadata(NativeResponse v) => v.metadata;
  static const Field<NativeResponse, ResponseMetadata> _f$metadata = Field(
    'metadata',
    _$metadata,
  );

  @override
  final MappableFields<NativeResponse> fields = const {
    #value: _f$value,
    #raw: _f$raw,
    #metadata: _f$metadata,
  };

  static NativeResponse<T> _instantiate<T>(DecodingData data) {
    return NativeResponse(
      value: data.dec(_f$value),
      raw: data.dec(_f$raw),
      metadata: data.dec(_f$metadata),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static NativeResponse<T> fromMap<T>(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NativeResponse<T>>(map);
  }

  static NativeResponse<T> fromJson<T>(String json) {
    return ensureInitialized().decodeJson<NativeResponse<T>>(json);
  }
}

mixin NativeResponseMappable<T> {
  String toJson() {
    return NativeResponseMapper.ensureInitialized()
        .encodeJson<NativeResponse<T>>(this as NativeResponse<T>);
  }

  Map<String, dynamic> toMap() {
    return NativeResponseMapper.ensureInitialized()
        .encodeMap<NativeResponse<T>>(this as NativeResponse<T>);
  }
}


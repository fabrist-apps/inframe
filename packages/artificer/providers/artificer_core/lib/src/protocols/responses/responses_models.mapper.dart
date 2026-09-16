// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'responses_models.dart';

class ResponsesOptionsMapper extends ClassMapperBase<ResponsesOptions> {
  ResponsesOptionsMapper._();

  static ResponsesOptionsMapper? _instance;
  static ResponsesOptionsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ResponsesOptionsMapper._());
      SettingMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ResponsesOptions';

  static Setting<List<Map<String, Object?>>> _$nativeTools(
    ResponsesOptions v,
  ) => v.nativeTools;
  static const Field<ResponsesOptions, Setting<List<Map<String, Object?>>>>
  _f$nativeTools = Field(
    'nativeTools',
    _$nativeTools,
    opt: true,
    def: const Setting.inherit(),
  );
  static Setting<Map<String, Object?>> _$extraBody(ResponsesOptions v) =>
      v.extraBody;
  static const Field<ResponsesOptions, Setting<Map<String, Object?>>>
  _f$extraBody = Field(
    'extraBody',
    _$extraBody,
    opt: true,
    def: const Setting.inherit(),
  );

  @override
  final MappableFields<ResponsesOptions> fields = const {
    #nativeTools: _f$nativeTools,
    #extraBody: _f$extraBody,
  };

  static ResponsesOptions _instantiate(DecodingData data) {
    return ResponsesOptions(
      nativeTools: data.dec(_f$nativeTools),
      extraBody: data.dec(_f$extraBody),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ResponsesOptions fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResponsesOptions>(map);
  }

  static ResponsesOptions fromJson(String json) {
    return ensureInitialized().decodeJson<ResponsesOptions>(json);
  }
}

mixin ResponsesOptionsMappable {
  String toJson() {
    return ResponsesOptionsMapper.ensureInitialized()
        .encodeJson<ResponsesOptions>(this as ResponsesOptions);
  }

  Map<String, dynamic> toMap() {
    return ResponsesOptionsMapper.ensureInitialized()
        .encodeMap<ResponsesOptions>(this as ResponsesOptions);
  }
}

class ResponsesRequestMapper extends ClassMapperBase<ResponsesRequest> {
  ResponsesRequestMapper._();

  static ResponsesRequestMapper? _instance;
  static ResponsesRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ResponsesRequestMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ResponsesRequest';

  static String _$model(ResponsesRequest v) => v.model;
  static const Field<ResponsesRequest, String> _f$model = Field(
    'model',
    _$model,
  );
  static List<Map<String, Object?>> _$input(ResponsesRequest v) => v.input;
  static const Field<ResponsesRequest, List<Map<String, Object?>>> _f$input =
      Field('input', _$input, hook: JsonValueHook());
  static String? _$instructions(ResponsesRequest v) => v.instructions;
  static const Field<ResponsesRequest, String> _f$instructions = Field(
    'instructions',
    _$instructions,
    opt: true,
  );
  static List<Map<String, Object?>> _$tools(ResponsesRequest v) => v.tools;
  static const Field<ResponsesRequest, List<Map<String, Object?>>> _f$tools =
      Field('tools', _$tools, opt: true, def: const [], hook: JsonValueHook());
  static Object? _$toolChoice(ResponsesRequest v) => v.toolChoice;
  static const Field<ResponsesRequest, Object> _f$toolChoice = Field(
    'toolChoice',
    _$toolChoice,
    opt: true,
    hook: JsonValueHook(),
  );
  static Map<String, Object?>? _$text(ResponsesRequest v) => v.text;
  static const Field<ResponsesRequest, Map<String, Object?>> _f$text = Field(
    'text',
    _$text,
    opt: true,
    hook: JsonValueHook(),
  );
  static int? _$maxOutputTokens(ResponsesRequest v) => v.maxOutputTokens;
  static const Field<ResponsesRequest, int> _f$maxOutputTokens = Field(
    'maxOutputTokens',
    _$maxOutputTokens,
    opt: true,
  );
  static double? _$temperature(ResponsesRequest v) => v.temperature;
  static const Field<ResponsesRequest, double> _f$temperature = Field(
    'temperature',
    _$temperature,
    opt: true,
  );
  static double? _$topP(ResponsesRequest v) => v.topP;
  static const Field<ResponsesRequest, double> _f$topP = Field(
    'topP',
    _$topP,
    opt: true,
  );
  static Map<String, Object?> _$extraBody(ResponsesRequest v) => v.extraBody;
  static const Field<ResponsesRequest, Map<String, Object?>> _f$extraBody =
      Field(
        'extraBody',
        _$extraBody,
        opt: true,
        def: const {},
        hook: JsonValueHook(),
      );

  @override
  final MappableFields<ResponsesRequest> fields = const {
    #model: _f$model,
    #input: _f$input,
    #instructions: _f$instructions,
    #tools: _f$tools,
    #toolChoice: _f$toolChoice,
    #text: _f$text,
    #maxOutputTokens: _f$maxOutputTokens,
    #temperature: _f$temperature,
    #topP: _f$topP,
    #extraBody: _f$extraBody,
  };

  static ResponsesRequest _instantiate(DecodingData data) {
    return ResponsesRequest(
      model: data.dec(_f$model),
      input: data.dec(_f$input),
      instructions: data.dec(_f$instructions),
      tools: data.dec(_f$tools),
      toolChoice: data.dec(_f$toolChoice),
      text: data.dec(_f$text),
      maxOutputTokens: data.dec(_f$maxOutputTokens),
      temperature: data.dec(_f$temperature),
      topP: data.dec(_f$topP),
      extraBody: data.dec(_f$extraBody),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ResponsesRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResponsesRequest>(map);
  }

  static ResponsesRequest fromJson(String json) {
    return ensureInitialized().decodeJson<ResponsesRequest>(json);
  }
}

mixin ResponsesRequestMappable {
  String toJson() {
    return ResponsesRequestMapper.ensureInitialized()
        .encodeJson<ResponsesRequest>(this as ResponsesRequest);
  }

  Map<String, dynamic> toMap() {
    return ResponsesRequestMapper.ensureInitialized()
        .encodeMap<ResponsesRequest>(this as ResponsesRequest);
  }
}

class ResponsesResponseMapper extends ClassMapperBase<ResponsesResponse> {
  ResponsesResponseMapper._();

  static ResponsesResponseMapper? _instance;
  static ResponsesResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ResponsesResponseMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ResponsesResponse';

  static String _$id(ResponsesResponse v) => v.id;
  static const Field<ResponsesResponse, String> _f$id = Field('id', _$id);
  static String _$model(ResponsesResponse v) => v.model;
  static const Field<ResponsesResponse, String> _f$model = Field(
    'model',
    _$model,
  );
  static String _$status(ResponsesResponse v) => v.status;
  static const Field<ResponsesResponse, String> _f$status = Field(
    'status',
    _$status,
  );
  static List<Map<String, Object?>> _$output(ResponsesResponse v) => v.output;
  static const Field<ResponsesResponse, List<Map<String, Object?>>> _f$output =
      Field('output', _$output, hook: JsonValueHook());
  static Map<String, Object?>? _$usage(ResponsesResponse v) => v.usage;
  static const Field<ResponsesResponse, Map<String, Object?>> _f$usage = Field(
    'usage',
    _$usage,
    opt: true,
    hook: JsonValueHook(),
  );
  static Map<String, Object?>? _$error(ResponsesResponse v) => v.error;
  static const Field<ResponsesResponse, Map<String, Object?>> _f$error = Field(
    'error',
    _$error,
    opt: true,
    hook: JsonValueHook(),
  );
  static Map<String, Object?>? _$incompleteDetails(ResponsesResponse v) =>
      v.incompleteDetails;
  static const Field<ResponsesResponse, Map<String, Object?>>
  _f$incompleteDetails = Field(
    'incompleteDetails',
    _$incompleteDetails,
    key: r'incomplete_details',
    opt: true,
    hook: JsonValueHook(),
  );
  static List<Map<String, Object?>> _$candidates(ResponsesResponse v) =>
      v.candidates;
  static const Field<ResponsesResponse, List<Map<String, Object?>>>
  _f$candidates = Field(
    'candidates',
    _$candidates,
    opt: true,
    def: const [],
    hook: JsonValueHook(),
  );

  @override
  final MappableFields<ResponsesResponse> fields = const {
    #id: _f$id,
    #model: _f$model,
    #status: _f$status,
    #output: _f$output,
    #usage: _f$usage,
    #error: _f$error,
    #incompleteDetails: _f$incompleteDetails,
    #candidates: _f$candidates,
  };

  static ResponsesResponse _instantiate(DecodingData data) {
    return ResponsesResponse(
      id: data.dec(_f$id),
      model: data.dec(_f$model),
      status: data.dec(_f$status),
      output: data.dec(_f$output),
      usage: data.dec(_f$usage),
      error: data.dec(_f$error),
      incompleteDetails: data.dec(_f$incompleteDetails),
      candidates: data.dec(_f$candidates),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ResponsesResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResponsesResponse>(map);
  }

  static ResponsesResponse fromJson(String json) {
    return ensureInitialized().decodeJson<ResponsesResponse>(json);
  }
}

mixin ResponsesResponseMappable {
  String toJson() {
    return ResponsesResponseMapper.ensureInitialized()
        .encodeJson<ResponsesResponse>(this as ResponsesResponse);
  }

  Map<String, dynamic> toMap() {
    return ResponsesResponseMapper.ensureInitialized()
        .encodeMap<ResponsesResponse>(this as ResponsesResponse);
  }
}


// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'generation.dart';

class FinishReasonMapper extends EnumMapper<FinishReason> {
  FinishReasonMapper._();

  static FinishReasonMapper? _instance;
  static FinishReasonMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FinishReasonMapper._());
    }
    return _instance!;
  }

  static FinishReason fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  FinishReason decode(dynamic value) {
    switch (value) {
      case r'stop':
        return FinishReason.stop;
      case r'toolCalls':
        return FinishReason.toolCalls;
      case r'outputLimit':
        return FinishReason.outputLimit;
      case r'refusal':
        return FinishReason.refusal;
      case r'contentFilter':
        return FinishReason.contentFilter;
      case r'paused':
        return FinishReason.paused;
      case r'other':
        return FinishReason.other;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(FinishReason self) {
    switch (self) {
      case FinishReason.stop:
        return r'stop';
      case FinishReason.toolCalls:
        return r'toolCalls';
      case FinishReason.outputLimit:
        return r'outputLimit';
      case FinishReason.refusal:
        return r'refusal';
      case FinishReason.contentFilter:
        return r'contentFilter';
      case FinishReason.paused:
        return r'paused';
      case FinishReason.other:
        return r'other';
    }
  }
}

extension FinishReasonMapperExtension on FinishReason {
  String toValue() {
    FinishReasonMapper.ensureInitialized();
    return MapperContainer.globals.toValue<FinishReason>(this) as String;
  }
}

class GenerationOptionsMapper extends ClassMapperBase<GenerationOptions> {
  GenerationOptionsMapper._();

  static GenerationOptionsMapper? _instance;
  static GenerationOptionsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GenerationOptionsMapper._());
      SettingMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GenerationOptions';

  static Setting<int> _$maxOutputTokens(GenerationOptions v) =>
      v.maxOutputTokens;
  static const Field<GenerationOptions, Setting<int>> _f$maxOutputTokens =
      Field(
        'maxOutputTokens',
        _$maxOutputTokens,
        opt: true,
        def: const Setting.inherit(),
      );
  static Setting<double> _$temperature(GenerationOptions v) => v.temperature;
  static const Field<GenerationOptions, Setting<double>> _f$temperature = Field(
    'temperature',
    _$temperature,
    opt: true,
    def: const Setting.inherit(),
  );
  static Setting<double> _$topP(GenerationOptions v) => v.topP;
  static const Field<GenerationOptions, Setting<double>> _f$topP = Field(
    'topP',
    _$topP,
    opt: true,
    def: const Setting.inherit(),
  );
  static Setting<List<String>> _$stop(GenerationOptions v) => v.stop;
  static const Field<GenerationOptions, Setting<List<String>>> _f$stop = Field(
    'stop',
    _$stop,
    opt: true,
    def: const Setting.inherit(),
  );

  @override
  final MappableFields<GenerationOptions> fields = const {
    #maxOutputTokens: _f$maxOutputTokens,
    #temperature: _f$temperature,
    #topP: _f$topP,
    #stop: _f$stop,
  };

  static GenerationOptions _instantiate(DecodingData data) {
    return GenerationOptions(
      maxOutputTokens: data.dec(_f$maxOutputTokens),
      temperature: data.dec(_f$temperature),
      topP: data.dec(_f$topP),
      stop: data.dec(_f$stop),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GenerationOptions fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GenerationOptions>(map);
  }

  static GenerationOptions fromJson(String json) {
    return ensureInitialized().decodeJson<GenerationOptions>(json);
  }
}

mixin GenerationOptionsMappable {
  String toJson() {
    return GenerationOptionsMapper.ensureInitialized()
        .encodeJson<GenerationOptions>(this as GenerationOptions);
  }

  Map<String, dynamic> toMap() {
    return GenerationOptionsMapper.ensureInitialized()
        .encodeMap<GenerationOptions>(this as GenerationOptions);
  }
}

class ResolvedGenerationOptionsMapper
    extends ClassMapperBase<ResolvedGenerationOptions> {
  ResolvedGenerationOptionsMapper._();

  static ResolvedGenerationOptionsMapper? _instance;
  static ResolvedGenerationOptionsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ResolvedGenerationOptionsMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'ResolvedGenerationOptions';

  static int? _$maxOutputTokens(ResolvedGenerationOptions v) =>
      v.maxOutputTokens;
  static const Field<ResolvedGenerationOptions, int> _f$maxOutputTokens = Field(
    'maxOutputTokens',
    _$maxOutputTokens,
    opt: true,
  );
  static double? _$temperature(ResolvedGenerationOptions v) => v.temperature;
  static const Field<ResolvedGenerationOptions, double> _f$temperature = Field(
    'temperature',
    _$temperature,
    opt: true,
  );
  static double? _$topP(ResolvedGenerationOptions v) => v.topP;
  static const Field<ResolvedGenerationOptions, double> _f$topP = Field(
    'topP',
    _$topP,
    opt: true,
  );
  static List<String>? _$stop(ResolvedGenerationOptions v) => v.stop;
  static const Field<ResolvedGenerationOptions, List<String>> _f$stop = Field(
    'stop',
    _$stop,
    opt: true,
  );

  @override
  final MappableFields<ResolvedGenerationOptions> fields = const {
    #maxOutputTokens: _f$maxOutputTokens,
    #temperature: _f$temperature,
    #topP: _f$topP,
    #stop: _f$stop,
  };

  static ResolvedGenerationOptions _instantiate(DecodingData data) {
    return ResolvedGenerationOptions(
      maxOutputTokens: data.dec(_f$maxOutputTokens),
      temperature: data.dec(_f$temperature),
      topP: data.dec(_f$topP),
      stop: data.dec(_f$stop),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ResolvedGenerationOptions fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ResolvedGenerationOptions>(map);
  }

  static ResolvedGenerationOptions fromJson(String json) {
    return ensureInitialized().decodeJson<ResolvedGenerationOptions>(json);
  }
}

mixin ResolvedGenerationOptionsMappable {
  String toJson() {
    return ResolvedGenerationOptionsMapper.ensureInitialized()
        .encodeJson<ResolvedGenerationOptions>(
          this as ResolvedGenerationOptions,
        );
  }

  Map<String, dynamic> toMap() {
    return ResolvedGenerationOptionsMapper.ensureInitialized()
        .encodeMap<ResolvedGenerationOptions>(
          this as ResolvedGenerationOptions,
        );
  }
}

class GenerationRequestMapper extends ClassMapperBase<GenerationRequest> {
  GenerationRequestMapper._();

  static GenerationRequestMapper? _instance;
  static GenerationRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GenerationRequestMapper._());
      MessageMapper.ensureInitialized();
      GenerationOptionsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GenerationRequest';

  static List<Message> _$messages(GenerationRequest v) => v.messages;
  static const Field<GenerationRequest, List<Message>> _f$messages = Field(
    'messages',
    _$messages,
  );
  static String? _$instructions(GenerationRequest v) => v.instructions;
  static const Field<GenerationRequest, String> _f$instructions = Field(
    'instructions',
    _$instructions,
    opt: true,
  );
  static GenerationOptions _$options(GenerationRequest v) => v.options;
  static const Field<GenerationRequest, GenerationOptions> _f$options = Field(
    'options',
    _$options,
    opt: true,
    def: const GenerationOptions(),
  );

  @override
  final MappableFields<GenerationRequest> fields = const {
    #messages: _f$messages,
    #instructions: _f$instructions,
    #options: _f$options,
  };

  static GenerationRequest _instantiate(DecodingData data) {
    return GenerationRequest(
      messages: data.dec(_f$messages),
      instructions: data.dec(_f$instructions),
      options: data.dec(_f$options),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GenerationRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GenerationRequest>(map);
  }

  static GenerationRequest fromJson(String json) {
    return ensureInitialized().decodeJson<GenerationRequest>(json);
  }
}

mixin GenerationRequestMappable {
  String toJson() {
    return GenerationRequestMapper.ensureInitialized()
        .encodeJson<GenerationRequest>(this as GenerationRequest);
  }

  Map<String, dynamic> toMap() {
    return GenerationRequestMapper.ensureInitialized()
        .encodeMap<GenerationRequest>(this as GenerationRequest);
  }
}

class UsageMapper extends ClassMapperBase<Usage> {
  UsageMapper._();

  static UsageMapper? _instance;
  static UsageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = UsageMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Usage';

  static int? _$inputTokens(Usage v) => v.inputTokens;
  static const Field<Usage, int> _f$inputTokens = Field(
    'inputTokens',
    _$inputTokens,
    opt: true,
  );
  static int? _$outputTokens(Usage v) => v.outputTokens;
  static const Field<Usage, int> _f$outputTokens = Field(
    'outputTokens',
    _$outputTokens,
    opt: true,
  );
  static int? _$totalTokens(Usage v) => v.totalTokens;
  static const Field<Usage, int> _f$totalTokens = Field(
    'totalTokens',
    _$totalTokens,
    opt: true,
  );

  @override
  final MappableFields<Usage> fields = const {
    #inputTokens: _f$inputTokens,
    #outputTokens: _f$outputTokens,
    #totalTokens: _f$totalTokens,
  };

  static Usage _instantiate(DecodingData data) {
    return Usage(
      inputTokens: data.dec(_f$inputTokens),
      outputTokens: data.dec(_f$outputTokens),
      totalTokens: data.dec(_f$totalTokens),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Usage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Usage>(map);
  }

  static Usage fromJson(String json) {
    return ensureInitialized().decodeJson<Usage>(json);
  }
}

mixin UsageMappable {
  String toJson() {
    return UsageMapper.ensureInitialized().encodeJson<Usage>(this as Usage);
  }

  Map<String, dynamic> toMap() {
    return UsageMapper.ensureInitialized().encodeMap<Usage>(this as Usage);
  }
}

class GenerationResultMapper extends ClassMapperBase<GenerationResult> {
  GenerationResultMapper._();

  static GenerationResultMapper? _instance;
  static GenerationResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GenerationResultMapper._());
      AssistantMessageMapper.ensureInitialized();
      FinishReasonMapper.ensureInitialized();
      NativePayloadMapper.ensureInitialized();
      UsageMapper.ensureInitialized();
      ResponseMetadataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GenerationResult';

  static AssistantMessage _$message(GenerationResult v) => v.message;
  static const Field<GenerationResult, AssistantMessage> _f$message = Field(
    'message',
    _$message,
  );
  static FinishReason _$finishReason(GenerationResult v) => v.finishReason;
  static const Field<GenerationResult, FinishReason> _f$finishReason = Field(
    'finishReason',
    _$finishReason,
  );
  static NativePayload _$native(GenerationResult v) => v.native;
  static const Field<GenerationResult, NativePayload> _f$native = Field(
    'native',
    _$native,
  );
  static String? _$nativeFinishReason(GenerationResult v) =>
      v.nativeFinishReason;
  static const Field<GenerationResult, String> _f$nativeFinishReason = Field(
    'nativeFinishReason',
    _$nativeFinishReason,
    opt: true,
  );
  static Usage? _$usage(GenerationResult v) => v.usage;
  static const Field<GenerationResult, Usage> _f$usage = Field(
    'usage',
    _$usage,
    opt: true,
  );
  static String? _$responseId(GenerationResult v) => v.responseId;
  static const Field<GenerationResult, String> _f$responseId = Field(
    'responseId',
    _$responseId,
    opt: true,
  );
  static ResponseMetadata? _$metadata(GenerationResult v) => v.metadata;
  static const Field<GenerationResult, ResponseMetadata> _f$metadata = Field(
    'metadata',
    _$metadata,
    opt: true,
  );
  static int _$schemaVersion(GenerationResult v) => v.schemaVersion;
  static const Field<GenerationResult, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<GenerationResult> fields = const {
    #message: _f$message,
    #finishReason: _f$finishReason,
    #native: _f$native,
    #nativeFinishReason: _f$nativeFinishReason,
    #usage: _f$usage,
    #responseId: _f$responseId,
    #metadata: _f$metadata,
    #schemaVersion: _f$schemaVersion,
  };

  static GenerationResult _instantiate(DecodingData data) {
    return GenerationResult(
      message: data.dec(_f$message),
      finishReason: data.dec(_f$finishReason),
      native: data.dec(_f$native),
      nativeFinishReason: data.dec(_f$nativeFinishReason),
      usage: data.dec(_f$usage),
      responseId: data.dec(_f$responseId),
      metadata: data.dec(_f$metadata),
      schemaVersion: data.dec(_f$schemaVersion),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GenerationResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GenerationResult>(map);
  }

  static GenerationResult fromJson(String json) {
    return ensureInitialized().decodeJson<GenerationResult>(json);
  }
}

mixin GenerationResultMappable {
  String toJson() {
    return GenerationResultMapper.ensureInitialized()
        .encodeJson<GenerationResult>(this as GenerationResult);
  }

  Map<String, dynamic> toMap() {
    return GenerationResultMapper.ensureInitialized()
        .encodeMap<GenerationResult>(this as GenerationResult);
  }
}

class GenerationEventMapper extends ClassMapperBase<GenerationEvent> {
  GenerationEventMapper._();

  static GenerationEventMapper? _instance;
  static GenerationEventMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GenerationEventMapper._());
      GenerationFinishedMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GenerationEvent';

  @override
  final MappableFields<GenerationEvent> fields = const {};

  static GenerationEvent _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'GenerationEvent',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GenerationEvent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GenerationEvent>(map);
  }

  static GenerationEvent fromJson(String json) {
    return ensureInitialized().decodeJson<GenerationEvent>(json);
  }
}

mixin GenerationEventMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class GenerationFinishedMapper extends SubClassMapperBase<GenerationFinished> {
  GenerationFinishedMapper._();

  static GenerationFinishedMapper? _instance;
  static GenerationFinishedMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GenerationFinishedMapper._());
      GenerationEventMapper.ensureInitialized().addSubMapper(_instance!);
      GenerationResultMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GenerationFinished';

  static GenerationResult _$result(GenerationFinished v) => v.result;
  static const Field<GenerationFinished, GenerationResult> _f$result = Field(
    'result',
    _$result,
  );

  @override
  final MappableFields<GenerationFinished> fields = const {#result: _f$result};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'finished';
  @override
  late final ClassMapperBase superMapper =
      GenerationEventMapper.ensureInitialized();

  static GenerationFinished _instantiate(DecodingData data) {
    return GenerationFinished(data.dec(_f$result));
  }

  @override
  final Function instantiate = _instantiate;

  static GenerationFinished fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GenerationFinished>(map);
  }

  static GenerationFinished fromJson(String json) {
    return ensureInitialized().decodeJson<GenerationFinished>(json);
  }
}

mixin GenerationFinishedMappable {
  String toJson() {
    return GenerationFinishedMapper.ensureInitialized()
        .encodeJson<GenerationFinished>(this as GenerationFinished);
  }

  Map<String, dynamic> toMap() {
    return GenerationFinishedMapper.ensureInitialized()
        .encodeMap<GenerationFinished>(this as GenerationFinished);
  }
}


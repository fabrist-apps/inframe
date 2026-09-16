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

class GenerationPartKindMapper extends EnumMapper<GenerationPartKind> {
  GenerationPartKindMapper._();

  static GenerationPartKindMapper? _instance;
  static GenerationPartKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GenerationPartKindMapper._());
    }
    return _instance!;
  }

  static GenerationPartKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  GenerationPartKind decode(dynamic value) {
    switch (value) {
      case r'text':
        return GenerationPartKind.text;
      case r'reasoning':
        return GenerationPartKind.reasoning;
      case r'refusal':
        return GenerationPartKind.refusal;
      case r'toolCall':
        return GenerationPartKind.toolCall;
      case r'providerTool':
        return GenerationPartKind.providerTool;
      case r'opaque':
        return GenerationPartKind.opaque;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(GenerationPartKind self) {
    switch (self) {
      case GenerationPartKind.text:
        return r'text';
      case GenerationPartKind.reasoning:
        return r'reasoning';
      case GenerationPartKind.refusal:
        return r'refusal';
      case GenerationPartKind.toolCall:
        return r'toolCall';
      case GenerationPartKind.providerTool:
        return r'providerTool';
      case GenerationPartKind.opaque:
        return r'opaque';
    }
  }
}

extension GenerationPartKindMapperExtension on GenerationPartKind {
  String toValue() {
    GenerationPartKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<GenerationPartKind>(this) as String;
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
      FunctionToolMapper.ensureInitialized();
      ToolChoiceMapper.ensureInitialized();
      OutputFormatMapper.ensureInitialized();
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
  static List<FunctionTool> _$tools(GenerationRequest v) => v.tools;
  static const Field<GenerationRequest, List<FunctionTool>> _f$tools = Field(
    'tools',
    _$tools,
    opt: true,
    def: const [],
  );
  static ToolChoice _$toolChoice(GenerationRequest v) => v.toolChoice;
  static const Field<GenerationRequest, ToolChoice> _f$toolChoice = Field(
    'toolChoice',
    _$toolChoice,
    opt: true,
    def: const AutoToolChoice(),
  );
  static OutputFormat _$output(GenerationRequest v) => v.output;
  static const Field<GenerationRequest, OutputFormat> _f$output = Field(
    'output',
    _$output,
    opt: true,
    def: const TextOutput(),
  );

  @override
  final MappableFields<GenerationRequest> fields = const {
    #messages: _f$messages,
    #instructions: _f$instructions,
    #options: _f$options,
    #tools: _f$tools,
    #toolChoice: _f$toolChoice,
    #output: _f$output,
  };

  static GenerationRequest _instantiate(DecodingData data) {
    return GenerationRequest(
      messages: data.dec(_f$messages),
      instructions: data.dec(_f$instructions),
      options: data.dec(_f$options),
      tools: data.dec(_f$tools),
      toolChoice: data.dec(_f$toolChoice),
      output: data.dec(_f$output),
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
      GenerationStartedMapper.ensureInitialized();
      PartStartedMapper.ensureInitialized();
      PartDeltaMapper.ensureInitialized();
      PartFinishedMapper.ensureInitialized();
      UsageUpdatedMapper.ensureInitialized();
      ProviderEventMapper.ensureInitialized();
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

class ContentDeltaMapper extends ClassMapperBase<ContentDelta> {
  ContentDeltaMapper._();

  static ContentDeltaMapper? _instance;
  static ContentDeltaMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ContentDeltaMapper._());
      TextDeltaMapper.ensureInitialized();
      ReasoningDeltaMapper.ensureInitialized();
      ToolArgumentsDeltaMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ContentDelta';

  @override
  final MappableFields<ContentDelta> fields = const {};

  static ContentDelta _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'ContentDelta',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ContentDelta fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ContentDelta>(map);
  }

  static ContentDelta fromJson(String json) {
    return ensureInitialized().decodeJson<ContentDelta>(json);
  }
}

mixin ContentDeltaMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class TextDeltaMapper extends SubClassMapperBase<TextDelta> {
  TextDeltaMapper._();

  static TextDeltaMapper? _instance;
  static TextDeltaMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TextDeltaMapper._());
      ContentDeltaMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'TextDelta';

  static String _$text(TextDelta v) => v.text;
  static const Field<TextDelta, String> _f$text = Field('text', _$text);

  @override
  final MappableFields<TextDelta> fields = const {#text: _f$text};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'text';
  @override
  late final ClassMapperBase superMapper =
      ContentDeltaMapper.ensureInitialized();

  static TextDelta _instantiate(DecodingData data) {
    return TextDelta(text: data.dec(_f$text));
  }

  @override
  final Function instantiate = _instantiate;

  static TextDelta fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TextDelta>(map);
  }

  static TextDelta fromJson(String json) {
    return ensureInitialized().decodeJson<TextDelta>(json);
  }
}

mixin TextDeltaMappable {
  String toJson() {
    return TextDeltaMapper.ensureInitialized().encodeJson<TextDelta>(
      this as TextDelta,
    );
  }

  Map<String, dynamic> toMap() {
    return TextDeltaMapper.ensureInitialized().encodeMap<TextDelta>(
      this as TextDelta,
    );
  }
}

class ReasoningDeltaMapper extends SubClassMapperBase<ReasoningDelta> {
  ReasoningDeltaMapper._();

  static ReasoningDeltaMapper? _instance;
  static ReasoningDeltaMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ReasoningDeltaMapper._());
      ContentDeltaMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ReasoningDelta';

  static String _$text(ReasoningDelta v) => v.text;
  static const Field<ReasoningDelta, String> _f$text = Field('text', _$text);

  @override
  final MappableFields<ReasoningDelta> fields = const {#text: _f$text};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'reasoning';
  @override
  late final ClassMapperBase superMapper =
      ContentDeltaMapper.ensureInitialized();

  static ReasoningDelta _instantiate(DecodingData data) {
    return ReasoningDelta(text: data.dec(_f$text));
  }

  @override
  final Function instantiate = _instantiate;

  static ReasoningDelta fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ReasoningDelta>(map);
  }

  static ReasoningDelta fromJson(String json) {
    return ensureInitialized().decodeJson<ReasoningDelta>(json);
  }
}

mixin ReasoningDeltaMappable {
  String toJson() {
    return ReasoningDeltaMapper.ensureInitialized().encodeJson<ReasoningDelta>(
      this as ReasoningDelta,
    );
  }

  Map<String, dynamic> toMap() {
    return ReasoningDeltaMapper.ensureInitialized().encodeMap<ReasoningDelta>(
      this as ReasoningDelta,
    );
  }
}

class ToolArgumentsDeltaMapper extends SubClassMapperBase<ToolArgumentsDelta> {
  ToolArgumentsDeltaMapper._();

  static ToolArgumentsDeltaMapper? _instance;
  static ToolArgumentsDeltaMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolArgumentsDeltaMapper._());
      ContentDeltaMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ToolArgumentsDelta';

  static String _$text(ToolArgumentsDelta v) => v.text;
  static const Field<ToolArgumentsDelta, String> _f$text = Field(
    'text',
    _$text,
  );

  @override
  final MappableFields<ToolArgumentsDelta> fields = const {#text: _f$text};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'toolArguments';
  @override
  late final ClassMapperBase superMapper =
      ContentDeltaMapper.ensureInitialized();

  static ToolArgumentsDelta _instantiate(DecodingData data) {
    return ToolArgumentsDelta(text: data.dec(_f$text));
  }

  @override
  final Function instantiate = _instantiate;

  static ToolArgumentsDelta fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolArgumentsDelta>(map);
  }

  static ToolArgumentsDelta fromJson(String json) {
    return ensureInitialized().decodeJson<ToolArgumentsDelta>(json);
  }
}

mixin ToolArgumentsDeltaMappable {
  String toJson() {
    return ToolArgumentsDeltaMapper.ensureInitialized()
        .encodeJson<ToolArgumentsDelta>(this as ToolArgumentsDelta);
  }

  Map<String, dynamic> toMap() {
    return ToolArgumentsDeltaMapper.ensureInitialized()
        .encodeMap<ToolArgumentsDelta>(this as ToolArgumentsDelta);
  }
}

class GenerationStartedMapper extends SubClassMapperBase<GenerationStarted> {
  GenerationStartedMapper._();

  static GenerationStartedMapper? _instance;
  static GenerationStartedMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GenerationStartedMapper._());
      GenerationEventMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'GenerationStarted';

  static String? _$responseId(GenerationStarted v) => v.responseId;
  static const Field<GenerationStarted, String> _f$responseId = Field(
    'responseId',
    _$responseId,
    opt: true,
  );
  static String? _$requestId(GenerationStarted v) => v.requestId;
  static const Field<GenerationStarted, String> _f$requestId = Field(
    'requestId',
    _$requestId,
    opt: true,
  );

  @override
  final MappableFields<GenerationStarted> fields = const {
    #responseId: _f$responseId,
    #requestId: _f$requestId,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'started';
  @override
  late final ClassMapperBase superMapper =
      GenerationEventMapper.ensureInitialized();

  static GenerationStarted _instantiate(DecodingData data) {
    return GenerationStarted(
      responseId: data.dec(_f$responseId),
      requestId: data.dec(_f$requestId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GenerationStarted fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GenerationStarted>(map);
  }

  static GenerationStarted fromJson(String json) {
    return ensureInitialized().decodeJson<GenerationStarted>(json);
  }
}

mixin GenerationStartedMappable {
  String toJson() {
    return GenerationStartedMapper.ensureInitialized()
        .encodeJson<GenerationStarted>(this as GenerationStarted);
  }

  Map<String, dynamic> toMap() {
    return GenerationStartedMapper.ensureInitialized()
        .encodeMap<GenerationStarted>(this as GenerationStarted);
  }
}

class PartStartedMapper extends SubClassMapperBase<PartStarted> {
  PartStartedMapper._();

  static PartStartedMapper? _instance;
  static PartStartedMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PartStartedMapper._());
      GenerationEventMapper.ensureInitialized().addSubMapper(_instance!);
      GenerationPartKindMapper.ensureInitialized();
      ToolExecutionOwnerMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PartStarted';

  static String _$id(PartStarted v) => v.id;
  static const Field<PartStarted, String> _f$id = Field('id', _$id);
  static int _$index(PartStarted v) => v.index;
  static const Field<PartStarted, int> _f$index = Field('index', _$index);
  static GenerationPartKind _$kind(PartStarted v) => v.kind;
  static const Field<PartStarted, GenerationPartKind> _f$kind = Field(
    'kind',
    _$kind,
  );
  static String? _$callId(PartStarted v) => v.callId;
  static const Field<PartStarted, String> _f$callId = Field(
    'callId',
    _$callId,
    opt: true,
  );
  static String? _$name(PartStarted v) => v.name;
  static const Field<PartStarted, String> _f$name = Field(
    'name',
    _$name,
    opt: true,
  );
  static ToolExecutionOwner? _$owner(PartStarted v) => v.owner;
  static const Field<PartStarted, ToolExecutionOwner> _f$owner = Field(
    'owner',
    _$owner,
    opt: true,
  );

  @override
  final MappableFields<PartStarted> fields = const {
    #id: _f$id,
    #index: _f$index,
    #kind: _f$kind,
    #callId: _f$callId,
    #name: _f$name,
    #owner: _f$owner,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'partStarted';
  @override
  late final ClassMapperBase superMapper =
      GenerationEventMapper.ensureInitialized();

  static PartStarted _instantiate(DecodingData data) {
    return PartStarted(
      id: data.dec(_f$id),
      index: data.dec(_f$index),
      kind: data.dec(_f$kind),
      callId: data.dec(_f$callId),
      name: data.dec(_f$name),
      owner: data.dec(_f$owner),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PartStarted fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PartStarted>(map);
  }

  static PartStarted fromJson(String json) {
    return ensureInitialized().decodeJson<PartStarted>(json);
  }
}

mixin PartStartedMappable {
  String toJson() {
    return PartStartedMapper.ensureInitialized().encodeJson<PartStarted>(
      this as PartStarted,
    );
  }

  Map<String, dynamic> toMap() {
    return PartStartedMapper.ensureInitialized().encodeMap<PartStarted>(
      this as PartStarted,
    );
  }
}

class PartDeltaMapper extends SubClassMapperBase<PartDelta> {
  PartDeltaMapper._();

  static PartDeltaMapper? _instance;
  static PartDeltaMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PartDeltaMapper._());
      GenerationEventMapper.ensureInitialized().addSubMapper(_instance!);
      ContentDeltaMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PartDelta';

  static String _$id(PartDelta v) => v.id;
  static const Field<PartDelta, String> _f$id = Field('id', _$id);
  static ContentDelta _$delta(PartDelta v) => v.delta;
  static const Field<PartDelta, ContentDelta> _f$delta = Field(
    'delta',
    _$delta,
  );

  @override
  final MappableFields<PartDelta> fields = const {#id: _f$id, #delta: _f$delta};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'partDelta';
  @override
  late final ClassMapperBase superMapper =
      GenerationEventMapper.ensureInitialized();

  static PartDelta _instantiate(DecodingData data) {
    return PartDelta(id: data.dec(_f$id), delta: data.dec(_f$delta));
  }

  @override
  final Function instantiate = _instantiate;

  static PartDelta fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PartDelta>(map);
  }

  static PartDelta fromJson(String json) {
    return ensureInitialized().decodeJson<PartDelta>(json);
  }
}

mixin PartDeltaMappable {
  String toJson() {
    return PartDeltaMapper.ensureInitialized().encodeJson<PartDelta>(
      this as PartDelta,
    );
  }

  Map<String, dynamic> toMap() {
    return PartDeltaMapper.ensureInitialized().encodeMap<PartDelta>(
      this as PartDelta,
    );
  }
}

class PartFinishedMapper extends SubClassMapperBase<PartFinished> {
  PartFinishedMapper._();

  static PartFinishedMapper? _instance;
  static PartFinishedMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PartFinishedMapper._());
      GenerationEventMapper.ensureInitialized().addSubMapper(_instance!);
      OutputPartMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'PartFinished';

  static String _$id(PartFinished v) => v.id;
  static const Field<PartFinished, String> _f$id = Field('id', _$id);
  static OutputPart _$part(PartFinished v) => v.part;
  static const Field<PartFinished, OutputPart> _f$part = Field('part', _$part);

  @override
  final MappableFields<PartFinished> fields = const {
    #id: _f$id,
    #part: _f$part,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'partFinished';
  @override
  late final ClassMapperBase superMapper =
      GenerationEventMapper.ensureInitialized();

  static PartFinished _instantiate(DecodingData data) {
    return PartFinished(id: data.dec(_f$id), part: data.dec(_f$part));
  }

  @override
  final Function instantiate = _instantiate;

  static PartFinished fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PartFinished>(map);
  }

  static PartFinished fromJson(String json) {
    return ensureInitialized().decodeJson<PartFinished>(json);
  }
}

mixin PartFinishedMappable {
  String toJson() {
    return PartFinishedMapper.ensureInitialized().encodeJson<PartFinished>(
      this as PartFinished,
    );
  }

  Map<String, dynamic> toMap() {
    return PartFinishedMapper.ensureInitialized().encodeMap<PartFinished>(
      this as PartFinished,
    );
  }
}

class UsageUpdatedMapper extends SubClassMapperBase<UsageUpdated> {
  UsageUpdatedMapper._();

  static UsageUpdatedMapper? _instance;
  static UsageUpdatedMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = UsageUpdatedMapper._());
      GenerationEventMapper.ensureInitialized().addSubMapper(_instance!);
      UsageMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'UsageUpdated';

  static Usage _$usage(UsageUpdated v) => v.usage;
  static const Field<UsageUpdated, Usage> _f$usage = Field('usage', _$usage);

  @override
  final MappableFields<UsageUpdated> fields = const {#usage: _f$usage};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'usageUpdated';
  @override
  late final ClassMapperBase superMapper =
      GenerationEventMapper.ensureInitialized();

  static UsageUpdated _instantiate(DecodingData data) {
    return UsageUpdated(usage: data.dec(_f$usage));
  }

  @override
  final Function instantiate = _instantiate;

  static UsageUpdated fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UsageUpdated>(map);
  }

  static UsageUpdated fromJson(String json) {
    return ensureInitialized().decodeJson<UsageUpdated>(json);
  }
}

mixin UsageUpdatedMappable {
  String toJson() {
    return UsageUpdatedMapper.ensureInitialized().encodeJson<UsageUpdated>(
      this as UsageUpdated,
    );
  }

  Map<String, dynamic> toMap() {
    return UsageUpdatedMapper.ensureInitialized().encodeMap<UsageUpdated>(
      this as UsageUpdated,
    );
  }
}

class ProviderEventMapper extends SubClassMapperBase<ProviderEvent> {
  ProviderEventMapper._();

  static ProviderEventMapper? _instance;
  static ProviderEventMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProviderEventMapper._());
      GenerationEventMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ProviderEvent';

  static String _$providerId(ProviderEvent v) => v.providerId;
  static const Field<ProviderEvent, String> _f$providerId = Field(
    'providerId',
    _$providerId,
  );
  static String _$api(ProviderEvent v) => v.api;
  static const Field<ProviderEvent, String> _f$api = Field('api', _$api);
  static String _$event(ProviderEvent v) => v.event;
  static const Field<ProviderEvent, String> _f$event = Field('event', _$event);
  static Object? _$data(ProviderEvent v) => v.data;
  static const Field<ProviderEvent, Object> _f$data = Field(
    'data',
    _$data,
    hook: JsonValueHook(),
  );

  @override
  final MappableFields<ProviderEvent> fields = const {
    #providerId: _f$providerId,
    #api: _f$api,
    #event: _f$event,
    #data: _f$data,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'providerEvent';
  @override
  late final ClassMapperBase superMapper =
      GenerationEventMapper.ensureInitialized();

  static ProviderEvent _instantiate(DecodingData data) {
    return ProviderEvent(
      providerId: data.dec(_f$providerId),
      api: data.dec(_f$api),
      event: data.dec(_f$event),
      data: data.dec(_f$data),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProviderEvent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProviderEvent>(map);
  }

  static ProviderEvent fromJson(String json) {
    return ensureInitialized().decodeJson<ProviderEvent>(json);
  }
}

mixin ProviderEventMappable {
  String toJson() {
    return ProviderEventMapper.ensureInitialized().encodeJson<ProviderEvent>(
      this as ProviderEvent,
    );
  }

  Map<String, dynamic> toMap() {
    return ProviderEventMapper.ensureInitialized().encodeMap<ProviderEvent>(
      this as ProviderEvent,
    );
  }
}


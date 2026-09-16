// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'chat_models.dart';

class ChatOptionsMapper extends ClassMapperBase<ChatOptions> {
  ChatOptionsMapper._();

  static ChatOptionsMapper? _instance;
  static ChatOptionsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChatOptionsMapper._());
      SettingMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ChatOptions';

  static Setting<int> _$seed(ChatOptions v) => v.seed;
  static const Field<ChatOptions, Setting<int>> _f$seed = Field(
    'seed',
    _$seed,
    opt: true,
    def: const Setting.inherit(),
  );
  static Setting<String> _$user(ChatOptions v) => v.user;
  static const Field<ChatOptions, Setting<String>> _f$user = Field(
    'user',
    _$user,
    opt: true,
    def: const Setting.inherit(),
  );
  static Setting<bool> _$parallelToolCalls(ChatOptions v) =>
      v.parallelToolCalls;
  static const Field<ChatOptions, Setting<bool>> _f$parallelToolCalls = Field(
    'parallelToolCalls',
    _$parallelToolCalls,
    opt: true,
    def: const Setting.inherit(),
  );
  static Setting<Map<String, Object?>> _$extraBody(ChatOptions v) =>
      v.extraBody;
  static const Field<ChatOptions, Setting<Map<String, Object?>>> _f$extraBody =
      Field('extraBody', _$extraBody, opt: true, def: const Setting.inherit());

  @override
  final MappableFields<ChatOptions> fields = const {
    #seed: _f$seed,
    #user: _f$user,
    #parallelToolCalls: _f$parallelToolCalls,
    #extraBody: _f$extraBody,
  };

  static ChatOptions _instantiate(DecodingData data) {
    return ChatOptions(
      seed: data.dec(_f$seed),
      user: data.dec(_f$user),
      parallelToolCalls: data.dec(_f$parallelToolCalls),
      extraBody: data.dec(_f$extraBody),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChatOptions fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChatOptions>(map);
  }

  static ChatOptions fromJson(String json) {
    return ensureInitialized().decodeJson<ChatOptions>(json);
  }
}

mixin ChatOptionsMappable {
  String toJson() {
    return ChatOptionsMapper.ensureInitialized().encodeJson<ChatOptions>(
      this as ChatOptions,
    );
  }

  Map<String, dynamic> toMap() {
    return ChatOptionsMapper.ensureInitialized().encodeMap<ChatOptions>(
      this as ChatOptions,
    );
  }
}

class NativeChatRequestMapper extends ClassMapperBase<NativeChatRequest> {
  NativeChatRequestMapper._();

  static NativeChatRequestMapper? _instance;
  static NativeChatRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = NativeChatRequestMapper._());
      NativeFieldMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'NativeChatRequest';

  static String _$model(NativeChatRequest v) => v.model;
  static const Field<NativeChatRequest, String> _f$model = Field(
    'model',
    _$model,
  );
  static List<Map<String, Object?>> _$messages(NativeChatRequest v) =>
      v.messages;
  static const Field<NativeChatRequest, List<Map<String, Object?>>>
  _f$messages = Field('messages', _$messages, hook: JsonValueHook());
  static NativeField<int>? _$maxTokens(NativeChatRequest v) => v.maxTokens;
  static const Field<NativeChatRequest, NativeField<int>> _f$maxTokens = Field(
    'maxTokens',
    _$maxTokens,
    opt: true,
  );
  static NativeField<double>? _$temperature(NativeChatRequest v) =>
      v.temperature;
  static const Field<NativeChatRequest, NativeField<double>> _f$temperature =
      Field('temperature', _$temperature, opt: true);
  static NativeField<double>? _$topP(NativeChatRequest v) => v.topP;
  static const Field<NativeChatRequest, NativeField<double>> _f$topP = Field(
    'topP',
    _$topP,
    opt: true,
  );
  static NativeField<Object?>? _$stop(NativeChatRequest v) => v.stop;
  static const Field<NativeChatRequest, NativeField<Object?>> _f$stop = Field(
    'stop',
    _$stop,
    opt: true,
  );
  static List<Map<String, Object?>>? _$tools(NativeChatRequest v) => v.tools;
  static const Field<NativeChatRequest, List<Map<String, Object?>>> _f$tools =
      Field('tools', _$tools, opt: true, hook: JsonValueHook());
  static NativeField<Object?>? _$toolChoice(NativeChatRequest v) =>
      v.toolChoice;
  static const Field<NativeChatRequest, NativeField<Object?>> _f$toolChoice =
      Field('toolChoice', _$toolChoice, opt: true);
  static Map<String, Object?>? _$responseFormat(NativeChatRequest v) =>
      v.responseFormat;
  static const Field<NativeChatRequest, Map<String, Object?>>
  _f$responseFormat = Field(
    'responseFormat',
    _$responseFormat,
    opt: true,
    hook: JsonValueHook(),
  );
  static int? _$n(NativeChatRequest v) => v.n;
  static const Field<NativeChatRequest, int> _f$n = Field('n', _$n, opt: true);
  static NativeField<int>? _$seed(NativeChatRequest v) => v.seed;
  static const Field<NativeChatRequest, NativeField<int>> _f$seed = Field(
    'seed',
    _$seed,
    opt: true,
  );
  static NativeField<String>? _$user(NativeChatRequest v) => v.user;
  static const Field<NativeChatRequest, NativeField<String>> _f$user = Field(
    'user',
    _$user,
    opt: true,
  );
  static NativeField<bool>? _$parallelToolCalls(NativeChatRequest v) =>
      v.parallelToolCalls;
  static const Field<NativeChatRequest, NativeField<bool>>
  _f$parallelToolCalls = Field(
    'parallelToolCalls',
    _$parallelToolCalls,
    opt: true,
  );
  static Map<String, Object?> _$extraBody(NativeChatRequest v) => v.extraBody;
  static const Field<NativeChatRequest, Map<String, Object?>> _f$extraBody =
      Field(
        'extraBody',
        _$extraBody,
        opt: true,
        def: const {},
        hook: JsonValueHook(),
      );

  @override
  final MappableFields<NativeChatRequest> fields = const {
    #model: _f$model,
    #messages: _f$messages,
    #maxTokens: _f$maxTokens,
    #temperature: _f$temperature,
    #topP: _f$topP,
    #stop: _f$stop,
    #tools: _f$tools,
    #toolChoice: _f$toolChoice,
    #responseFormat: _f$responseFormat,
    #n: _f$n,
    #seed: _f$seed,
    #user: _f$user,
    #parallelToolCalls: _f$parallelToolCalls,
    #extraBody: _f$extraBody,
  };

  static NativeChatRequest _instantiate(DecodingData data) {
    return NativeChatRequest(
      model: data.dec(_f$model),
      messages: data.dec(_f$messages),
      maxTokens: data.dec(_f$maxTokens),
      temperature: data.dec(_f$temperature),
      topP: data.dec(_f$topP),
      stop: data.dec(_f$stop),
      tools: data.dec(_f$tools),
      toolChoice: data.dec(_f$toolChoice),
      responseFormat: data.dec(_f$responseFormat),
      n: data.dec(_f$n),
      seed: data.dec(_f$seed),
      user: data.dec(_f$user),
      parallelToolCalls: data.dec(_f$parallelToolCalls),
      extraBody: data.dec(_f$extraBody),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static NativeChatRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NativeChatRequest>(map);
  }

  static NativeChatRequest fromJson(String json) {
    return ensureInitialized().decodeJson<NativeChatRequest>(json);
  }
}

mixin NativeChatRequestMappable {
  String toJson() {
    return NativeChatRequestMapper.ensureInitialized()
        .encodeJson<NativeChatRequest>(this as NativeChatRequest);
  }

  Map<String, dynamic> toMap() {
    return NativeChatRequestMapper.ensureInitialized()
        .encodeMap<NativeChatRequest>(this as NativeChatRequest);
  }
}

class ChatResponseMapper extends ClassMapperBase<ChatResponse> {
  ChatResponseMapper._();

  static ChatResponseMapper? _instance;
  static ChatResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChatResponseMapper._());
      ChatChoiceMapper.ensureInitialized();
      UsageMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ChatResponse';

  static String _$model(ChatResponse v) => v.model;
  static const Field<ChatResponse, String> _f$model = Field('model', _$model);
  static List<ChatChoice> _$choices(ChatResponse v) => v.choices;
  static const Field<ChatResponse, List<ChatChoice>> _f$choices = Field(
    'choices',
    _$choices,
  );
  static String? _$id(ChatResponse v) => v.id;
  static const Field<ChatResponse, String> _f$id = Field('id', _$id, opt: true);
  static Usage? _$usage(ChatResponse v) => v.usage;
  static const Field<ChatResponse, Usage> _f$usage = Field(
    'usage',
    _$usage,
    opt: true,
  );

  @override
  final MappableFields<ChatResponse> fields = const {
    #model: _f$model,
    #choices: _f$choices,
    #id: _f$id,
    #usage: _f$usage,
  };

  static ChatResponse _instantiate(DecodingData data) {
    return ChatResponse(
      model: data.dec(_f$model),
      choices: data.dec(_f$choices),
      id: data.dec(_f$id),
      usage: data.dec(_f$usage),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChatResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChatResponse>(map);
  }

  static ChatResponse fromJson(String json) {
    return ensureInitialized().decodeJson<ChatResponse>(json);
  }
}

mixin ChatResponseMappable {
  String toJson() {
    return ChatResponseMapper.ensureInitialized().encodeJson<ChatResponse>(
      this as ChatResponse,
    );
  }

  Map<String, dynamic> toMap() {
    return ChatResponseMapper.ensureInitialized().encodeMap<ChatResponse>(
      this as ChatResponse,
    );
  }
}

class ChatChoiceMapper extends ClassMapperBase<ChatChoice> {
  ChatChoiceMapper._();

  static ChatChoiceMapper? _instance;
  static ChatChoiceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChatChoiceMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ChatChoice';

  static int _$index(ChatChoice v) => v.index;
  static const Field<ChatChoice, int> _f$index = Field('index', _$index);
  static Map<String, Object?> _$message(ChatChoice v) => v.message;
  static const Field<ChatChoice, Map<String, Object?>> _f$message = Field(
    'message',
    _$message,
    hook: JsonValueHook(),
  );
  static String? _$finishReason(ChatChoice v) => v.finishReason;
  static const Field<ChatChoice, String> _f$finishReason = Field(
    'finishReason',
    _$finishReason,
    opt: true,
  );

  @override
  final MappableFields<ChatChoice> fields = const {
    #index: _f$index,
    #message: _f$message,
    #finishReason: _f$finishReason,
  };

  static ChatChoice _instantiate(DecodingData data) {
    return ChatChoice(
      index: data.dec(_f$index),
      message: data.dec(_f$message),
      finishReason: data.dec(_f$finishReason),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChatChoice fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChatChoice>(map);
  }

  static ChatChoice fromJson(String json) {
    return ensureInitialized().decodeJson<ChatChoice>(json);
  }
}

mixin ChatChoiceMappable {
  String toJson() {
    return ChatChoiceMapper.ensureInitialized().encodeJson<ChatChoice>(
      this as ChatChoice,
    );
  }

  Map<String, dynamic> toMap() {
    return ChatChoiceMapper.ensureInitialized().encodeMap<ChatChoice>(
      this as ChatChoice,
    );
  }
}


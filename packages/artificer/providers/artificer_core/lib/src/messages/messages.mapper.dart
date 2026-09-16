// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'messages.dart';

class ToolExecutionOwnerMapper extends EnumMapper<ToolExecutionOwner> {
  ToolExecutionOwnerMapper._();

  static ToolExecutionOwnerMapper? _instance;
  static ToolExecutionOwnerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolExecutionOwnerMapper._());
    }
    return _instance!;
  }

  static ToolExecutionOwner fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ToolExecutionOwner decode(dynamic value) {
    switch (value) {
      case r'application':
        return ToolExecutionOwner.application;
      case r'provider':
        return ToolExecutionOwner.provider;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ToolExecutionOwner self) {
    switch (self) {
      case ToolExecutionOwner.application:
        return r'application';
      case ToolExecutionOwner.provider:
        return r'provider';
    }
  }
}

extension ToolExecutionOwnerMapperExtension on ToolExecutionOwner {
  String toValue() {
    ToolExecutionOwnerMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ToolExecutionOwner>(this) as String;
  }
}

class ToolStatusMapper extends EnumMapper<ToolStatus> {
  ToolStatusMapper._();

  static ToolStatusMapper? _instance;
  static ToolStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolStatusMapper._());
    }
    return _instance!;
  }

  static ToolStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ToolStatus decode(dynamic value) {
    switch (value) {
      case r'pending':
        return ToolStatus.pending;
      case r'running':
        return ToolStatus.running;
      case r'completed':
        return ToolStatus.completed;
      case r'failed':
        return ToolStatus.failed;
      case r'unknown':
        return ToolStatus.unknown;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ToolStatus self) {
    switch (self) {
      case ToolStatus.pending:
        return r'pending';
      case ToolStatus.running:
        return r'running';
      case ToolStatus.completed:
        return r'completed';
      case ToolStatus.failed:
        return r'failed';
      case ToolStatus.unknown:
        return r'unknown';
    }
  }
}

extension ToolStatusMapperExtension on ToolStatus {
  String toValue() {
    ToolStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ToolStatus>(this) as String;
  }
}

class MessageMapper extends ClassMapperBase<Message> {
  MessageMapper._();

  static MessageMapper? _instance;
  static MessageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MessageMapper._());
      UserMessageMapper.ensureInitialized();
      AssistantMessageMapper.ensureInitialized();
      ToolMessageMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Message';

  static int _$schemaVersion(Message v) => v.schemaVersion;
  static const Field<Message, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<Message> fields = const {
    #schemaVersion: _f$schemaVersion,
  };

  static Message _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'Message',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Message fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Message>(map);
  }

  static Message fromJson(String json) {
    return ensureInitialized().decodeJson<Message>(json);
  }
}

mixin MessageMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class UserMessageMapper extends SubClassMapperBase<UserMessage> {
  UserMessageMapper._();

  static UserMessageMapper? _instance;
  static UserMessageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = UserMessageMapper._());
      MessageMapper.ensureInitialized().addSubMapper(_instance!);
      InputPartMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'UserMessage';

  static List<InputPart> _$parts(UserMessage v) => v.parts;
  static const Field<UserMessage, List<InputPart>> _f$parts = Field(
    'parts',
    _$parts,
  );
  static int _$schemaVersion(UserMessage v) => v.schemaVersion;
  static const Field<UserMessage, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<UserMessage> fields = const {
    #parts: _f$parts,
    #schemaVersion: _f$schemaVersion,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'user';
  @override
  late final ClassMapperBase superMapper = MessageMapper.ensureInitialized();

  static UserMessage _instantiate(DecodingData data) {
    return UserMessage(
      data.dec(_f$parts),
      schemaVersion: data.dec(_f$schemaVersion),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static UserMessage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<UserMessage>(map);
  }

  static UserMessage fromJson(String json) {
    return ensureInitialized().decodeJson<UserMessage>(json);
  }
}

mixin UserMessageMappable {
  String toJson() {
    return UserMessageMapper.ensureInitialized().encodeJson<UserMessage>(
      this as UserMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return UserMessageMapper.ensureInitialized().encodeMap<UserMessage>(
      this as UserMessage,
    );
  }
}

class InputPartMapper extends ClassMapperBase<InputPart> {
  InputPartMapper._();

  static InputPartMapper? _instance;
  static InputPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = InputPartMapper._());
      TextInputPartMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'InputPart';

  @override
  final MappableFields<InputPart> fields = const {};

  static InputPart _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'InputPart',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static InputPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<InputPart>(map);
  }

  static InputPart fromJson(String json) {
    return ensureInitialized().decodeJson<InputPart>(json);
  }
}

mixin InputPartMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class AssistantMessageMapper extends SubClassMapperBase<AssistantMessage> {
  AssistantMessageMapper._();

  static AssistantMessageMapper? _instance;
  static AssistantMessageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AssistantMessageMapper._());
      MessageMapper.ensureInitialized().addSubMapper(_instance!);
      OutputPartMapper.ensureInitialized();
      ProviderReplayMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AssistantMessage';

  static List<OutputPart> _$parts(AssistantMessage v) => v.parts;
  static const Field<AssistantMessage, List<OutputPart>> _f$parts = Field(
    'parts',
    _$parts,
  );
  static ProviderReplay? _$replay(AssistantMessage v) => v.replay;
  static const Field<AssistantMessage, ProviderReplay> _f$replay = Field(
    'replay',
    _$replay,
    opt: true,
  );
  static int _$schemaVersion(AssistantMessage v) => v.schemaVersion;
  static const Field<AssistantMessage, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<AssistantMessage> fields = const {
    #parts: _f$parts,
    #replay: _f$replay,
    #schemaVersion: _f$schemaVersion,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'assistant';
  @override
  late final ClassMapperBase superMapper = MessageMapper.ensureInitialized();

  static AssistantMessage _instantiate(DecodingData data) {
    return AssistantMessage(
      data.dec(_f$parts),
      replay: data.dec(_f$replay),
      schemaVersion: data.dec(_f$schemaVersion),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AssistantMessage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AssistantMessage>(map);
  }

  static AssistantMessage fromJson(String json) {
    return ensureInitialized().decodeJson<AssistantMessage>(json);
  }
}

mixin AssistantMessageMappable {
  String toJson() {
    return AssistantMessageMapper.ensureInitialized()
        .encodeJson<AssistantMessage>(this as AssistantMessage);
  }

  Map<String, dynamic> toMap() {
    return AssistantMessageMapper.ensureInitialized()
        .encodeMap<AssistantMessage>(this as AssistantMessage);
  }
}

class OutputPartMapper extends ClassMapperBase<OutputPart> {
  OutputPartMapper._();

  static OutputPartMapper? _instance;
  static OutputPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OutputPartMapper._());
      TextOutputPartMapper.ensureInitialized();
      ReasoningOutputPartMapper.ensureInitialized();
      RefusalOutputPartMapper.ensureInitialized();
      OpaqueOutputPartMapper.ensureInitialized();
      ToolCallPartMapper.ensureInitialized();
      ProviderToolPartMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'OutputPart';

  @override
  final MappableFields<OutputPart> fields = const {};

  static OutputPart _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'OutputPart',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OutputPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OutputPart>(map);
  }

  static OutputPart fromJson(String json) {
    return ensureInitialized().decodeJson<OutputPart>(json);
  }
}

mixin OutputPartMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class ProviderReplayMapper extends ClassMapperBase<ProviderReplay> {
  ProviderReplayMapper._();

  static ProviderReplayMapper? _instance;
  static ProviderReplayMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProviderReplayMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProviderReplay';

  static String _$providerId(ProviderReplay v) => v.providerId;
  static const Field<ProviderReplay, String> _f$providerId = Field(
    'providerId',
    _$providerId,
  );
  static String _$api(ProviderReplay v) => v.api;
  static const Field<ProviderReplay, String> _f$api = Field('api', _$api);
  static String _$modelId(ProviderReplay v) => v.modelId;
  static const Field<ProviderReplay, String> _f$modelId = Field(
    'modelId',
    _$modelId,
  );
  static List<Object?> _$items(ProviderReplay v) => v.items;
  static const Field<ProviderReplay, List<Object?>> _f$items = Field(
    'items',
    _$items,
  );
  static int _$schemaVersion(ProviderReplay v) => v.schemaVersion;
  static const Field<ProviderReplay, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<ProviderReplay> fields = const {
    #providerId: _f$providerId,
    #api: _f$api,
    #modelId: _f$modelId,
    #items: _f$items,
    #schemaVersion: _f$schemaVersion,
  };

  static ProviderReplay _instantiate(DecodingData data) {
    return ProviderReplay(
      providerId: data.dec(_f$providerId),
      api: data.dec(_f$api),
      modelId: data.dec(_f$modelId),
      items: data.dec(_f$items),
      schemaVersion: data.dec(_f$schemaVersion),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProviderReplay fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProviderReplay>(map);
  }

  static ProviderReplay fromJson(String json) {
    return ensureInitialized().decodeJson<ProviderReplay>(json);
  }
}

mixin ProviderReplayMappable {
  String toJson() {
    return ProviderReplayMapper.ensureInitialized().encodeJson<ProviderReplay>(
      this as ProviderReplay,
    );
  }

  Map<String, dynamic> toMap() {
    return ProviderReplayMapper.ensureInitialized().encodeMap<ProviderReplay>(
      this as ProviderReplay,
    );
  }
}

class TextInputPartMapper extends SubClassMapperBase<TextInputPart> {
  TextInputPartMapper._();

  static TextInputPartMapper? _instance;
  static TextInputPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TextInputPartMapper._());
      InputPartMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'TextInputPart';

  static String _$text(TextInputPart v) => v.text;
  static const Field<TextInputPart, String> _f$text = Field('text', _$text);

  @override
  final MappableFields<TextInputPart> fields = const {#text: _f$text};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'text';
  @override
  late final ClassMapperBase superMapper = InputPartMapper.ensureInitialized();

  static TextInputPart _instantiate(DecodingData data) {
    return TextInputPart(data.dec(_f$text));
  }

  @override
  final Function instantiate = _instantiate;

  static TextInputPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TextInputPart>(map);
  }

  static TextInputPart fromJson(String json) {
    return ensureInitialized().decodeJson<TextInputPart>(json);
  }
}

mixin TextInputPartMappable {
  String toJson() {
    return TextInputPartMapper.ensureInitialized().encodeJson<TextInputPart>(
      this as TextInputPart,
    );
  }

  Map<String, dynamic> toMap() {
    return TextInputPartMapper.ensureInitialized().encodeMap<TextInputPart>(
      this as TextInputPart,
    );
  }
}

class TextOutputPartMapper extends SubClassMapperBase<TextOutputPart> {
  TextOutputPartMapper._();

  static TextOutputPartMapper? _instance;
  static TextOutputPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TextOutputPartMapper._());
      OutputPartMapper.ensureInitialized().addSubMapper(_instance!);
      CitationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TextOutputPart';

  static String _$text(TextOutputPart v) => v.text;
  static const Field<TextOutputPart, String> _f$text = Field('text', _$text);
  static List<Citation> _$citations(TextOutputPart v) => v.citations;
  static const Field<TextOutputPart, List<Citation>> _f$citations = Field(
    'citations',
    _$citations,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<TextOutputPart> fields = const {
    #text: _f$text,
    #citations: _f$citations,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'text';
  @override
  late final ClassMapperBase superMapper = OutputPartMapper.ensureInitialized();

  static TextOutputPart _instantiate(DecodingData data) {
    return TextOutputPart(data.dec(_f$text), citations: data.dec(_f$citations));
  }

  @override
  final Function instantiate = _instantiate;

  static TextOutputPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TextOutputPart>(map);
  }

  static TextOutputPart fromJson(String json) {
    return ensureInitialized().decodeJson<TextOutputPart>(json);
  }
}

mixin TextOutputPartMappable {
  String toJson() {
    return TextOutputPartMapper.ensureInitialized().encodeJson<TextOutputPart>(
      this as TextOutputPart,
    );
  }

  Map<String, dynamic> toMap() {
    return TextOutputPartMapper.ensureInitialized().encodeMap<TextOutputPart>(
      this as TextOutputPart,
    );
  }
}

class CitationMapper extends ClassMapperBase<Citation> {
  CitationMapper._();

  static CitationMapper? _instance;
  static CitationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CitationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'Citation';

  static Object? _$data(Citation v) => v.data;
  static const Field<Citation, Object> _f$data = Field('data', _$data);
  static String? _$url(Citation v) => v.url;
  static const Field<Citation, String> _f$url = Field('url', _$url, opt: true);
  static String? _$title(Citation v) => v.title;
  static const Field<Citation, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
  );
  static int? _$start(Citation v) => v.start;
  static const Field<Citation, int> _f$start = Field(
    'start',
    _$start,
    opt: true,
  );
  static int? _$end(Citation v) => v.end;
  static const Field<Citation, int> _f$end = Field('end', _$end, opt: true);

  @override
  final MappableFields<Citation> fields = const {
    #data: _f$data,
    #url: _f$url,
    #title: _f$title,
    #start: _f$start,
    #end: _f$end,
  };

  static Citation _instantiate(DecodingData data) {
    return Citation(
      data: data.dec(_f$data),
      url: data.dec(_f$url),
      title: data.dec(_f$title),
      start: data.dec(_f$start),
      end: data.dec(_f$end),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Citation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Citation>(map);
  }

  static Citation fromJson(String json) {
    return ensureInitialized().decodeJson<Citation>(json);
  }
}

mixin CitationMappable {
  String toJson() {
    return CitationMapper.ensureInitialized().encodeJson<Citation>(
      this as Citation,
    );
  }

  Map<String, dynamic> toMap() {
    return CitationMapper.ensureInitialized().encodeMap<Citation>(
      this as Citation,
    );
  }
}

class ToolMessageMapper extends SubClassMapperBase<ToolMessage> {
  ToolMessageMapper._();

  static ToolMessageMapper? _instance;
  static ToolMessageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolMessageMapper._());
      MessageMapper.ensureInitialized().addSubMapper(_instance!);
      ToolResultMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolMessage';

  static List<ToolResult> _$results(ToolMessage v) => v.results;
  static const Field<ToolMessage, List<ToolResult>> _f$results = Field(
    'results',
    _$results,
  );
  static int _$schemaVersion(ToolMessage v) => v.schemaVersion;
  static const Field<ToolMessage, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<ToolMessage> fields = const {
    #results: _f$results,
    #schemaVersion: _f$schemaVersion,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'tool';
  @override
  late final ClassMapperBase superMapper = MessageMapper.ensureInitialized();

  static ToolMessage _instantiate(DecodingData data) {
    return ToolMessage(
      data.dec(_f$results),
      schemaVersion: data.dec(_f$schemaVersion),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolMessage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolMessage>(map);
  }

  static ToolMessage fromJson(String json) {
    return ensureInitialized().decodeJson<ToolMessage>(json);
  }
}

mixin ToolMessageMappable {
  String toJson() {
    return ToolMessageMapper.ensureInitialized().encodeJson<ToolMessage>(
      this as ToolMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return ToolMessageMapper.ensureInitialized().encodeMap<ToolMessage>(
      this as ToolMessage,
    );
  }
}

class ReasoningOutputPartMapper
    extends SubClassMapperBase<ReasoningOutputPart> {
  ReasoningOutputPartMapper._();

  static ReasoningOutputPartMapper? _instance;
  static ReasoningOutputPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ReasoningOutputPartMapper._());
      OutputPartMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ReasoningOutputPart';

  static String _$summary(ReasoningOutputPart v) => v.summary;
  static const Field<ReasoningOutputPart, String> _f$summary = Field(
    'summary',
    _$summary,
  );

  @override
  final MappableFields<ReasoningOutputPart> fields = const {
    #summary: _f$summary,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'reasoning';
  @override
  late final ClassMapperBase superMapper = OutputPartMapper.ensureInitialized();

  static ReasoningOutputPart _instantiate(DecodingData data) {
    return ReasoningOutputPart(summary: data.dec(_f$summary));
  }

  @override
  final Function instantiate = _instantiate;

  static ReasoningOutputPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ReasoningOutputPart>(map);
  }

  static ReasoningOutputPart fromJson(String json) {
    return ensureInitialized().decodeJson<ReasoningOutputPart>(json);
  }
}

mixin ReasoningOutputPartMappable {
  String toJson() {
    return ReasoningOutputPartMapper.ensureInitialized()
        .encodeJson<ReasoningOutputPart>(this as ReasoningOutputPart);
  }

  Map<String, dynamic> toMap() {
    return ReasoningOutputPartMapper.ensureInitialized()
        .encodeMap<ReasoningOutputPart>(this as ReasoningOutputPart);
  }
}

class RefusalOutputPartMapper extends SubClassMapperBase<RefusalOutputPart> {
  RefusalOutputPartMapper._();

  static RefusalOutputPartMapper? _instance;
  static RefusalOutputPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RefusalOutputPartMapper._());
      OutputPartMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'RefusalOutputPart';

  static String _$text(RefusalOutputPart v) => v.text;
  static const Field<RefusalOutputPart, String> _f$text = Field('text', _$text);

  @override
  final MappableFields<RefusalOutputPart> fields = const {#text: _f$text};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'refusal';
  @override
  late final ClassMapperBase superMapper = OutputPartMapper.ensureInitialized();

  static RefusalOutputPart _instantiate(DecodingData data) {
    return RefusalOutputPart(text: data.dec(_f$text));
  }

  @override
  final Function instantiate = _instantiate;

  static RefusalOutputPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RefusalOutputPart>(map);
  }

  static RefusalOutputPart fromJson(String json) {
    return ensureInitialized().decodeJson<RefusalOutputPart>(json);
  }
}

mixin RefusalOutputPartMappable {
  String toJson() {
    return RefusalOutputPartMapper.ensureInitialized()
        .encodeJson<RefusalOutputPart>(this as RefusalOutputPart);
  }

  Map<String, dynamic> toMap() {
    return RefusalOutputPartMapper.ensureInitialized()
        .encodeMap<RefusalOutputPart>(this as RefusalOutputPart);
  }
}

class OpaqueOutputPartMapper extends SubClassMapperBase<OpaqueOutputPart> {
  OpaqueOutputPartMapper._();

  static OpaqueOutputPartMapper? _instance;
  static OpaqueOutputPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OpaqueOutputPartMapper._());
      OutputPartMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'OpaqueOutputPart';

  static String _$providerId(OpaqueOutputPart v) => v.providerId;
  static const Field<OpaqueOutputPart, String> _f$providerId = Field(
    'providerId',
    _$providerId,
  );
  static String _$api(OpaqueOutputPart v) => v.api;
  static const Field<OpaqueOutputPart, String> _f$api = Field('api', _$api);
  static Object? _$data(OpaqueOutputPart v) => v.data;
  static const Field<OpaqueOutputPart, Object> _f$data = Field('data', _$data);

  @override
  final MappableFields<OpaqueOutputPart> fields = const {
    #providerId: _f$providerId,
    #api: _f$api,
    #data: _f$data,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'opaque';
  @override
  late final ClassMapperBase superMapper = OutputPartMapper.ensureInitialized();

  static OpaqueOutputPart _instantiate(DecodingData data) {
    return OpaqueOutputPart(
      providerId: data.dec(_f$providerId),
      api: data.dec(_f$api),
      data: data.dec(_f$data),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OpaqueOutputPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OpaqueOutputPart>(map);
  }

  static OpaqueOutputPart fromJson(String json) {
    return ensureInitialized().decodeJson<OpaqueOutputPart>(json);
  }
}

mixin OpaqueOutputPartMappable {
  String toJson() {
    return OpaqueOutputPartMapper.ensureInitialized()
        .encodeJson<OpaqueOutputPart>(this as OpaqueOutputPart);
  }

  Map<String, dynamic> toMap() {
    return OpaqueOutputPartMapper.ensureInitialized()
        .encodeMap<OpaqueOutputPart>(this as OpaqueOutputPart);
  }
}

class ToolCallPartMapper extends SubClassMapperBase<ToolCallPart> {
  ToolCallPartMapper._();

  static ToolCallPartMapper? _instance;
  static ToolCallPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolCallPartMapper._());
      OutputPartMapper.ensureInitialized().addSubMapper(_instance!);
      ToolArgumentsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolCallPart';

  static String _$callId(ToolCallPart v) => v.callId;
  static const Field<ToolCallPart, String> _f$callId = Field(
    'callId',
    _$callId,
  );
  static String _$name(ToolCallPart v) => v.name;
  static const Field<ToolCallPart, String> _f$name = Field('name', _$name);
  static ToolArguments _$arguments(ToolCallPart v) => v.arguments;
  static const Field<ToolCallPart, ToolArguments> _f$arguments = Field(
    'arguments',
    _$arguments,
  );

  @override
  final MappableFields<ToolCallPart> fields = const {
    #callId: _f$callId,
    #name: _f$name,
    #arguments: _f$arguments,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'toolCall';
  @override
  late final ClassMapperBase superMapper = OutputPartMapper.ensureInitialized();

  static ToolCallPart _instantiate(DecodingData data) {
    return ToolCallPart(
      callId: data.dec(_f$callId),
      name: data.dec(_f$name),
      arguments: data.dec(_f$arguments),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolCallPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolCallPart>(map);
  }

  static ToolCallPart fromJson(String json) {
    return ensureInitialized().decodeJson<ToolCallPart>(json);
  }
}

mixin ToolCallPartMappable {
  String toJson() {
    return ToolCallPartMapper.ensureInitialized().encodeJson<ToolCallPart>(
      this as ToolCallPart,
    );
  }

  Map<String, dynamic> toMap() {
    return ToolCallPartMapper.ensureInitialized().encodeMap<ToolCallPart>(
      this as ToolCallPart,
    );
  }
}

class ProviderToolPartMapper extends SubClassMapperBase<ProviderToolPart> {
  ProviderToolPartMapper._();

  static ProviderToolPartMapper? _instance;
  static ProviderToolPartMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProviderToolPartMapper._());
      OutputPartMapper.ensureInitialized().addSubMapper(_instance!);
      ToolExecutionOwnerMapper.ensureInitialized();
      ToolStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProviderToolPart';

  static String _$id(ProviderToolPart v) => v.id;
  static const Field<ProviderToolPart, String> _f$id = Field('id', _$id);
  static String _$name(ProviderToolPart v) => v.name;
  static const Field<ProviderToolPart, String> _f$name = Field('name', _$name);
  static ToolExecutionOwner _$owner(ProviderToolPart v) => v.owner;
  static const Field<ProviderToolPart, ToolExecutionOwner> _f$owner = Field(
    'owner',
    _$owner,
  );
  static Object? _$native(ProviderToolPart v) => v.native;
  static const Field<ProviderToolPart, Object> _f$native = Field(
    'native',
    _$native,
  );
  static ToolStatus _$status(ProviderToolPart v) => v.status;
  static const Field<ProviderToolPart, ToolStatus> _f$status = Field(
    'status',
    _$status,
    opt: true,
    def: ToolStatus.unknown,
  );

  @override
  final MappableFields<ProviderToolPart> fields = const {
    #id: _f$id,
    #name: _f$name,
    #owner: _f$owner,
    #native: _f$native,
    #status: _f$status,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'providerTool';
  @override
  late final ClassMapperBase superMapper = OutputPartMapper.ensureInitialized();

  static ProviderToolPart _instantiate(DecodingData data) {
    return ProviderToolPart(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      owner: data.dec(_f$owner),
      native: data.dec(_f$native),
      status: data.dec(_f$status),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProviderToolPart fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProviderToolPart>(map);
  }

  static ProviderToolPart fromJson(String json) {
    return ensureInitialized().decodeJson<ProviderToolPart>(json);
  }
}

mixin ProviderToolPartMappable {
  String toJson() {
    return ProviderToolPartMapper.ensureInitialized()
        .encodeJson<ProviderToolPart>(this as ProviderToolPart);
  }

  Map<String, dynamic> toMap() {
    return ProviderToolPartMapper.ensureInitialized()
        .encodeMap<ProviderToolPart>(this as ProviderToolPart);
  }
}


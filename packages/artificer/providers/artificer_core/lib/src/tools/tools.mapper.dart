// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'tools.dart';

class FunctionToolMapper extends ClassMapperBase<FunctionTool> {
  FunctionToolMapper._();

  static FunctionToolMapper? _instance;
  static FunctionToolMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FunctionToolMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FunctionTool';

  static String _$name(FunctionTool v) => v.name;
  static const Field<FunctionTool, String> _f$name = Field('name', _$name);
  static Map<String, Object?> _$inputSchema(FunctionTool v) => v.inputSchema;
  static const Field<FunctionTool, Map<String, Object?>> _f$inputSchema = Field(
    'inputSchema',
    _$inputSchema,
    hook: JsonValueHook(),
  );
  static String? _$description(FunctionTool v) => v.description;
  static const Field<FunctionTool, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
  );

  @override
  final MappableFields<FunctionTool> fields = const {
    #name: _f$name,
    #inputSchema: _f$inputSchema,
    #description: _f$description,
  };

  static FunctionTool _instantiate(DecodingData data) {
    return FunctionTool(
      name: data.dec(_f$name),
      inputSchema: data.dec(_f$inputSchema),
      description: data.dec(_f$description),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FunctionTool fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FunctionTool>(map);
  }

  static FunctionTool fromJson(String json) {
    return ensureInitialized().decodeJson<FunctionTool>(json);
  }
}

mixin FunctionToolMappable {
  String toJson() {
    return FunctionToolMapper.ensureInitialized().encodeJson<FunctionTool>(
      this as FunctionTool,
    );
  }

  Map<String, dynamic> toMap() {
    return FunctionToolMapper.ensureInitialized().encodeMap<FunctionTool>(
      this as FunctionTool,
    );
  }
}

class ToolChoiceMapper extends ClassMapperBase<ToolChoice> {
  ToolChoiceMapper._();

  static ToolChoiceMapper? _instance;
  static ToolChoiceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolChoiceMapper._());
      AutoToolChoiceMapper.ensureInitialized();
      NoToolChoiceMapper.ensureInitialized();
      RequiredToolChoiceMapper.ensureInitialized();
      NamedToolChoiceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolChoice';

  @override
  final MappableFields<ToolChoice> fields = const {};

  static ToolChoice _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'ToolChoice',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolChoice fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolChoice>(map);
  }

  static ToolChoice fromJson(String json) {
    return ensureInitialized().decodeJson<ToolChoice>(json);
  }
}

mixin ToolChoiceMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class AutoToolChoiceMapper extends SubClassMapperBase<AutoToolChoice> {
  AutoToolChoiceMapper._();

  static AutoToolChoiceMapper? _instance;
  static AutoToolChoiceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AutoToolChoiceMapper._());
      ToolChoiceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'AutoToolChoice';

  @override
  final MappableFields<AutoToolChoice> fields = const {};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'auto';
  @override
  late final ClassMapperBase superMapper = ToolChoiceMapper.ensureInitialized();

  static AutoToolChoice _instantiate(DecodingData data) {
    return AutoToolChoice();
  }

  @override
  final Function instantiate = _instantiate;

  static AutoToolChoice fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AutoToolChoice>(map);
  }

  static AutoToolChoice fromJson(String json) {
    return ensureInitialized().decodeJson<AutoToolChoice>(json);
  }
}

mixin AutoToolChoiceMappable {
  String toJson() {
    return AutoToolChoiceMapper.ensureInitialized().encodeJson<AutoToolChoice>(
      this as AutoToolChoice,
    );
  }

  Map<String, dynamic> toMap() {
    return AutoToolChoiceMapper.ensureInitialized().encodeMap<AutoToolChoice>(
      this as AutoToolChoice,
    );
  }
}

class NoToolChoiceMapper extends SubClassMapperBase<NoToolChoice> {
  NoToolChoiceMapper._();

  static NoToolChoiceMapper? _instance;
  static NoToolChoiceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = NoToolChoiceMapper._());
      ToolChoiceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'NoToolChoice';

  @override
  final MappableFields<NoToolChoice> fields = const {};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'none';
  @override
  late final ClassMapperBase superMapper = ToolChoiceMapper.ensureInitialized();

  static NoToolChoice _instantiate(DecodingData data) {
    return NoToolChoice();
  }

  @override
  final Function instantiate = _instantiate;

  static NoToolChoice fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NoToolChoice>(map);
  }

  static NoToolChoice fromJson(String json) {
    return ensureInitialized().decodeJson<NoToolChoice>(json);
  }
}

mixin NoToolChoiceMappable {
  String toJson() {
    return NoToolChoiceMapper.ensureInitialized().encodeJson<NoToolChoice>(
      this as NoToolChoice,
    );
  }

  Map<String, dynamic> toMap() {
    return NoToolChoiceMapper.ensureInitialized().encodeMap<NoToolChoice>(
      this as NoToolChoice,
    );
  }
}

class RequiredToolChoiceMapper extends SubClassMapperBase<RequiredToolChoice> {
  RequiredToolChoiceMapper._();

  static RequiredToolChoiceMapper? _instance;
  static RequiredToolChoiceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RequiredToolChoiceMapper._());
      ToolChoiceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'RequiredToolChoice';

  @override
  final MappableFields<RequiredToolChoice> fields = const {};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'required';
  @override
  late final ClassMapperBase superMapper = ToolChoiceMapper.ensureInitialized();

  static RequiredToolChoice _instantiate(DecodingData data) {
    return RequiredToolChoice();
  }

  @override
  final Function instantiate = _instantiate;

  static RequiredToolChoice fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RequiredToolChoice>(map);
  }

  static RequiredToolChoice fromJson(String json) {
    return ensureInitialized().decodeJson<RequiredToolChoice>(json);
  }
}

mixin RequiredToolChoiceMappable {
  String toJson() {
    return RequiredToolChoiceMapper.ensureInitialized()
        .encodeJson<RequiredToolChoice>(this as RequiredToolChoice);
  }

  Map<String, dynamic> toMap() {
    return RequiredToolChoiceMapper.ensureInitialized()
        .encodeMap<RequiredToolChoice>(this as RequiredToolChoice);
  }
}

class NamedToolChoiceMapper extends SubClassMapperBase<NamedToolChoice> {
  NamedToolChoiceMapper._();

  static NamedToolChoiceMapper? _instance;
  static NamedToolChoiceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = NamedToolChoiceMapper._());
      ToolChoiceMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'NamedToolChoice';

  static String _$name(NamedToolChoice v) => v.name;
  static const Field<NamedToolChoice, String> _f$name = Field('name', _$name);

  @override
  final MappableFields<NamedToolChoice> fields = const {#name: _f$name};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'named';
  @override
  late final ClassMapperBase superMapper = ToolChoiceMapper.ensureInitialized();

  static NamedToolChoice _instantiate(DecodingData data) {
    return NamedToolChoice(name: data.dec(_f$name));
  }

  @override
  final Function instantiate = _instantiate;

  static NamedToolChoice fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NamedToolChoice>(map);
  }

  static NamedToolChoice fromJson(String json) {
    return ensureInitialized().decodeJson<NamedToolChoice>(json);
  }
}

mixin NamedToolChoiceMappable {
  String toJson() {
    return NamedToolChoiceMapper.ensureInitialized()
        .encodeJson<NamedToolChoice>(this as NamedToolChoice);
  }

  Map<String, dynamic> toMap() {
    return NamedToolChoiceMapper.ensureInitialized().encodeMap<NamedToolChoice>(
      this as NamedToolChoice,
    );
  }
}

class OutputFormatMapper extends ClassMapperBase<OutputFormat> {
  OutputFormatMapper._();

  static OutputFormatMapper? _instance;
  static OutputFormatMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OutputFormatMapper._());
      TextOutputMapper.ensureInitialized();
      JsonObjectOutputMapper.ensureInitialized();
      JsonSchemaOutputMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'OutputFormat';

  @override
  final MappableFields<OutputFormat> fields = const {};

  static OutputFormat _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'OutputFormat',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OutputFormat fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OutputFormat>(map);
  }

  static OutputFormat fromJson(String json) {
    return ensureInitialized().decodeJson<OutputFormat>(json);
  }
}

mixin OutputFormatMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class TextOutputMapper extends SubClassMapperBase<TextOutput> {
  TextOutputMapper._();

  static TextOutputMapper? _instance;
  static TextOutputMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TextOutputMapper._());
      OutputFormatMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'TextOutput';

  @override
  final MappableFields<TextOutput> fields = const {};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'text';
  @override
  late final ClassMapperBase superMapper =
      OutputFormatMapper.ensureInitialized();

  static TextOutput _instantiate(DecodingData data) {
    return TextOutput();
  }

  @override
  final Function instantiate = _instantiate;

  static TextOutput fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TextOutput>(map);
  }

  static TextOutput fromJson(String json) {
    return ensureInitialized().decodeJson<TextOutput>(json);
  }
}

mixin TextOutputMappable {
  String toJson() {
    return TextOutputMapper.ensureInitialized().encodeJson<TextOutput>(
      this as TextOutput,
    );
  }

  Map<String, dynamic> toMap() {
    return TextOutputMapper.ensureInitialized().encodeMap<TextOutput>(
      this as TextOutput,
    );
  }
}

class JsonObjectOutputMapper extends SubClassMapperBase<JsonObjectOutput> {
  JsonObjectOutputMapper._();

  static JsonObjectOutputMapper? _instance;
  static JsonObjectOutputMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = JsonObjectOutputMapper._());
      OutputFormatMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'JsonObjectOutput';

  @override
  final MappableFields<JsonObjectOutput> fields = const {};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'jsonObject';
  @override
  late final ClassMapperBase superMapper =
      OutputFormatMapper.ensureInitialized();

  static JsonObjectOutput _instantiate(DecodingData data) {
    return JsonObjectOutput();
  }

  @override
  final Function instantiate = _instantiate;

  static JsonObjectOutput fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<JsonObjectOutput>(map);
  }

  static JsonObjectOutput fromJson(String json) {
    return ensureInitialized().decodeJson<JsonObjectOutput>(json);
  }
}

mixin JsonObjectOutputMappable {
  String toJson() {
    return JsonObjectOutputMapper.ensureInitialized()
        .encodeJson<JsonObjectOutput>(this as JsonObjectOutput);
  }

  Map<String, dynamic> toMap() {
    return JsonObjectOutputMapper.ensureInitialized()
        .encodeMap<JsonObjectOutput>(this as JsonObjectOutput);
  }
}

class JsonSchemaOutputMapper extends SubClassMapperBase<JsonSchemaOutput> {
  JsonSchemaOutputMapper._();

  static JsonSchemaOutputMapper? _instance;
  static JsonSchemaOutputMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = JsonSchemaOutputMapper._());
      OutputFormatMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'JsonSchemaOutput';

  static String _$name(JsonSchemaOutput v) => v.name;
  static const Field<JsonSchemaOutput, String> _f$name = Field('name', _$name);
  static Map<String, Object?> _$schema(JsonSchemaOutput v) => v.schema;
  static const Field<JsonSchemaOutput, Map<String, Object?>> _f$schema = Field(
    'schema',
    _$schema,
    hook: JsonValueHook(),
  );
  static String? _$description(JsonSchemaOutput v) => v.description;
  static const Field<JsonSchemaOutput, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
  );

  @override
  final MappableFields<JsonSchemaOutput> fields = const {
    #name: _f$name,
    #schema: _f$schema,
    #description: _f$description,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'jsonSchema';
  @override
  late final ClassMapperBase superMapper =
      OutputFormatMapper.ensureInitialized();

  static JsonSchemaOutput _instantiate(DecodingData data) {
    return JsonSchemaOutput(
      name: data.dec(_f$name),
      schema: data.dec(_f$schema),
      description: data.dec(_f$description),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static JsonSchemaOutput fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<JsonSchemaOutput>(map);
  }

  static JsonSchemaOutput fromJson(String json) {
    return ensureInitialized().decodeJson<JsonSchemaOutput>(json);
  }
}

mixin JsonSchemaOutputMappable {
  String toJson() {
    return JsonSchemaOutputMapper.ensureInitialized()
        .encodeJson<JsonSchemaOutput>(this as JsonSchemaOutput);
  }

  Map<String, dynamic> toMap() {
    return JsonSchemaOutputMapper.ensureInitialized()
        .encodeMap<JsonSchemaOutput>(this as JsonSchemaOutput);
  }
}

class ToolArgumentsMapper extends ClassMapperBase<ToolArguments> {
  ToolArgumentsMapper._();

  static ToolArgumentsMapper? _instance;
  static ToolArgumentsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolArgumentsMapper._());
      JsonToolArgumentsMapper.ensureInitialized();
      FreeFormToolArgumentsMapper.ensureInitialized();
      NativeToolArgumentsMapper.ensureInitialized();
      MalformedToolArgumentsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolArguments';

  @override
  final MappableFields<ToolArguments> fields = const {};

  static ToolArguments _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'ToolArguments',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolArguments fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolArguments>(map);
  }

  static ToolArguments fromJson(String json) {
    return ensureInitialized().decodeJson<ToolArguments>(json);
  }
}

mixin ToolArgumentsMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class JsonToolArgumentsMapper extends SubClassMapperBase<JsonToolArguments> {
  JsonToolArgumentsMapper._();

  static JsonToolArgumentsMapper? _instance;
  static JsonToolArgumentsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = JsonToolArgumentsMapper._());
      ToolArgumentsMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'JsonToolArguments';

  static Map<String, Object?> _$value(JsonToolArguments v) => v.value;
  static const Field<JsonToolArguments, Map<String, Object?>> _f$value = Field(
    'value',
    _$value,
    hook: JsonValueHook(),
  );
  static String? _$original(JsonToolArguments v) => v.original;
  static const Field<JsonToolArguments, String> _f$original = Field(
    'original',
    _$original,
    opt: true,
  );

  @override
  final MappableFields<JsonToolArguments> fields = const {
    #value: _f$value,
    #original: _f$original,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'json';
  @override
  late final ClassMapperBase superMapper =
      ToolArgumentsMapper.ensureInitialized();

  static JsonToolArguments _instantiate(DecodingData data) {
    return JsonToolArguments(
      value: data.dec(_f$value),
      original: data.dec(_f$original),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static JsonToolArguments fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<JsonToolArguments>(map);
  }

  static JsonToolArguments fromJson(String json) {
    return ensureInitialized().decodeJson<JsonToolArguments>(json);
  }
}

mixin JsonToolArgumentsMappable {
  String toJson() {
    return JsonToolArgumentsMapper.ensureInitialized()
        .encodeJson<JsonToolArguments>(this as JsonToolArguments);
  }

  Map<String, dynamic> toMap() {
    return JsonToolArgumentsMapper.ensureInitialized()
        .encodeMap<JsonToolArguments>(this as JsonToolArguments);
  }
}

class FreeFormToolArgumentsMapper
    extends SubClassMapperBase<FreeFormToolArguments> {
  FreeFormToolArgumentsMapper._();

  static FreeFormToolArgumentsMapper? _instance;
  static FreeFormToolArgumentsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FreeFormToolArgumentsMapper._());
      ToolArgumentsMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'FreeFormToolArguments';

  static String _$text(FreeFormToolArguments v) => v.text;
  static const Field<FreeFormToolArguments, String> _f$text = Field(
    'text',
    _$text,
  );

  @override
  final MappableFields<FreeFormToolArguments> fields = const {#text: _f$text};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'freeForm';
  @override
  late final ClassMapperBase superMapper =
      ToolArgumentsMapper.ensureInitialized();

  static FreeFormToolArguments _instantiate(DecodingData data) {
    return FreeFormToolArguments(text: data.dec(_f$text));
  }

  @override
  final Function instantiate = _instantiate;

  static FreeFormToolArguments fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FreeFormToolArguments>(map);
  }

  static FreeFormToolArguments fromJson(String json) {
    return ensureInitialized().decodeJson<FreeFormToolArguments>(json);
  }
}

mixin FreeFormToolArgumentsMappable {
  String toJson() {
    return FreeFormToolArgumentsMapper.ensureInitialized()
        .encodeJson<FreeFormToolArguments>(this as FreeFormToolArguments);
  }

  Map<String, dynamic> toMap() {
    return FreeFormToolArgumentsMapper.ensureInitialized()
        .encodeMap<FreeFormToolArguments>(this as FreeFormToolArguments);
  }
}

class NativeToolArgumentsMapper
    extends SubClassMapperBase<NativeToolArguments> {
  NativeToolArgumentsMapper._();

  static NativeToolArgumentsMapper? _instance;
  static NativeToolArgumentsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = NativeToolArgumentsMapper._());
      ToolArgumentsMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'NativeToolArguments';

  static String _$providerId(NativeToolArguments v) => v.providerId;
  static const Field<NativeToolArguments, String> _f$providerId = Field(
    'providerId',
    _$providerId,
  );
  static String _$api(NativeToolArguments v) => v.api;
  static const Field<NativeToolArguments, String> _f$api = Field('api', _$api);
  static Object? _$value(NativeToolArguments v) => v.value;
  static const Field<NativeToolArguments, Object> _f$value = Field(
    'value',
    _$value,
    hook: JsonValueHook(),
  );

  @override
  final MappableFields<NativeToolArguments> fields = const {
    #providerId: _f$providerId,
    #api: _f$api,
    #value: _f$value,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'native';
  @override
  late final ClassMapperBase superMapper =
      ToolArgumentsMapper.ensureInitialized();

  static NativeToolArguments _instantiate(DecodingData data) {
    return NativeToolArguments(
      providerId: data.dec(_f$providerId),
      api: data.dec(_f$api),
      value: data.dec(_f$value),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static NativeToolArguments fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NativeToolArguments>(map);
  }

  static NativeToolArguments fromJson(String json) {
    return ensureInitialized().decodeJson<NativeToolArguments>(json);
  }
}

mixin NativeToolArgumentsMappable {
  String toJson() {
    return NativeToolArgumentsMapper.ensureInitialized()
        .encodeJson<NativeToolArguments>(this as NativeToolArguments);
  }

  Map<String, dynamic> toMap() {
    return NativeToolArgumentsMapper.ensureInitialized()
        .encodeMap<NativeToolArguments>(this as NativeToolArguments);
  }
}

class MalformedToolArgumentsMapper
    extends SubClassMapperBase<MalformedToolArguments> {
  MalformedToolArgumentsMapper._();

  static MalformedToolArgumentsMapper? _instance;
  static MalformedToolArgumentsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MalformedToolArgumentsMapper._());
      ToolArgumentsMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'MalformedToolArguments';

  static String _$original(MalformedToolArguments v) => v.original;
  static const Field<MalformedToolArguments, String> _f$original = Field(
    'original',
    _$original,
  );
  static String _$issue(MalformedToolArguments v) => v.issue;
  static const Field<MalformedToolArguments, String> _f$issue = Field(
    'issue',
    _$issue,
  );

  @override
  final MappableFields<MalformedToolArguments> fields = const {
    #original: _f$original,
    #issue: _f$issue,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'malformed';
  @override
  late final ClassMapperBase superMapper =
      ToolArgumentsMapper.ensureInitialized();

  static MalformedToolArguments _instantiate(DecodingData data) {
    return MalformedToolArguments(
      original: data.dec(_f$original),
      issue: data.dec(_f$issue),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MalformedToolArguments fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MalformedToolArguments>(map);
  }

  static MalformedToolArguments fromJson(String json) {
    return ensureInitialized().decodeJson<MalformedToolArguments>(json);
  }
}

mixin MalformedToolArgumentsMappable {
  String toJson() {
    return MalformedToolArgumentsMapper.ensureInitialized()
        .encodeJson<MalformedToolArguments>(this as MalformedToolArguments);
  }

  Map<String, dynamic> toMap() {
    return MalformedToolArgumentsMapper.ensureInitialized()
        .encodeMap<MalformedToolArguments>(this as MalformedToolArguments);
  }
}

class ToolResultContentMapper extends ClassMapperBase<ToolResultContent> {
  ToolResultContentMapper._();

  static ToolResultContentMapper? _instance;
  static ToolResultContentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolResultContentMapper._());
      JsonToolResultContentMapper.ensureInitialized();
      TextToolResultContentMapper.ensureInitialized();
      NativeToolResultContentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolResultContent';

  @override
  final MappableFields<ToolResultContent> fields = const {};

  static ToolResultContent _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'ToolResultContent',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolResultContent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolResultContent>(map);
  }

  static ToolResultContent fromJson(String json) {
    return ensureInitialized().decodeJson<ToolResultContent>(json);
  }
}

mixin ToolResultContentMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class JsonToolResultContentMapper
    extends SubClassMapperBase<JsonToolResultContent> {
  JsonToolResultContentMapper._();

  static JsonToolResultContentMapper? _instance;
  static JsonToolResultContentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = JsonToolResultContentMapper._());
      ToolResultContentMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'JsonToolResultContent';

  static Object? _$value(JsonToolResultContent v) => v.value;
  static const Field<JsonToolResultContent, Object> _f$value = Field(
    'value',
    _$value,
    hook: JsonValueHook(),
  );

  @override
  final MappableFields<JsonToolResultContent> fields = const {#value: _f$value};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'json';
  @override
  late final ClassMapperBase superMapper =
      ToolResultContentMapper.ensureInitialized();

  static JsonToolResultContent _instantiate(DecodingData data) {
    return JsonToolResultContent(value: data.dec(_f$value));
  }

  @override
  final Function instantiate = _instantiate;

  static JsonToolResultContent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<JsonToolResultContent>(map);
  }

  static JsonToolResultContent fromJson(String json) {
    return ensureInitialized().decodeJson<JsonToolResultContent>(json);
  }
}

mixin JsonToolResultContentMappable {
  String toJson() {
    return JsonToolResultContentMapper.ensureInitialized()
        .encodeJson<JsonToolResultContent>(this as JsonToolResultContent);
  }

  Map<String, dynamic> toMap() {
    return JsonToolResultContentMapper.ensureInitialized()
        .encodeMap<JsonToolResultContent>(this as JsonToolResultContent);
  }
}

class TextToolResultContentMapper
    extends SubClassMapperBase<TextToolResultContent> {
  TextToolResultContentMapper._();

  static TextToolResultContentMapper? _instance;
  static TextToolResultContentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TextToolResultContentMapper._());
      ToolResultContentMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'TextToolResultContent';

  static List<String> _$parts(TextToolResultContent v) => v.parts;
  static const Field<TextToolResultContent, List<String>> _f$parts = Field(
    'parts',
    _$parts,
  );

  @override
  final MappableFields<TextToolResultContent> fields = const {#parts: _f$parts};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'text';
  @override
  late final ClassMapperBase superMapper =
      ToolResultContentMapper.ensureInitialized();

  static TextToolResultContent _instantiate(DecodingData data) {
    return TextToolResultContent(parts: data.dec(_f$parts));
  }

  @override
  final Function instantiate = _instantiate;

  static TextToolResultContent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TextToolResultContent>(map);
  }

  static TextToolResultContent fromJson(String json) {
    return ensureInitialized().decodeJson<TextToolResultContent>(json);
  }
}

mixin TextToolResultContentMappable {
  String toJson() {
    return TextToolResultContentMapper.ensureInitialized()
        .encodeJson<TextToolResultContent>(this as TextToolResultContent);
  }

  Map<String, dynamic> toMap() {
    return TextToolResultContentMapper.ensureInitialized()
        .encodeMap<TextToolResultContent>(this as TextToolResultContent);
  }
}

class NativeToolResultContentMapper
    extends SubClassMapperBase<NativeToolResultContent> {
  NativeToolResultContentMapper._();

  static NativeToolResultContentMapper? _instance;
  static NativeToolResultContentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = NativeToolResultContentMapper._(),
      );
      ToolResultContentMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'NativeToolResultContent';

  static String _$providerId(NativeToolResultContent v) => v.providerId;
  static const Field<NativeToolResultContent, String> _f$providerId = Field(
    'providerId',
    _$providerId,
  );
  static String _$api(NativeToolResultContent v) => v.api;
  static const Field<NativeToolResultContent, String> _f$api = Field(
    'api',
    _$api,
  );
  static Object? _$value(NativeToolResultContent v) => v.value;
  static const Field<NativeToolResultContent, Object> _f$value = Field(
    'value',
    _$value,
    hook: JsonValueHook(),
  );

  @override
  final MappableFields<NativeToolResultContent> fields = const {
    #providerId: _f$providerId,
    #api: _f$api,
    #value: _f$value,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'native';
  @override
  late final ClassMapperBase superMapper =
      ToolResultContentMapper.ensureInitialized();

  static NativeToolResultContent _instantiate(DecodingData data) {
    return NativeToolResultContent(
      providerId: data.dec(_f$providerId),
      api: data.dec(_f$api),
      value: data.dec(_f$value),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static NativeToolResultContent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NativeToolResultContent>(map);
  }

  static NativeToolResultContent fromJson(String json) {
    return ensureInitialized().decodeJson<NativeToolResultContent>(json);
  }
}

mixin NativeToolResultContentMappable {
  String toJson() {
    return NativeToolResultContentMapper.ensureInitialized()
        .encodeJson<NativeToolResultContent>(this as NativeToolResultContent);
  }

  Map<String, dynamic> toMap() {
    return NativeToolResultContentMapper.ensureInitialized()
        .encodeMap<NativeToolResultContent>(this as NativeToolResultContent);
  }
}

class ToolResultMapper extends ClassMapperBase<ToolResult> {
  ToolResultMapper._();

  static ToolResultMapper? _instance;
  static ToolResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolResultMapper._());
      ToolSuccessMapper.ensureInitialized();
      ToolFailureMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolResult';

  @override
  final MappableFields<ToolResult> fields = const {};

  static ToolResult _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'ToolResult',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolResult>(map);
  }

  static ToolResult fromJson(String json) {
    return ensureInitialized().decodeJson<ToolResult>(json);
  }
}

mixin ToolResultMappable {
  String toJson();
  Map<String, dynamic> toMap();
}

class ToolSuccessMapper extends SubClassMapperBase<ToolSuccess> {
  ToolSuccessMapper._();

  static ToolSuccessMapper? _instance;
  static ToolSuccessMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolSuccessMapper._());
      ToolResultMapper.ensureInitialized().addSubMapper(_instance!);
      ToolResultContentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolSuccess';

  static String _$callId(ToolSuccess v) => v.callId;
  static const Field<ToolSuccess, String> _f$callId = Field('callId', _$callId);
  static ToolResultContent _$content(ToolSuccess v) => v.content;
  static const Field<ToolSuccess, ToolResultContent> _f$content = Field(
    'content',
    _$content,
  );

  @override
  final MappableFields<ToolSuccess> fields = const {
    #callId: _f$callId,
    #content: _f$content,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'success';
  @override
  late final ClassMapperBase superMapper = ToolResultMapper.ensureInitialized();

  static ToolSuccess _instantiate(DecodingData data) {
    return ToolSuccess(
      callId: data.dec(_f$callId),
      content: data.dec(_f$content),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolSuccess fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolSuccess>(map);
  }

  static ToolSuccess fromJson(String json) {
    return ensureInitialized().decodeJson<ToolSuccess>(json);
  }
}

mixin ToolSuccessMappable {
  String toJson() {
    return ToolSuccessMapper.ensureInitialized().encodeJson<ToolSuccess>(
      this as ToolSuccess,
    );
  }

  Map<String, dynamic> toMap() {
    return ToolSuccessMapper.ensureInitialized().encodeMap<ToolSuccess>(
      this as ToolSuccess,
    );
  }
}

class ToolFailureMapper extends SubClassMapperBase<ToolFailure> {
  ToolFailureMapper._();

  static ToolFailureMapper? _instance;
  static ToolFailureMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ToolFailureMapper._());
      ToolResultMapper.ensureInitialized().addSubMapper(_instance!);
      ToolResultContentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ToolFailure';

  static String _$callId(ToolFailure v) => v.callId;
  static const Field<ToolFailure, String> _f$callId = Field('callId', _$callId);
  static ToolResultContent _$content(ToolFailure v) => v.content;
  static const Field<ToolFailure, ToolResultContent> _f$content = Field(
    'content',
    _$content,
  );

  @override
  final MappableFields<ToolFailure> fields = const {
    #callId: _f$callId,
    #content: _f$content,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'applicationError';
  @override
  late final ClassMapperBase superMapper = ToolResultMapper.ensureInitialized();

  static ToolFailure _instantiate(DecodingData data) {
    return ToolFailure(
      callId: data.dec(_f$callId),
      content: data.dec(_f$content),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ToolFailure fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ToolFailure>(map);
  }

  static ToolFailure fromJson(String json) {
    return ensureInitialized().decodeJson<ToolFailure>(json);
  }
}

mixin ToolFailureMappable {
  String toJson() {
    return ToolFailureMapper.ensureInitialized().encodeJson<ToolFailure>(
      this as ToolFailure,
    );
  }

  Map<String, dynamic> toMap() {
    return ToolFailureMapper.ensureInitialized().encodeMap<ToolFailure>(
      this as ToolFailure,
    );
  }
}


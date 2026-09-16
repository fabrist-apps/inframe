// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'messages.dart';

class MessageMapper extends ClassMapperBase<Message> {
  MessageMapper._();

  static MessageMapper? _instance;
  static MessageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MessageMapper._());
      UserMessageMapper.ensureInitialized();
      AssistantMessageMapper.ensureInitialized();
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
    }
    return _instance!;
  }

  @override
  final String id = 'TextOutputPart';

  static String _$text(TextOutputPart v) => v.text;
  static const Field<TextOutputPart, String> _f$text = Field('text', _$text);

  @override
  final MappableFields<TextOutputPart> fields = const {#text: _f$text};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'text';
  @override
  late final ClassMapperBase superMapper = OutputPartMapper.ensureInitialized();

  static TextOutputPart _instantiate(DecodingData data) {
    return TextOutputPart(data.dec(_f$text));
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


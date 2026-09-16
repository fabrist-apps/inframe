// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'compatible_embedding_model.dart';

class EmbeddingOptionsMapper extends ClassMapperBase<EmbeddingOptions> {
  EmbeddingOptionsMapper._();

  static EmbeddingOptionsMapper? _instance;
  static EmbeddingOptionsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EmbeddingOptionsMapper._());
      SettingMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EmbeddingOptions';

  static Setting<String> _$user(EmbeddingOptions v) => v.user;
  static const Field<EmbeddingOptions, Setting<String>> _f$user = Field(
    'user',
    _$user,
    opt: true,
    def: const Setting.inherit(),
  );
  static Setting<Map<String, Object?>> _$extraBody(EmbeddingOptions v) =>
      v.extraBody;
  static const Field<EmbeddingOptions, Setting<Map<String, Object?>>>
  _f$extraBody = Field(
    'extraBody',
    _$extraBody,
    opt: true,
    def: const Setting.inherit(),
  );

  @override
  final MappableFields<EmbeddingOptions> fields = const {
    #user: _f$user,
    #extraBody: _f$extraBody,
  };

  static EmbeddingOptions _instantiate(DecodingData data) {
    return EmbeddingOptions(
      user: data.dec(_f$user),
      extraBody: data.dec(_f$extraBody),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EmbeddingOptions fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EmbeddingOptions>(map);
  }

  static EmbeddingOptions fromJson(String json) {
    return ensureInitialized().decodeJson<EmbeddingOptions>(json);
  }
}

mixin EmbeddingOptionsMappable {
  String toJson() {
    return EmbeddingOptionsMapper.ensureInitialized()
        .encodeJson<EmbeddingOptions>(this as EmbeddingOptions);
  }

  Map<String, dynamic> toMap() {
    return EmbeddingOptionsMapper.ensureInitialized()
        .encodeMap<EmbeddingOptions>(this as EmbeddingOptions);
  }
}


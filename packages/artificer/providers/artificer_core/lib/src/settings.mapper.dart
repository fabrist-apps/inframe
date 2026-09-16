// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'settings.dart';

class SettingMapper extends ClassMapperBase<Setting> {
  SettingMapper._();

  static SettingMapper? _instance;
  static SettingMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SettingMapper._());
      InheritSettingMapper.ensureInitialized();
      ValueSettingMapper.ensureInitialized();
      ClearSettingMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Setting';
  @override
  Function get typeFactory =>
      <T>(f) => f<Setting<T>>();

  @override
  final MappableFields<Setting> fields = const {};

  static Setting<T> _instantiate<T>(DecodingData data) {
    throw MapperException.missingSubclass(
      'Setting',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Setting<T> fromMap<T>(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Setting<T>>(map);
  }

  static Setting<T> fromJson<T>(String json) {
    return ensureInitialized().decodeJson<Setting<T>>(json);
  }
}

mixin SettingMappable<T> {
  String toJson();
  Map<String, dynamic> toMap();
}

class InheritSettingMapper extends SubClassMapperBase<InheritSetting> {
  InheritSettingMapper._();

  static InheritSettingMapper? _instance;
  static InheritSettingMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = InheritSettingMapper._());
      SettingMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'InheritSetting';
  @override
  Function get typeFactory =>
      <T>(f) => f<InheritSetting<T>>();

  @override
  final MappableFields<InheritSetting> fields = const {};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'inherit';
  @override
  late final ClassMapperBase superMapper = SettingMapper.ensureInitialized();

  static InheritSetting<T> _instantiate<T>(DecodingData data) {
    return InheritSetting();
  }

  @override
  final Function instantiate = _instantiate;

  static InheritSetting<T> fromMap<T>(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<InheritSetting<T>>(map);
  }

  static InheritSetting<T> fromJson<T>(String json) {
    return ensureInitialized().decodeJson<InheritSetting<T>>(json);
  }
}

mixin InheritSettingMappable<T> {
  String toJson() {
    return InheritSettingMapper.ensureInitialized()
        .encodeJson<InheritSetting<T>>(this as InheritSetting<T>);
  }

  Map<String, dynamic> toMap() {
    return InheritSettingMapper.ensureInitialized()
        .encodeMap<InheritSetting<T>>(this as InheritSetting<T>);
  }
}

class ValueSettingMapper extends SubClassMapperBase<ValueSetting> {
  ValueSettingMapper._();

  static ValueSettingMapper? _instance;
  static ValueSettingMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ValueSettingMapper._());
      SettingMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ValueSetting';
  @override
  Function get typeFactory =>
      <T>(f) => f<ValueSetting<T>>();

  static dynamic _$value(ValueSetting v) => v.value;
  static dynamic _arg$value<T>(f) => f<T>();
  static const Field<ValueSetting, dynamic> _f$value = Field(
    'value',
    _$value,
    arg: _arg$value,
  );

  @override
  final MappableFields<ValueSetting> fields = const {#value: _f$value};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'set';
  @override
  late final ClassMapperBase superMapper = SettingMapper.ensureInitialized();

  static ValueSetting<T> _instantiate<T>(DecodingData data) {
    return ValueSetting(data.dec(_f$value));
  }

  @override
  final Function instantiate = _instantiate;

  static ValueSetting<T> fromMap<T>(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ValueSetting<T>>(map);
  }

  static ValueSetting<T> fromJson<T>(String json) {
    return ensureInitialized().decodeJson<ValueSetting<T>>(json);
  }
}

mixin ValueSettingMappable<T> {
  String toJson() {
    return ValueSettingMapper.ensureInitialized().encodeJson<ValueSetting<T>>(
      this as ValueSetting<T>,
    );
  }

  Map<String, dynamic> toMap() {
    return ValueSettingMapper.ensureInitialized().encodeMap<ValueSetting<T>>(
      this as ValueSetting<T>,
    );
  }
}

class ClearSettingMapper extends SubClassMapperBase<ClearSetting> {
  ClearSettingMapper._();

  static ClearSettingMapper? _instance;
  static ClearSettingMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ClearSettingMapper._());
      SettingMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'ClearSetting';
  @override
  Function get typeFactory =>
      <T>(f) => f<ClearSetting<T>>();

  @override
  final MappableFields<ClearSetting> fields = const {};

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'clear';
  @override
  late final ClassMapperBase superMapper = SettingMapper.ensureInitialized();

  static ClearSetting<T> _instantiate<T>(DecodingData data) {
    return ClearSetting();
  }

  @override
  final Function instantiate = _instantiate;

  static ClearSetting<T> fromMap<T>(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ClearSetting<T>>(map);
  }

  static ClearSetting<T> fromJson<T>(String json) {
    return ensureInitialized().decodeJson<ClearSetting<T>>(json);
  }
}

mixin ClearSettingMappable<T> {
  String toJson() {
    return ClearSettingMapper.ensureInitialized().encodeJson<ClearSetting<T>>(
      this as ClearSetting<T>,
    );
  }

  Map<String, dynamic> toMap() {
    return ClearSettingMapper.ensureInitialized().encodeMap<ClearSetting<T>>(
      this as ClearSetting<T>,
    );
  }
}

class NativeFieldMapper extends ClassMapperBase<NativeField> {
  NativeFieldMapper._();

  static NativeFieldMapper? _instance;
  static NativeFieldMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = NativeFieldMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'NativeField';
  @override
  Function get typeFactory =>
      <T>(f) => f<NativeField<T>>();

  static bool _$isPresent(NativeField v) => v.isPresent;
  static const Field<NativeField, bool> _f$isPresent = Field(
    'isPresent',
    _$isPresent,
  );
  static dynamic _$value(NativeField v) => v.value;
  static dynamic _arg$value<T>(f) => f<T>();
  static const Field<NativeField, dynamic> _f$value = Field(
    'value',
    _$value,
    opt: true,
    arg: _arg$value,
  );

  @override
  final MappableFields<NativeField> fields = const {
    #isPresent: _f$isPresent,
    #value: _f$value,
  };

  static NativeField<T> _instantiate<T>(DecodingData data) {
    return NativeField(
      isPresent: data.dec(_f$isPresent),
      value: data.dec(_f$value),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static NativeField<T> fromMap<T>(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<NativeField<T>>(map);
  }

  static NativeField<T> fromJson<T>(String json) {
    return ensureInitialized().decodeJson<NativeField<T>>(json);
  }
}

mixin NativeFieldMappable<T> {
  String toJson() {
    return NativeFieldMapper.ensureInitialized().encodeJson<NativeField<T>>(
      this as NativeField<T>,
    );
  }

  Map<String, dynamic> toMap() {
    return NativeFieldMapper.ensureInitialized().encodeMap<NativeField<T>>(
      this as NativeField<T>,
    );
  }
}


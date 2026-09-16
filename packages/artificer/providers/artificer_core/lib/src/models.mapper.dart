// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'models.dart';

class CapabilitySupportMapper extends EnumMapper<CapabilitySupport> {
  CapabilitySupportMapper._();

  static CapabilitySupportMapper? _instance;
  static CapabilitySupportMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = CapabilitySupportMapper._());
    }
    return _instance!;
  }

  static CapabilitySupport fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  CapabilitySupport decode(dynamic value) {
    switch (value) {
      case r'supported':
        return CapabilitySupport.supported;
      case r'unsupported':
        return CapabilitySupport.unsupported;
      case r'unknown':
        return CapabilitySupport.unknown;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(CapabilitySupport self) {
    switch (self) {
      case CapabilitySupport.supported:
        return r'supported';
      case CapabilitySupport.unsupported:
        return r'unsupported';
      case CapabilitySupport.unknown:
        return r'unknown';
    }
  }
}

extension CapabilitySupportMapperExtension on CapabilitySupport {
  String toValue() {
    CapabilitySupportMapper.ensureInitialized();
    return MapperContainer.globals.toValue<CapabilitySupport>(this) as String;
  }
}

class ModelCapabilityMapper extends EnumMapper<ModelCapability> {
  ModelCapabilityMapper._();

  static ModelCapabilityMapper? _instance;
  static ModelCapabilityMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModelCapabilityMapper._());
    }
    return _instance!;
  }

  static ModelCapability fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ModelCapability decode(dynamic value) {
    switch (value) {
      case r'textGeneration':
        return ModelCapability.textGeneration;
      case r'streaming':
        return ModelCapability.streaming;
      case r'tools':
        return ModelCapability.tools;
      case r'structuredOutput':
        return ModelCapability.structuredOutput;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ModelCapability self) {
    switch (self) {
      case ModelCapability.textGeneration:
        return r'textGeneration';
      case ModelCapability.streaming:
        return r'streaming';
      case ModelCapability.tools:
        return r'tools';
      case ModelCapability.structuredOutput:
        return r'structuredOutput';
    }
  }
}

extension ModelCapabilityMapperExtension on ModelCapability {
  String toValue() {
    ModelCapabilityMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ModelCapability>(this) as String;
  }
}

class ModelCapabilitiesMapper extends ClassMapperBase<ModelCapabilities> {
  ModelCapabilitiesMapper._();

  static ModelCapabilitiesMapper? _instance;
  static ModelCapabilitiesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ModelCapabilitiesMapper._());
      ModelCapabilityMapper.ensureInitialized();
      CapabilitySupportMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ModelCapabilities';

  static Map<ModelCapability, CapabilitySupport> _$values(
    ModelCapabilities v,
  ) => v.values;
  static const Field<ModelCapabilities, Map<ModelCapability, CapabilitySupport>>
  _f$values = Field('values', _$values, opt: true, def: const {});

  @override
  final MappableFields<ModelCapabilities> fields = const {#values: _f$values};

  static ModelCapabilities _instantiate(DecodingData data) {
    return ModelCapabilities(data.dec(_f$values));
  }

  @override
  final Function instantiate = _instantiate;

  static ModelCapabilities fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ModelCapabilities>(map);
  }

  static ModelCapabilities fromJson(String json) {
    return ensureInitialized().decodeJson<ModelCapabilities>(json);
  }
}

mixin ModelCapabilitiesMappable {
  String toJson() {
    return ModelCapabilitiesMapper.ensureInitialized()
        .encodeJson<ModelCapabilities>(this as ModelCapabilities);
  }

  Map<String, dynamic> toMap() {
    return ModelCapabilitiesMapper.ensureInitialized()
        .encodeMap<ModelCapabilities>(this as ModelCapabilities);
  }
}


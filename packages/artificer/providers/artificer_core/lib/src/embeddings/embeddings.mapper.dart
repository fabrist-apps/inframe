// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'embeddings.dart';

class EmbeddingInputMapper extends ClassMapperBase<EmbeddingInput> {
  EmbeddingInputMapper._();

  static EmbeddingInputMapper? _instance;
  static EmbeddingInputMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EmbeddingInputMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'EmbeddingInput';

  static String _$text(EmbeddingInput v) => v.text;
  static const Field<EmbeddingInput, String> _f$text = Field('text', _$text);

  @override
  final MappableFields<EmbeddingInput> fields = const {#text: _f$text};

  static EmbeddingInput _instantiate(DecodingData data) {
    return EmbeddingInput.text(data.dec(_f$text));
  }

  @override
  final Function instantiate = _instantiate;

  static EmbeddingInput fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EmbeddingInput>(map);
  }

  static EmbeddingInput fromJson(String json) {
    return ensureInitialized().decodeJson<EmbeddingInput>(json);
  }
}

mixin EmbeddingInputMappable {
  String toJson() {
    return EmbeddingInputMapper.ensureInitialized().encodeJson<EmbeddingInput>(
      this as EmbeddingInput,
    );
  }

  Map<String, dynamic> toMap() {
    return EmbeddingInputMapper.ensureInitialized().encodeMap<EmbeddingInput>(
      this as EmbeddingInput,
    );
  }
}

class EmbeddingRequestMapper extends ClassMapperBase<EmbeddingRequest> {
  EmbeddingRequestMapper._();

  static EmbeddingRequestMapper? _instance;
  static EmbeddingRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EmbeddingRequestMapper._());
      EmbeddingInputMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EmbeddingRequest';

  static List<EmbeddingInput> _$items(EmbeddingRequest v) => v.items;
  static const Field<EmbeddingRequest, List<EmbeddingInput>> _f$items = Field(
    'items',
    _$items,
  );
  static int? _$dimensions(EmbeddingRequest v) => v.dimensions;
  static const Field<EmbeddingRequest, int> _f$dimensions = Field(
    'dimensions',
    _$dimensions,
    opt: true,
  );

  @override
  final MappableFields<EmbeddingRequest> fields = const {
    #items: _f$items,
    #dimensions: _f$dimensions,
  };

  static EmbeddingRequest _instantiate(DecodingData data) {
    return EmbeddingRequest(
      items: data.dec(_f$items),
      dimensions: data.dec(_f$dimensions),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EmbeddingRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EmbeddingRequest>(map);
  }

  static EmbeddingRequest fromJson(String json) {
    return ensureInitialized().decodeJson<EmbeddingRequest>(json);
  }
}

mixin EmbeddingRequestMappable {
  String toJson() {
    return EmbeddingRequestMapper.ensureInitialized()
        .encodeJson<EmbeddingRequest>(this as EmbeddingRequest);
  }

  Map<String, dynamic> toMap() {
    return EmbeddingRequestMapper.ensureInitialized()
        .encodeMap<EmbeddingRequest>(this as EmbeddingRequest);
  }
}

class EmbeddingCapabilitiesMapper
    extends ClassMapperBase<EmbeddingCapabilities> {
  EmbeddingCapabilitiesMapper._();

  static EmbeddingCapabilitiesMapper? _instance;
  static EmbeddingCapabilitiesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EmbeddingCapabilitiesMapper._());
      CapabilitySupportMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EmbeddingCapabilities';

  static CapabilitySupport _$dimensions(EmbeddingCapabilities v) =>
      v.dimensions;
  static const Field<EmbeddingCapabilities, CapabilitySupport> _f$dimensions =
      Field(
        'dimensions',
        _$dimensions,
        opt: true,
        def: CapabilitySupport.unknown,
      );

  @override
  final MappableFields<EmbeddingCapabilities> fields = const {
    #dimensions: _f$dimensions,
  };

  static EmbeddingCapabilities _instantiate(DecodingData data) {
    return EmbeddingCapabilities(dimensions: data.dec(_f$dimensions));
  }

  @override
  final Function instantiate = _instantiate;

  static EmbeddingCapabilities fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EmbeddingCapabilities>(map);
  }

  static EmbeddingCapabilities fromJson(String json) {
    return ensureInitialized().decodeJson<EmbeddingCapabilities>(json);
  }
}

mixin EmbeddingCapabilitiesMappable {
  String toJson() {
    return EmbeddingCapabilitiesMapper.ensureInitialized()
        .encodeJson<EmbeddingCapabilities>(this as EmbeddingCapabilities);
  }

  Map<String, dynamic> toMap() {
    return EmbeddingCapabilitiesMapper.ensureInitialized()
        .encodeMap<EmbeddingCapabilities>(this as EmbeddingCapabilities);
  }
}

class EmbeddingResultMapper extends ClassMapperBase<EmbeddingResult> {
  EmbeddingResultMapper._();

  static EmbeddingResultMapper? _instance;
  static EmbeddingResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EmbeddingResultMapper._());
      NativePayloadMapper.ensureInitialized();
      UsageMapper.ensureInitialized();
      ResponseMetadataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EmbeddingResult';

  static List<List<double>> _$vectors(EmbeddingResult v) => v.vectors;
  static const Field<EmbeddingResult, List<List<double>>> _f$vectors = Field(
    'vectors',
    _$vectors,
  );
  static String _$modelId(EmbeddingResult v) => v.modelId;
  static const Field<EmbeddingResult, String> _f$modelId = Field(
    'modelId',
    _$modelId,
  );
  static NativePayload _$native(EmbeddingResult v) => v.native;
  static const Field<EmbeddingResult, NativePayload> _f$native = Field(
    'native',
    _$native,
  );
  static Usage? _$usage(EmbeddingResult v) => v.usage;
  static const Field<EmbeddingResult, Usage> _f$usage = Field(
    'usage',
    _$usage,
    opt: true,
  );
  static ResponseMetadata? _$metadata(EmbeddingResult v) => v.metadata;
  static const Field<EmbeddingResult, ResponseMetadata> _f$metadata = Field(
    'metadata',
    _$metadata,
    opt: true,
  );
  static int _$schemaVersion(EmbeddingResult v) => v.schemaVersion;
  static const Field<EmbeddingResult, int> _f$schemaVersion = Field(
    'schemaVersion',
    _$schemaVersion,
    opt: true,
    def: 1,
  );

  @override
  final MappableFields<EmbeddingResult> fields = const {
    #vectors: _f$vectors,
    #modelId: _f$modelId,
    #native: _f$native,
    #usage: _f$usage,
    #metadata: _f$metadata,
    #schemaVersion: _f$schemaVersion,
  };

  static EmbeddingResult _instantiate(DecodingData data) {
    return EmbeddingResult(
      vectors: data.dec(_f$vectors),
      modelId: data.dec(_f$modelId),
      native: data.dec(_f$native),
      usage: data.dec(_f$usage),
      metadata: data.dec(_f$metadata),
      schemaVersion: data.dec(_f$schemaVersion),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EmbeddingResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EmbeddingResult>(map);
  }

  static EmbeddingResult fromJson(String json) {
    return ensureInitialized().decodeJson<EmbeddingResult>(json);
  }
}

mixin EmbeddingResultMappable {
  String toJson() {
    return EmbeddingResultMapper.ensureInitialized()
        .encodeJson<EmbeddingResult>(this as EmbeddingResult);
  }

  Map<String, dynamic> toMap() {
    return EmbeddingResultMapper.ensureInitialized().encodeMap<EmbeddingResult>(
      this as EmbeddingResult,
    );
  }
}

class IndexedEmbeddingMapper extends ClassMapperBase<IndexedEmbedding> {
  IndexedEmbeddingMapper._();

  static IndexedEmbeddingMapper? _instance;
  static IndexedEmbeddingMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IndexedEmbeddingMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'IndexedEmbedding';

  static int _$index(IndexedEmbedding v) => v.index;
  static const Field<IndexedEmbedding, int> _f$index = Field('index', _$index);
  static List<double> _$embedding(IndexedEmbedding v) => v.embedding;
  static const Field<IndexedEmbedding, List<double>> _f$embedding = Field(
    'embedding',
    _$embedding,
  );

  @override
  final MappableFields<IndexedEmbedding> fields = const {
    #index: _f$index,
    #embedding: _f$embedding,
  };

  static IndexedEmbedding _instantiate(DecodingData data) {
    return IndexedEmbedding(
      index: data.dec(_f$index),
      embedding: data.dec(_f$embedding),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IndexedEmbedding fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IndexedEmbedding>(map);
  }

  static IndexedEmbedding fromJson(String json) {
    return ensureInitialized().decodeJson<IndexedEmbedding>(json);
  }
}

mixin IndexedEmbeddingMappable {
  String toJson() {
    return IndexedEmbeddingMapper.ensureInitialized()
        .encodeJson<IndexedEmbedding>(this as IndexedEmbedding);
  }

  Map<String, dynamic> toMap() {
    return IndexedEmbeddingMapper.ensureInitialized()
        .encodeMap<IndexedEmbedding>(this as IndexedEmbedding);
  }
}

class EmbeddingBatchMapper extends ClassMapperBase<EmbeddingBatch> {
  EmbeddingBatchMapper._();

  static EmbeddingBatchMapper? _instance;
  static EmbeddingBatchMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EmbeddingBatchMapper._());
      IndexedEmbeddingMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'EmbeddingBatch';

  static String _$model(EmbeddingBatch v) => v.model;
  static const Field<EmbeddingBatch, String> _f$model = Field('model', _$model);
  static List<IndexedEmbedding> _$data(EmbeddingBatch v) => v.data;
  static const Field<EmbeddingBatch, List<IndexedEmbedding>> _f$data = Field(
    'data',
    _$data,
  );
  static Map<String, Object?>? _$usage(EmbeddingBatch v) => v.usage;
  static const Field<EmbeddingBatch, Map<String, Object?>> _f$usage = Field(
    'usage',
    _$usage,
    opt: true,
    hook: JsonValueHook(),
  );

  @override
  final MappableFields<EmbeddingBatch> fields = const {
    #model: _f$model,
    #data: _f$data,
    #usage: _f$usage,
  };

  static EmbeddingBatch _instantiate(DecodingData data) {
    return EmbeddingBatch(
      model: data.dec(_f$model),
      data: data.dec(_f$data),
      usage: data.dec(_f$usage),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EmbeddingBatch fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EmbeddingBatch>(map);
  }

  static EmbeddingBatch fromJson(String json) {
    return ensureInitialized().decodeJson<EmbeddingBatch>(json);
  }
}

mixin EmbeddingBatchMappable {
  String toJson() {
    return EmbeddingBatchMapper.ensureInitialized().encodeJson<EmbeddingBatch>(
      this as EmbeddingBatch,
    );
  }

  Map<String, dynamic> toMap() {
    return EmbeddingBatchMapper.ensureInitialized().encodeMap<EmbeddingBatch>(
      this as EmbeddingBatch,
    );
  }
}


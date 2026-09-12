import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'xai';
const _api = 'models';

/// Typed native xAI model discovery operations.
final class XaiModelsResource {
  /// Creates the resource over one provider-owned core client.
  const XaiModelsResource(this._client);

  final ProviderHttpClient _client;

  /// Lists the OpenAI-compatible model view once.
  Effect<NativeResponse<XaiModelPage>, AiError> list() =>
      _get('models', 'models', XaiModelPage.fromJson);

  /// Retrieves one model from the compatible view.
  Effect<NativeResponse<XaiModel>, AiError> retrieve(String modelId) {
    final id = _nonEmpty(modelId, 'modelId');
    return _get('models/${Uri.encodeComponent(id)}', id, XaiModel.fromJson);
  }

  /// Lists xAI language-model metadata once.
  Effect<NativeResponse<XaiDetailedModelPage>, AiError> listLanguage() =>
      _get('language-models', 'language-models', XaiDetailedModelPage.fromJson);

  /// Retrieves one xAI language-model metadata object.
  Effect<NativeResponse<XaiDetailedModel>, AiError> retrieveLanguage(String modelId) {
    final id = _nonEmpty(modelId, 'modelId');
    return _get('language-models/${Uri.encodeComponent(id)}', id, XaiDetailedModel.fromJson);
  }

  /// Lists xAI embedding-model metadata once.
  Effect<NativeResponse<XaiDetailedModelPage>, AiError> listEmbedding() =>
      _get('embedding-models', 'embedding-models', XaiDetailedModelPage.fromJson);

  /// Retrieves one xAI embedding-model metadata object.
  Effect<NativeResponse<XaiDetailedModel>, AiError> retrieveEmbedding(String modelId) {
    final id = _nonEmpty(modelId, 'modelId');
    return _get('embedding-models/${Uri.encodeComponent(id)}', id, XaiDetailedModel.fromJson);
  }

  Effect<NativeResponse<T>, AiError> _get<T>(
    String path,
    String modelId,
    T Function(JsonObject) decode,
  ) => _client
      .sendJson(
        ProviderHttpRequest(method: 'GET', path: path),
        providerId: _providerId,
        api: _api,
        modelId: modelId,
      )
      .flatMap((response, _) => _decode(response, decode));
}

/// One model from xAI's compatible `/models` view.
final class XaiModel {
  /// Decodes a model object.
  factory XaiModel.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiModel._(
      id: _string(value, 'id'),
      aliases: _strings(value, 'aliases'),
      created: _integer(value, 'created'),
      ownedBy: _string(value, 'owned_by'),
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'aliases', 'created', 'object', 'owned_by'})),
    );
  }

  XaiModel._({
    required this.id,
    required Iterable<String> aliases,
    required this.created,
    required this.ownedBy,
    required this.raw,
    required this.extensions,
  }) : aliases = List.unmodifiable(aliases);

  /// Provider-local model ID.
  final String id;

  /// IDs that may select the same model.
  final List<String> aliases;

  /// Unix creation timestamp.
  final int created;

  /// Owning organization.
  final String ownedBy;

  /// Complete native object.
  final JsonObject raw;

  /// Pricing, context, and newer model fields.
  final JsonObject extensions;
}

/// One detailed language or embedding model metadata object.
final class XaiDetailedModel {
  /// Decodes detailed xAI model metadata.
  factory XaiDetailedModel.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiDetailedModel._(
      id: _string(value, 'id'),
      fingerprint: _string(value, 'fingerprint'),
      created: _integer(value, 'created'),
      ownedBy: _string(value, 'owned_by'),
      version: _string(value, 'version'),
      aliases: _strings(value, 'aliases'),
      inputModalities: _strings(value, 'input_modalities'),
      outputModalities: _strings(value, 'output_modalities'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'id',
          'fingerprint',
          'created',
          'object',
          'owned_by',
          'version',
          'aliases',
          'input_modalities',
          'output_modalities',
        }),
      ),
    );
  }

  XaiDetailedModel._({
    required this.id,
    required this.fingerprint,
    required this.created,
    required this.ownedBy,
    required this.version,
    required Iterable<String> aliases,
    required Iterable<String> inputModalities,
    required Iterable<String> outputModalities,
    required this.raw,
    required this.extensions,
  }) : aliases = List.unmodifiable(aliases),
       inputModalities = List.unmodifiable(inputModalities),
       outputModalities = List.unmodifiable(outputModalities);

  /// Provider-local model ID.
  final String id;

  /// xAI serving fingerprint.
  final String fingerprint;

  /// Unix creation timestamp.
  final int created;

  /// Owning organization.
  final String ownedBy;

  /// Native model version.
  final String version;

  /// Equivalent selectable IDs.
  final List<String> aliases;

  /// Modalities reported by discovery.
  final List<String> inputModalities;

  /// Output modalities reported by discovery.
  final List<String> outputModalities;

  /// Complete native object.
  final JsonObject raw;

  /// Native prices and newer metadata fields.
  final JsonObject extensions;
}

/// One explicitly fetched compatible model page.
final class XaiModelPage {
  /// Decodes a compatible model page.
  factory XaiModelPage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiModelPage._(
      data: _list(value, 'data').map((item) => XaiModel.fromJson(_jsonObject(item, 'model'))),
      raw: raw,
      extensions: JsonObject(_without(value, {'object', 'data'})),
    );
  }

  XaiModelPage._({required Iterable<XaiModel> data, required this.raw, required this.extensions})
    : data = List.unmodifiable(data);

  /// Models in this response.
  final List<XaiModel> data;

  /// Complete native page.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One explicitly fetched detailed model page.
final class XaiDetailedModelPage {
  /// Decodes a language- or embedding-model page.
  factory XaiDetailedModelPage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiDetailedModelPage._(
      models: _list(
        value,
        'models',
      ).map((item) => XaiDetailedModel.fromJson(_jsonObject(item, 'model'))),
      raw: raw,
      extensions: JsonObject(_without(value, {'models'})),
    );
  }

  XaiDetailedModelPage._({
    required Iterable<XaiDetailedModel> models,
    required this.raw,
    required this.extensions,
  }) : models = List.unmodifiable(models);

  /// Models in this response.
  final List<XaiDetailedModel> models;

  /// Complete native page.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

Effect<NativeResponse<T>, AiError> _decode<T>(
  NativeResponse<JsonObject> response,
  T Function(JsonObject) decode,
) {
  try {
    return Effect.succeed(
      NativeResponse(
        value: decode(response.value),
        payload: response.payload,
        metadata: response.metadata,
      ),
    );
  } on FormatException catch (error) {
    return Effect.fail(ProtocolError(error.message));
  }
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

List<String> _strings(Map<String, Object?> value, String key) {
  final values = _list(value, key);
  if (values.any((value) => value is! String)) {
    throw FormatException('$key must contain strings.');
  }
  return values.cast<String>();
}

JsonObject _jsonObject(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return JsonObject(value);
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

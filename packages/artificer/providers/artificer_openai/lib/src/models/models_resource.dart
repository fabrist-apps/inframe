import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'openai';
const _api = 'models';

/// Typed native model discovery operations.
final class OpenAIModelsResource {
  /// Creates the resource over one provider-owned core client.
  const OpenAIModelsResource(this._client);

  final ProviderHttpClient _client;

  /// Lists one model page. This never follows pagination automatically.
  Effect<NativeResponse<OpenAIModelPage>, AiError> list() => _client
      .sendJson(
        ProviderHttpRequest(method: 'GET', path: 'models'),
        providerId: _providerId,
        api: _api,
        modelId: 'models',
      )
      .flatMap((response) => _decode(response, OpenAIModelPage.fromJson));

  /// Retrieves one model by its exact provider-local ID.
  Effect<NativeResponse<OpenAIModel>, AiError> retrieve(String modelId) {
    final id = _nonEmpty(modelId, 'modelId');
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: 'models/${Uri.encodeComponent(id)}'),
          providerId: _providerId,
          api: _api,
          modelId: id,
        )
        .flatMap((response) => _decode(response, OpenAIModel.fromJson));
  }
}

/// One model returned by native discovery.
final class OpenAIModel {
  /// Decodes a model object.
  factory OpenAIModel.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIModel._(
      id: _string(value, 'id'),
      created: _integer(value, 'created'),
      ownedBy: _string(value, 'owned_by'),
      shutdownDate: _nullableString(value, 'shutdown_date'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'id', 'object', 'created', 'owned_by', 'shutdown_date'}),
      ),
    );
  }

  OpenAIModel._({
    required this.id,
    required this.created,
    required this.ownedBy,
    required this.shutdownDate,
    required this.raw,
    required this.extensions,
  });

  /// Provider-local model ID.
  final String id;

  /// Unix creation timestamp.
  final int created;

  /// Owning organization.
  final String ownedBy;

  /// Announced shutdown date, when any.
  final String? shutdownDate;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One explicitly fetched model page.
final class OpenAIModelPage {
  /// Decodes a model page.
  factory OpenAIModelPage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIModelPage._(
      data: _list(value, 'data').map((item) => OpenAIModel.fromJson(JsonObject.fromDart(item))),
      raw: raw,
      extensions: JsonObject(_without(value, {'object', 'data'})),
    );
  }

  OpenAIModelPage._({
    required Iterable<OpenAIModel> data,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Models in this page.
  final List<OpenAIModel> data;

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

String? _nullableString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string or null.');
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

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

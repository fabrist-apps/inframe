import 'package:artificer_anthropic/src/models/model_models.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'anthropic';
const _api = 'models';

/// Typed native Anthropic model-discovery operations.
final class AnthropicModelsResource {
  /// Creates this resource over one provider-owned core client.
  const AnthropicModelsResource(this._client);

  final ProviderHttpClient _client;

  /// Lists one model page without following its cursors automatically.
  Effect<NativeResponse<AnthropicModelPage>, AiError> list({
    int? limit,
    String? beforeId,
    String? afterId,
  }) {
    if (limit != null && (limit < 1 || limit > 1000)) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 1000');
    }
    final query = <String, String>{
      if (limit != null) 'limit': '$limit',
      if (beforeId != null) 'before_id': _nonEmpty(beforeId, 'beforeId'),
      if (afterId != null) 'after_id': _nonEmpty(afterId, 'afterId'),
    };
    final path = Uri(
      path: 'models',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'models',
        )
        .flatMap((response) => _decode(response, AnthropicModelPage.fromJson));
  }

  /// Retrieves one model by its exact provider-local identifier.
  Effect<NativeResponse<AnthropicModel>, AiError> retrieve(String modelId) {
    final id = _nonEmpty(modelId, 'modelId');
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'GET',
            path: 'models/${Uri.encodeComponent(id)}',
          ),
          providerId: _providerId,
          api: _api,
          modelId: id,
        )
        .flatMap((response) => _decode(response, AnthropicModel.fromJson));
  }
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

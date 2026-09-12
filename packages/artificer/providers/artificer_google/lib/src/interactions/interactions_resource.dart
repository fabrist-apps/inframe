import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/interactions/interaction_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'google';
const _api = 'interactions';
const _modelId = 'interactions';

/// Explicit lifecycle operations for the stable Google Interactions v1 API.
final class GoogleInteractionsResource {
  /// Creates interaction operations over one provider-owned client.
  const GoogleInteractionsResource(this._client);

  final ProviderHttpClient _client;

  /// Creates one interaction without polling for a terminal status.
  Effect<NativeResponse<GoogleInteraction>, AiError> create(
    GoogleInteractionRequest request,
  ) {
    if (request.stream == true) {
      return Effect.fail(
        const UnsupportedFeatureError(
          'Use the interaction streaming operation for stream: true.',
          feature: 'streaming',
        ),
      );
    }
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1/interactions',
            body: request.toJson(),
          ),
          providerId: _providerId,
          api: _api,
          modelId: request.model,
        )
        .flatMap((response) => _decode(response, GoogleInteraction.fromJson));
  }

  /// Retrieves one stored interaction without polling or following links.
  Effect<NativeResponse<GoogleInteraction>, AiError> retrieve(String id) {
    final encodedId = _id(id);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'GET',
            path: '/v1/interactions/$encodedId',
          ),
          providerId: _providerId,
          api: _api,
          modelId: _modelId,
        )
        .flatMap((response) => _decode(response, GoogleInteraction.fromJson));
  }

  /// Requests cancellation and returns the interaction state from that exchange.
  Effect<NativeResponse<GoogleInteraction>, AiError> cancel(String id) {
    final encodedId = _id(id);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'POST',
            path: '/v1/interactions/$encodedId/cancel',
          ),
          providerId: _providerId,
          api: _api,
          modelId: _modelId,
        )
        .flatMap((response) => _decode(response, GoogleInteraction.fromJson));
  }

  /// Deletes one stored interaction and accepts the stable v1 empty success body.
  Effect<NativeResponse<GoogleInteractionDeleteResult>, AiError> delete(String id) {
    final encodedId = _id(id);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'DELETE',
            path: '/v1/interactions/$encodedId',
          ),
          providerId: _providerId,
          api: _api,
          modelId: _modelId,
          allowEmptySuccess: true,
        )
        .map(
          (response) => NativeResponse(
            value: GoogleInteractionDeleteResult(response.value),
            payload: response.payload,
            metadata: response.metadata,
          ),
        );
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
    return Effect.fail(
      ProtocolError(
        error.message,
        partialOutput: response.payload.json,
      ),
    );
  }
}

String _id(String value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'id', 'must not be empty');
  }
  return Uri.encodeComponent(value);
}

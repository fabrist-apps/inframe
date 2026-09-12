import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/cached_contents/cached_content_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'google';
const _api = 'cachedContents';

/// Explicit lifecycle operations for Gemini cached content.
final class GoogleCachedContentsResource {
  /// Creates cache operations over one provider-owned client.
  const GoogleCachedContentsResource(this._client);

  final ProviderHttpClient _client;

  /// Explicitly creates a new immutable cache.
  Effect<NativeResponse<GoogleCachedContent>, AiError> create(
    GoogleCreateCachedContentRequest request,
  ) => _client
      .sendJson(
        ProviderHttpRequest(method: 'POST', path: '/v1beta/cachedContents', body: request.toJson()),
        providerId: _providerId,
        api: _api,
        modelId: 'cachedContents',
      )
      .flatMap((response, _) => _decode(response, GoogleCachedContent.fromJson));

  /// Lists exactly one requested page without following its page token.
  Effect<NativeResponse<GoogleCachedContentPage>, AiError> list({
    int? pageSize,
    String? pageToken,
  }) {
    if (pageSize != null && (pageSize <= 0 || pageSize > 1000)) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be between 1 and 1000');
    }
    final query = <String, String>{
      if (pageSize != null) 'pageSize': '$pageSize',
      if (pageToken != null) 'pageToken': _nonEmpty(pageToken, 'pageToken'),
    };
    final path = Uri(
      path: '/v1beta/cachedContents',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'cachedContents',
        )
        .flatMap((response, _) => _decode(response, GoogleCachedContentPage.fromJson));
  }

  /// Retrieves one cache metadata record without polling or refreshing it.
  Effect<NativeResponse<GoogleCachedContent>, AiError> retrieve(String name) {
    final id = _cacheId(name);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'GET',
            path: '/v1beta/cachedContents/${Uri.encodeComponent(id)}',
          ),
          providerId: _providerId,
          api: _api,
          modelId: 'cachedContents',
        )
        .flatMap((response, _) => _decode(response, GoogleCachedContent.fromJson));
  }

  /// Changes only one expiration field using a matching update mask.
  Effect<NativeResponse<GoogleCachedContent>, AiError> update(
    String name,
    GoogleCachedContentExpirationUpdate update,
  ) {
    final id = _cacheId(name);
    final path = Uri(
      path: '/v1beta/cachedContents/${Uri.encodeComponent(id)}',
      queryParameters: {'updateMask': update.updateMask},
    ).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'PATCH', path: path, body: update.toJson()),
          providerId: _providerId,
          api: _api,
          modelId: 'cachedContents',
        )
        .flatMap((response, _) => _decode(response, GoogleCachedContent.fromJson));
  }

  /// Explicitly deletes one cache and accepts Google's empty success body.
  ///
  /// Closing the provider never calls this method or deletes remote caches.
  Effect<NativeResponse<JsonObject>, AiError> delete(String name) {
    final id = _cacheId(name);
    return _client.sendJson(
      ProviderHttpRequest(
        method: 'DELETE',
        path: '/v1beta/cachedContents/${Uri.encodeComponent(id)}',
      ),
      providerId: _providerId,
      api: _api,
      modelId: 'cachedContents',
      allowEmptySuccess: true,
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
    return Effect.fail(ProtocolError(error.message));
  }
}

String _cacheId(String name) {
  if (!name.startsWith('cachedContents/') ||
      name.length == 'cachedContents/'.length ||
      name.substring('cachedContents/'.length).contains('/')) {
    throw ArgumentError.value(name, 'name', 'must have the format cachedContents/{id}');
  }
  return name.substring('cachedContents/'.length);
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

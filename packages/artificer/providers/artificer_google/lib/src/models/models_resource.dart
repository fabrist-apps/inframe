import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:artificer_google/src/generate_content/generate_content_resource.dart';
import 'package:artificer_google/src/models/google_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'google';
const _api = 'generateContent';

/// Typed native Gemini model discovery operations.
final class GoogleModelsResource {
  /// Creates model operations over one provider-owned client.
  const GoogleModelsResource(this._client, this._generateContent);

  final ProviderHttpClient _client;
  final GoogleGenerateContentResource _generateContent;

  /// Runs one native GenerateContent inference attempt.
  Effect<NativeResponse<GoogleGenerateContentResponse>, AiError> generateContent(
    GoogleGenerateContentRequest request,
  ) => _generateContent.create(request);

  /// Streams typed native GenerateContent response fragments.
  Flow<GoogleGenerateContentChunk, AiError> streamGenerateContent(
    GoogleGenerateContentRequest request, {
    int decodedEventCapacity = 16,
    int maxEventBytes = 8 * 1024 * 1024,
    int? maxStreamBytes,
  }) => _generateContent.stream(
    request,
    decodedEventCapacity: decodedEventCapacity,
    maxEventBytes: maxEventBytes,
    maxStreamBytes: maxStreamBytes,
  );

  /// Normalizes a native GenerateContent response without I/O.
  GenerationResult normalizeGenerateContent(
    NativeResponse<GoogleGenerateContentResponse> response, {
    int? candidateIndex,
    GoogleGenerateContentRequest? request,
  }) => _generateContent.normalize(
    response,
    candidateIndex: candidateIndex,
    request: request,
  );

  /// Counts tokens for the selected model through one explicit request.
  Effect<NativeResponse<GoogleCountTokensResponse>, AiError> countTokens(
    GoogleCountTokensRequest request,
  ) => _generateContent.countTokens(request);

  /// Lists exactly one requested page without following its page token.
  Effect<NativeResponse<GoogleModelPage>, AiError> list({int? pageSize, String? pageToken}) {
    if (pageSize != null && (pageSize <= 0 || pageSize > 1000)) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be between 1 and 1000');
    }
    final query = <String, String>{
      if (pageSize != null) 'pageSize': '$pageSize',
      if (pageToken != null) 'pageToken': _nonEmpty(pageToken, 'pageToken'),
    };
    final path = Uri(
      path: '/v1beta/models',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'models',
        )
        .flatMap((response) => _decode(response, GoogleModelPage.fromJson));
  }

  /// Retrieves one authoritative `models/{id}` resource without discovery.
  Effect<NativeResponse<GoogleModel>, AiError> retrieve(String name) {
    final modelId = _modelId(name);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'GET',
            path: '/v1beta/models/${Uri.encodeComponent(modelId)}',
          ),
          providerId: _providerId,
          api: _api,
          modelId: modelId,
        )
        .flatMap((response) => _decode(response, GoogleModel.fromJson));
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

String _modelId(String name) {
  if (!name.startsWith('models/') || name.length == 7 || name.substring(7).contains('/')) {
    throw ArgumentError.value(name, 'name', 'must have the format models/{id}');
  }
  return name.substring(7);
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

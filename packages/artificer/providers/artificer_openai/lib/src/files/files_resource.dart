import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_openai/src/files/file_models.dart';
import 'package:artificer_openai/src/responses/lifecycle_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'openai';
const _api = 'files';

/// Explicit caller-managed OpenAI file operations.
final class OpenAIFilesResource {
  /// Creates the resource over one provider-owned core client.
  const OpenAIFilesResource(this._client);

  final ProviderHttpClient _client;

  /// Uploads one file as multipart data without starting generation.
  Effect<NativeResponse<OpenAIFile>, AiError> create(
    UploadSource source, {
    required OpenAIFilePurpose purpose,
  }) {
    if (purpose == OpenAIFilePurpose.unknown) {
      throw ArgumentError.value(purpose, 'purpose', 'must be a documented upload purpose');
    }
    return _client
        .sendMultipart(
          ProviderMultipartRequest(path: 'files', fields: {'purpose': purpose.wireValue}),
          source,
          providerId: _providerId,
          api: _api,
        )
        .flatMap((response) => _decode(response, OpenAIFile.fromJson));
  }

  /// Lists one explicit page without polling or automatic pagination.
  Effect<NativeResponse<OpenAIFilePage>, AiError> list({
    OpenAIFilePurpose? purpose,
    int? limit,
    OpenAIListOrder? order,
    String? after,
  }) {
    if (limit != null && (limit < 1 || limit > 10000)) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 10000');
    }
    final query = <String, String>{
      if (purpose != null) 'purpose': purpose.wireValue,
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order.wireValue,
      if (after != null) 'after': _nonEmpty(after, 'after'),
    };
    final path = Uri(path: 'files', queryParameters: query.isEmpty ? null : query).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'files',
        )
        .flatMap((response) => _decode(response, OpenAIFilePage.fromJson));
  }

  /// Retrieves native file metadata.
  Effect<NativeResponse<OpenAIFile>, AiError> retrieve(String fileId) => _client
      .sendJson(
        ProviderHttpRequest(
          method: 'GET',
          path: 'files/${Uri.encodeComponent(_nonEmpty(fileId, 'fileId'))}',
        ),
        providerId: _providerId,
        api: _api,
        modelId: 'files',
      )
      .flatMap((response) => _decode(response, OpenAIFile.fromJson));

  /// Streams file bytes without buffering the complete response.
  Flow<List<int>, AiError> content(
    String fileId, {
    int decodedChunkCapacity = 16,
    int? maxResponseBytes,
  }) => _client.sendBytes(
    ProviderHttpRequest(
      method: 'GET',
      path: 'files/${Uri.encodeComponent(_nonEmpty(fileId, 'fileId'))}/content',
    ),
    decodedChunkCapacity: decodedChunkCapacity,
    maxResponseBytes: maxResponseBytes,
  );

  /// Deletes one remote file only when explicitly executed.
  Effect<NativeResponse<OpenAIDeletedFile>, AiError> delete(String fileId) => _client
      .sendJson(
        ProviderHttpRequest(
          method: 'DELETE',
          path: 'files/${Uri.encodeComponent(_nonEmpty(fileId, 'fileId'))}',
        ),
        providerId: _providerId,
        api: _api,
        modelId: 'files',
      )
      .flatMap((response) => _decode(response, OpenAIDeletedFile.fromJson));
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

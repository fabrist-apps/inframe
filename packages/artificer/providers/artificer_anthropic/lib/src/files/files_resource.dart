import 'package:artificer_anthropic/src/decode.dart';
import 'package:artificer_anthropic/src/files/file_models.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'anthropic';
const _api = 'files';

/// Explicit caller-managed Anthropic Files operations.
///
/// The pinned Files endpoints are stable and add no beta header themselves. The
/// shared [ProviderHttpClient] preserves any configured authentication, API
/// version, beta, and workspace headers. Constructing an operation performs no
/// I/O. Uploading, following a page cursor, downloading, and deleting each
/// require a separate caller execution.
final class AnthropicFilesResource {
  /// Creates the resource over one provider-owned core client.
  const AnthropicFilesResource(this._client);

  final ProviderHttpClient _client;

  /// Uploads one file as multipart data without starting generation.
  Effect<NativeResponse<AnthropicFileMetadata>, AiError> upload(
    UploadSource source, {
    int? expiresInSeconds,
  }) {
    if (expiresInSeconds != null && (expiresInSeconds < 3600 || expiresInSeconds > 7776000)) {
      throw ArgumentError.value(
        expiresInSeconds,
        'expiresInSeconds',
        'must be between 3600 and 7776000',
      );
    }
    return _client
        .sendMultipart(
          ProviderMultipartRequest(
            path: 'files',
            fields: {
              if (expiresInSeconds != null) 'expires_in_seconds': '$expiresInSeconds',
            },
          ),
          source,
          providerId: _providerId,
          api: _api,
        )
        .flatMap((response) => decodeNativeResponse(response, AnthropicFileMetadata.fromJson));
  }

  /// Lists one explicit page without automatically following [AnthropicFilePage.nextPage].
  Effect<NativeResponse<AnthropicFilePage>, AiError> list({
    Iterable<String>? ids,
    int? limit,
    String? page,
  }) {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    if (ids != null && (limit != null || page != null)) {
      throw ArgumentError.value(ids, 'ids', 'cannot be combined with limit or page');
    }
    final uniqueIds = ids == null
        ? null
        : List<String>.unmodifiable(
            ids.map((id) => _nonEmpty(id, 'ids')).toSet(),
          );
    if (uniqueIds != null) {
      if (uniqueIds.isEmpty) {
        throw ArgumentError.value(ids, 'ids', 'must contain at least one ID');
      }
      if (uniqueIds.length > 100) {
        throw ArgumentError.value(ids, 'ids', 'must contain at most 100 unique IDs');
      }
    }
    final query = <String, Object>{
      'ids': ?uniqueIds,
      if (limit != null) 'limit': '$limit',
      if (page != null) 'page': _nonEmpty(page, 'page'),
    };
    final path = Uri(
      path: 'files',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'files',
        )
        .flatMap((response) => decodeNativeResponse(response, AnthropicFilePage.fromJson));
  }

  /// Retrieves one file's native metadata.
  Effect<NativeResponse<AnthropicFileMetadata>, AiError> retrieveMetadata(String fileId) => _client
      .sendJson(
        ProviderHttpRequest(method: 'GET', path: _filePath(fileId)),
        providerId: _providerId,
        api: _api,
        modelId: 'files',
      )
      .flatMap((response) => decodeNativeResponse(response, AnthropicFileMetadata.fromJson));

  /// Downloads file bytes subject to Anthropic's native download restrictions.
  ///
  /// Non-downloadable files fail with the original [ProviderError]. The response
  /// is streamed with bounded backpressure and released on completion,
  /// interruption, or early consumption.
  Flow<List<int>, AiError> download(
    String fileId, {
    int decodedChunkCapacity = 16,
    int? maxResponseBytes,
  }) => _client.sendBytes(
    ProviderHttpRequest(
      method: 'GET',
      path: '${_filePath(fileId)}/content',
      headers: const {'accept': 'application/binary'},
    ),
    decodedChunkCapacity: decodedChunkCapacity,
    maxResponseBytes: maxResponseBytes,
  );

  /// Deletes one remote file only when explicitly executed.
  Effect<NativeResponse<AnthropicDeletedFile>, AiError> delete(String fileId) => _client
      .sendJson(
        ProviderHttpRequest(method: 'DELETE', path: _filePath(fileId)),
        providerId: _providerId,
        api: _api,
        modelId: 'files',
      )
      .flatMap((response) => decodeNativeResponse(response, AnthropicDeletedFile.fromJson));
}

String _filePath(String fileId) => 'files/${Uri.encodeComponent(_nonEmpty(fileId, 'fileId'))}';

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

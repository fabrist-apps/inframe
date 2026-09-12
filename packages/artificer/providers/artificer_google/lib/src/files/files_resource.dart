import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/files/google_file.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'google';
const _api = 'files';

/// Typed explicit upload and lifecycle operations for Google files.
final class GoogleFilesResource {
  /// Creates file operations over one provider-owned client.
  const GoogleFilesResource(this._client);

  final ProviderHttpClient _client;

  /// Starts and finalizes one resumable upload without polling or retrying.
  ///
  /// The operation is lazy and repeatable. Each execution starts a new remote
  /// upload and opens [source] once. The returned state is not a readiness
  /// guarantee; inspect it and call [retrieve] explicitly if needed.
  Effect<NativeResponse<GoogleFile>, AiError> upload(
    UploadSource source, {
    String? displayName,
  }) {
    final name = displayName == null ? source.filename : _nonEmpty(displayName, 'displayName');
    return _client
        .sendResumableUpload(
          ProviderResumableUploadRequest(
            startRequest: ProviderHttpRequest(
              method: 'POST',
              path: '/upload/v1beta/files',
              headers: {
                'x-goog-upload-protocol': 'resumable',
                'x-goog-upload-command': 'start',
                'x-goog-upload-header-content-length': '${source.length}',
                'x-goog-upload-header-content-type': source.mimeType,
                'content-type': 'application/json',
              },
              body: JsonObject({
                'file': {'display_name': name},
              }),
            ),
            uploadHeaders: {
              'x-goog-upload-offset': '0',
              'x-goog-upload-command': 'upload, finalize',
            },
            remoteResourceIdHeader: 'x-guploader-uploadid',
          ),
          source,
          providerId: _providerId,
          api: _api,
        )
        .flatMap(_decodeUploadedFile);
  }

  /// Lists exactly one requested page without following its page token.
  Effect<NativeResponse<GoogleFilePage>, AiError> list({int? pageSize, String? pageToken}) {
    if (pageSize != null && (pageSize <= 0 || pageSize > 100)) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be between 1 and 100');
    }
    final query = <String, String>{
      if (pageSize != null) 'pageSize': '$pageSize',
      if (pageToken != null) 'pageToken': _nonEmpty(pageToken, 'pageToken'),
    };
    final path = Uri(
      path: '/v1beta/files',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'files',
        )
        .flatMap((response) => _decode(response, GoogleFilePage.fromJson));
  }

  /// Retrieves one authoritative `files/{id}` resource without polling.
  Effect<NativeResponse<GoogleFile>, AiError> retrieve(String name) {
    final fileId = _fileId(name);
    return _client
        .sendJson(
          ProviderHttpRequest(
            method: 'GET',
            path: '/v1beta/files/${Uri.encodeComponent(fileId)}',
          ),
          providerId: _providerId,
          api: _api,
          modelId: 'files',
        )
        .flatMap((response) => _decode(response, GoogleFile.fromJson));
  }

  /// Deletes one authoritative `files/{id}` resource.
  ///
  /// Closing a provider never calls this method or deletes remote files.
  Effect<NativeResponse<JsonObject>, AiError> delete(String name) {
    final fileId = _fileId(name);
    return _client.sendJson(
      ProviderHttpRequest(
        method: 'DELETE',
        path: '/v1beta/files/${Uri.encodeComponent(fileId)}',
      ),
      providerId: _providerId,
      api: _api,
      modelId: 'files',
      allowEmptySuccess: true,
    );
  }
}

Effect<NativeResponse<GoogleFile>, AiError> _decodeUploadedFile(
  NativeResponse<JsonObject> response,
) {
  final value = response.value.toDart();
  final file = value['file'];
  if (file is! Map<String, Object?>) {
    return Effect.fail(const ProtocolError('Upload response file must be an object.'));
  }
  return _decode(response, (_) => GoogleFile.fromJson(JsonObject(file)));
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
    return Effect.fail(ProtocolError(error.message, remoteResourceId: _partialFileName(response)));
  }
}

String? _partialFileName(NativeResponse<JsonObject> response) {
  final value = response.value.toDart();
  final nested = value['file'];
  final candidate = nested is Map<String, Object?> ? nested['name'] : value['name'];
  return candidate is String && candidate.startsWith('files/') ? candidate : null;
}

String _fileId(String name) {
  if (!name.startsWith('files/') || name.length == 6 || name.substring(6).contains('/')) {
    throw ArgumentError.value(name, 'name', 'must have the format files/{id}');
  }
  return name.substring(6);
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

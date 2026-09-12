import 'dart:typed_data';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_xai/src/files/file_models.dart';
import 'package:conflux/conflux.dart';

const _providerId = 'xai';
const _api = 'files';

/// Native file listing order.
enum XaiFileOrder {
  /// Oldest or alphabetically first value first.
  ascending('asc'),

  /// Newest or alphabetically last value first.
  descending('desc');

  const XaiFileOrder(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Native file listing field.
enum XaiFileSortBy {
  /// Sort by creation time.
  createdAt('created_at'),

  /// Sort by filename.
  filename('filename'),

  /// Sort by file size.
  size('size');

  const XaiFileSortBy(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Native file download representation.
enum XaiFileContentFormat {
  /// Original uploaded bytes.
  original('original'),

  /// xAI text conversion.
  text('text');

  const XaiFileContentFormat(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Explicit caller-managed xAI file operations.
final class XaiFilesResource {
  /// Creates the resource over one provider-owned core client.
  const XaiFilesResource(this._client);

  final ProviderHttpClient _client;

  /// Uploads one file without starting generation.
  Effect<NativeResponse<XaiFile>, AiError> create(
    UploadSource source, {
    int? expiresAfter,
    String? purpose,
  }) {
    if (expiresAfter != null && (expiresAfter < 3600 || expiresAfter > 2592000)) {
      throw ArgumentError.value(expiresAfter, 'expiresAfter', 'must be between 3600 and 2592000');
    }
    final fields = <String, String>{
      if (expiresAfter != null) 'expires_after': '$expiresAfter',
      if (purpose != null) 'purpose': _nonEmpty(purpose, 'purpose'),
    };
    return _client
        .sendMultipart(
          ProviderMultipartRequest(path: 'files', fields: fields),
          source,
          providerId: _providerId,
          api: _api,
        )
        .flatMap((response, _) => _decode(response, XaiFile.fromJson));
  }

  /// Lists one page without automatic pagination.
  Effect<NativeResponse<XaiFilePage>, AiError> list({
    int? limit,
    XaiFileOrder? order,
    XaiFileSortBy? sortBy,
    String? paginationToken,
    String? after,
    String? filter,
  }) {
    if (limit != null && limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final query = <String, String>{
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order.wireValue,
      if (sortBy != null) 'sort_by': sortBy.wireValue,
      if (paginationToken != null)
        'pagination_token': _nonEmpty(paginationToken, 'paginationToken'),
      if (after != null) 'after': _nonEmpty(after, 'after'),
      if (filter != null) 'filter': _nonEmpty(filter, 'filter'),
    };
    final path = Uri(path: 'files', queryParameters: query.isEmpty ? null : query).toString();
    return _client
        .sendJson(
          ProviderHttpRequest(method: 'GET', path: path),
          providerId: _providerId,
          api: _api,
          modelId: 'files',
        )
        .flatMap((response, _) => _decode(response, XaiFilePage.fromJson));
  }

  /// Retrieves native file metadata.
  Effect<NativeResponse<XaiFile>, AiError> retrieve(String fileId) => _client
      .sendJson(
        ProviderHttpRequest(method: 'GET', path: 'files/${_fileId(fileId)}'),
        providerId: _providerId,
        api: _api,
        modelId: 'files',
      )
      .flatMap((response, _) => _decode(response, XaiFile.fromJson));

  /// Streams immutable raw file byte chunks without buffering the response.
  Flow<Uint8List, AiError> content(
    String fileId, {
    XaiFileContentFormat? format,
    int decodedChunkCapacity = 16,
    int? maxResponseBytes,
  }) {
    final base = 'files/${_fileId(fileId)}/content';
    final path = format == null
        ? base
        : Uri(path: base, queryParameters: {'format': format.wireValue}).toString();
    return _client
        .sendBytes(
          ProviderHttpRequest(method: 'GET', path: path),
          decodedChunkCapacity: decodedChunkCapacity,
          maxResponseBytes: maxResponseBytes,
        )
        .map(
          (chunk) => chunk is Uint8List
              ? chunk.asUnmodifiableView()
              : Uint8List.fromList(chunk).asUnmodifiableView(),
        );
  }

  /// Deletes one remote file only when explicitly executed.
  Effect<NativeResponse<XaiDeletedFile>, AiError> delete(String fileId) => _client
      .sendJson(
        ProviderHttpRequest(method: 'DELETE', path: 'files/${_fileId(fileId)}'),
        providerId: _providerId,
        api: _api,
        modelId: 'files',
      )
      .flatMap((response, _) => _decode(response, XaiDeletedFile.fromJson));
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

String _fileId(String fileId) => Uri.encodeComponent(_nonEmpty(fileId, 'fileId'));

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

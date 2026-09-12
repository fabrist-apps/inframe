import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// Metadata for one caller-managed Anthropic file.
final class AnthropicFileMetadata {
  /// Decodes file metadata from the native response shape.
  factory AnthropicFileMetadata.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    final sizeBytes = _integer(value, 'size_bytes');
    if (type != 'file') throw const FormatException('type must be file.');
    if (sizeBytes < 0) throw const FormatException('size_bytes must not be negative.');
    return AnthropicFileMetadata._(
      id: _string(value, 'id'),
      createdAt: _string(value, 'created_at'),
      filename: _string(value, 'filename'),
      mimeType: _string(value, 'mime_type'),
      sizeBytes: sizeBytes,
      type: type,
      downloadable: _optionalBoolean(value, 'downloadable'),
      expiresAt: _optionalString(value, 'expires_at'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'id',
          'created_at',
          'filename',
          'mime_type',
          'size_bytes',
          'type',
          'downloadable',
          'expires_at',
        }),
      ),
    );
  }

  AnthropicFileMetadata._({
    required this.id,
    required this.createdAt,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.type,
    required this.downloadable,
    required this.expiresAt,
    required this.raw,
    required this.extensions,
  });

  /// Provider-owned file ID.
  final String id;

  /// RFC 3339 creation timestamp as returned by Anthropic.
  final String createdAt;

  /// Original upload filename.
  final String filename;

  /// Stored media MIME type.
  final String mimeType;

  /// Stored file size in bytes.
  final int sizeBytes;

  /// Native object discriminator, currently `file`.
  final String type;

  /// Whether Anthropic allows the caller to download this file.
  final bool? downloadable;

  /// RFC 3339 expiration timestamp, or null when the file does not expire.
  final String? expiresAt;

  /// Complete immutable native object.
  final JsonObject raw;

  /// Immutable fields outside the pinned native schema.
  final JsonObject extensions;

  /// Creates a reference accepted by Anthropic Messages without doing I/O.
  ProviderFileSource asMessageSource() => ProviderFileSource(
    providerId: 'anthropic',
    api: 'messages',
    reference: id,
    mimeType: mimeType,
  );
}

/// One explicitly requested page of Anthropic files.
final class AnthropicFilePage {
  /// Decodes a native cursor page without fetching the next page.
  factory AnthropicFilePage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return AnthropicFilePage._(
      data: _list(value, 'data').map((item) {
        if (item is! Map<String, Object?>) {
          throw const FormatException('file page data must contain objects.');
        }
        return AnthropicFileMetadata.fromJson(JsonObject(item));
      }),
      nextPage: _requiredNullableString(value, 'next_page'),
      raw: raw,
      extensions: JsonObject(_without(value, {'data', 'next_page'})),
    );
  }

  AnthropicFilePage._({
    required Iterable<AnthropicFileMetadata> data,
    required this.nextPage,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Files in this page.
  final List<AnthropicFileMetadata> data;

  /// Cursor callers can pass to a later explicit list call.
  final String? nextPage;

  /// Complete immutable native page.
  final JsonObject raw;

  /// Immutable fields outside the pinned native schema.
  final JsonObject extensions;
}

/// Acknowledgement for one explicit Anthropic file deletion.
final class AnthropicDeletedFile {
  /// Decodes a native deletion acknowledgement.
  factory AnthropicDeletedFile.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _optionalString(value, 'type');
    if (type != null && type != 'file_deleted') {
      throw const FormatException('type must be file_deleted or null.');
    }
    return AnthropicDeletedFile._(
      id: _string(value, 'id'),
      type: type,
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'type'})),
    );
  }

  AnthropicDeletedFile._({
    required this.id,
    required this.type,
    required this.raw,
    required this.extensions,
  });

  /// ID of the deleted file.
  final String id;

  /// Native object discriminator, currently `file_deleted` when supplied.
  final String? type;

  /// Complete immutable native acknowledgement.
  final JsonObject raw;

  /// Immutable fields outside the pinned native schema.
  final JsonObject extensions;
}

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string or null.');
  return field;
}

String? _requiredNullableString(Map<String, Object?> value, String key) {
  if (!value.containsKey(key)) throw FormatException('$key is required.');
  return _optionalString(value, key);
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

bool? _optionalBoolean(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! bool) throw FormatException('$key must be a boolean or null.');
  return field;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

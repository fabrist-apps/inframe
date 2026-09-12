import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// One caller-managed xAI file.
final class XaiFile {
  /// Decodes native file metadata.
  factory XaiFile.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiFile._(
      id: _string(value, 'id'),
      bytes: _integer(value, 'bytes'),
      createdAt: _integer(value, 'created_at'),
      expiresAt: _optionalInteger(value, 'expires_at'),
      filename: _string(value, 'filename'),
      purpose: _optionalString(value, 'purpose'),
      publicUrl: _optionalString(value, 'public_url'),
      publicUrlExpiresAt: _optionalInteger(value, 'public_url_expires_at'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {
          'id',
          'object',
          'bytes',
          'created_at',
          'expires_at',
          'filename',
          'purpose',
          'public_url',
          'public_url_expires_at',
        }),
      ),
    );
  }

  XaiFile._({
    required this.id,
    required this.bytes,
    required this.createdAt,
    required this.expiresAt,
    required this.filename,
    required this.purpose,
    required this.publicUrl,
    required this.publicUrlExpiresAt,
    required this.raw,
    required this.extensions,
  });

  /// Provider file ID.
  final String id;

  /// File size in bytes.
  final int bytes;

  /// Unix creation timestamp.
  final int createdAt;

  /// Unix expiration timestamp, when configured.
  final int? expiresAt;

  /// Uploaded filename.
  final String filename;

  /// Compatibility purpose label, when returned.
  final String? purpose;

  /// Active public URL, when returned.
  final String? publicUrl;

  /// Unix expiration timestamp for the public URL, when any.
  final int? publicUrlExpiresAt;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Creates an explicit reference accepted by xAI Responses.
  ProviderFileSource asResponseSource({required String mimeType}) => ProviderFileSource(
    providerId: 'xai',
    api: 'responses',
    reference: id,
    mimeType: mimeType,
  );
}

/// One explicitly fetched xAI file page.
final class XaiFilePage {
  /// Decodes a native page.
  factory XaiFilePage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiFilePage._(
      data: _list(value, 'data').map((item) => XaiFile.fromJson(_jsonObject(item, 'file'))),
      paginationToken: _optionalString(value, 'pagination_token'),
      raw: raw,
      extensions: JsonObject(_without(value, {'data', 'pagination_token'})),
    );
  }

  XaiFilePage._({
    required Iterable<XaiFile> data,
    required this.paginationToken,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Files in this response.
  final List<XaiFile> data;

  /// Token callers may pass to a later explicit page request.
  final String? paginationToken;

  /// Complete native page.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One explicit file deletion acknowledgement.
final class XaiDeletedFile {
  /// Decodes a deletion acknowledgement.
  factory XaiDeletedFile.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return XaiDeletedFile._(
      id: _string(value, 'id'),
      deleted: _boolean(value, 'deleted'),
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'object', 'deleted'})),
    );
  }

  XaiDeletedFile._({
    required this.id,
    required this.deleted,
    required this.raw,
    required this.extensions,
  });

  /// Deleted file ID.
  final String id;

  /// Whether deletion succeeded.
  final bool deleted;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
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

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

int? _optionalInteger(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int) throw FormatException('$key must be an integer or null.');
  return field;
}

bool _boolean(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! bool) throw FormatException('$key must be a boolean.');
  return field;
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

JsonObject _jsonObject(Object? value, String name) {
  if (value is! Map<String, Object?>) throw FormatException('$name must be an object.');
  return JsonObject(value);
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

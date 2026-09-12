import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// A native OpenAI file purpose.
enum OpenAIFilePurpose {
  /// Input for assistants-compatible endpoints.
  assistants('assistants'),

  /// Assistant-generated output.
  assistantsOutput('assistants_output'),

  /// Batch input.
  batch('batch'),

  /// Batch output.
  batchOutput('batch_output'),

  /// Fine-tuning input.
  fineTune('fine-tune'),

  /// Fine-tuning output.
  fineTuneResults('fine-tune-results'),

  /// Vision input.
  vision('vision'),

  /// General caller-managed input.
  userData('user_data'),

  /// A newer purpose retained in raw JSON.
  unknown('unknown');

  const OpenAIFilePurpose(this.wireValue);

  /// Value sent on the wire.
  final String wireValue;
}

/// Deprecated native processing state retained for compatibility.
enum OpenAIFileStatus {
  /// Bytes reached OpenAI.
  uploaded,

  /// Processing completed.
  processed,

  /// Processing failed.
  error,

  /// A newer native status.
  unknown,
}

/// One caller-managed native file.
final class OpenAIFile {
  /// Decodes a native file object.
  factory OpenAIFile.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIFile._(
      id: _string(value, 'id'),
      bytes: _integer(value, 'bytes'),
      createdAt: _integer(value, 'created_at'),
      expiresAt: _optionalInteger(value, 'expires_at'),
      filename: _string(value, 'filename'),
      purpose: _purpose(_string(value, 'purpose')),
      status: _status(_string(value, 'status')),
      statusDetails: _optionalString(value, 'status_details'),
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
          'status',
          'status_details',
        }),
      ),
    );
  }

  OpenAIFile._({
    required this.id,
    required this.bytes,
    required this.createdAt,
    required this.expiresAt,
    required this.filename,
    required this.purpose,
    required this.status,
    required this.statusDetails,
    required this.raw,
    required this.extensions,
  });

  /// Provider file ID.
  final String id;

  /// File size in bytes.
  final int bytes;

  /// Unix creation timestamp.
  final int createdAt;

  /// Unix expiration timestamp, when any.
  final int? expiresAt;

  /// Uploaded filename.
  final String filename;

  /// Declared purpose.
  final OpenAIFilePurpose purpose;

  /// Deprecated native processing status.
  final OpenAIFileStatus status;

  /// Deprecated native status details.
  final String? statusDetails;

  /// Complete native object.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;

  /// Creates an explicit reference accepted by this provider's Responses API.
  ProviderFileSource asResponseSource({required String mimeType}) => ProviderFileSource(
    providerId: 'openai',
    api: 'responses',
    reference: id,
    mimeType: mimeType,
  );
}

/// One explicitly fetched file page.
final class OpenAIFilePage {
  /// Decodes a native page.
  factory OpenAIFilePage.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIFilePage._(
      data: _list(value, 'data').map((item) => OpenAIFile.fromJson(JsonObject.fromDart(item))),
      firstId: _string(value, 'first_id'),
      lastId: _string(value, 'last_id'),
      hasMore: _boolean(value, 'has_more'),
      raw: raw,
      extensions: JsonObject(
        _without(value, {'object', 'data', 'first_id', 'last_id', 'has_more'}),
      ),
    );
  }

  OpenAIFilePage._({
    required Iterable<OpenAIFile> data,
    required this.firstId,
    required this.lastId,
    required this.hasMore,
    required this.raw,
    required this.extensions,
  }) : data = List.unmodifiable(data);

  /// Files in this page.
  final List<OpenAIFile> data;

  /// First file ID.
  final String firstId;

  /// Last file ID.
  final String lastId;

  /// Whether another page can be requested.
  final bool hasMore;

  /// Complete native page.
  final JsonObject raw;

  /// Fields outside the typed snapshot.
  final JsonObject extensions;
}

/// One explicit file deletion acknowledgement.
final class OpenAIDeletedFile {
  /// Decodes a deletion acknowledgement.
  factory OpenAIDeletedFile.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return OpenAIDeletedFile._(
      id: _string(value, 'id'),
      deleted: _boolean(value, 'deleted'),
      raw: raw,
      extensions: JsonObject(_without(value, {'id', 'object', 'deleted'})),
    );
  }

  OpenAIDeletedFile._({
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

OpenAIFilePurpose _purpose(String value) => OpenAIFilePurpose.values.firstWhere(
  (purpose) => purpose.wireValue == value,
  orElse: () => OpenAIFilePurpose.unknown,
);

OpenAIFileStatus _status(String value) => switch (value) {
  'uploaded' => OpenAIFileStatus.uploaded,
  'processed' => OpenAIFileStatus.processed,
  'error' => OpenAIFileStatus.error,
  _ => OpenAIFileStatus.unknown,
};

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

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

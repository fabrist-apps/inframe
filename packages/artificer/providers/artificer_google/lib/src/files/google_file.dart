import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';

/// Native processing state of a Google Files resource.
final class GoogleFileState {
  const GoogleFileState._(this.value, this.isKnown);

  /// Decodes a state while retaining values added after the pinned snapshot.
  factory GoogleFileState.fromJson(String value) => switch (value) {
    'STATE_UNSPECIFIED' => unspecified,
    'PROCESSING' => processing,
    'ACTIVE' => active,
    'FAILED' => failed,
    _ => GoogleFileState._(value, false),
  };

  /// The API did not specify a state.
  static const unspecified = GoogleFileState._('STATE_UNSPECIFIED', true);

  /// The file is still being processed.
  static const processing = GoogleFileState._('PROCESSING', true);

  /// The file is ready for inference.
  static const active = GoogleFileState._('ACTIVE', true);

  /// File processing failed.
  static const failed = GoogleFileState._('FAILED', true);

  /// Exact native enum value.
  final String value;

  /// Whether [value] was present in the 2026-09-12 Files snapshot.
  final bool isKnown;

  @override
  String toString() => 'GoogleFileState($value)';
}

/// Native origin of a Google Files resource.
final class GoogleFileSource {
  const GoogleFileSource._(this.value, this.isKnown);

  /// Decodes a source while retaining values added after the pinned snapshot.
  factory GoogleFileSource.fromJson(String value) => switch (value) {
    'SOURCE_UNSPECIFIED' => unspecified,
    'UPLOADED' => uploaded,
    'GENERATED' => generated,
    'REGISTERED' => registered,
    _ => GoogleFileSource._(value, false),
  };

  /// The API did not specify a source.
  static const unspecified = GoogleFileSource._('SOURCE_UNSPECIFIED', true);

  /// The caller uploaded the file.
  static const uploaded = GoogleFileSource._('UPLOADED', true);

  /// Google generated the file.
  static const generated = GoogleFileSource._('GENERATED', true);

  /// The resource refers to a registered Google Cloud Storage file.
  static const registered = GoogleFileSource._('REGISTERED', true);

  /// Exact native enum value.
  final String value;

  /// Whether [value] was present in the 2026-09-12 Files snapshot.
  final bool isKnown;
}

/// Native `google.rpc.Status` attached to a failed file.
final class GoogleFileError {
  GoogleFileError._({
    required this.code,
    required this.message,
    required this.details,
    required this.extensions,
    required this.raw,
  });

  /// Decodes a status while retaining unknown fields and detail objects.
  factory GoogleFileError.fromJson(JsonObject json) {
    final value = json.toDart();
    final details = value['details'];
    if (details != null && details is! List<Object?>) {
      throw const FormatException('error.details must be an array.');
    }
    return GoogleFileError._(
      code: _optionalInt(value, 'code'),
      message: _optionalString(value, 'message'),
      details: List.unmodifiable(
        (details as List<Object?>? ?? const []).map(JsonValue.fromDart),
      ),
      extensions: JsonObject(_without(value, {'code', 'message', 'details'})),
      raw: json,
    );
  }

  /// Canonical status code.
  final int? code;

  /// Developer-facing status message.
  final String? message;

  /// Immutable native detail values.
  final List<JsonValue> details;

  /// Fields outside the pinned status snapshot.
  final JsonObject extensions;

  /// Complete native status payload.
  final JsonObject raw;
}

/// Native video metadata attached to a Google file.
final class GoogleVideoFileMetadata {
  GoogleVideoFileMetadata._({
    required this.videoDuration,
    required this.extensions,
    required this.raw,
  });

  /// Decodes the 2026-09-12 video metadata snapshot.
  factory GoogleVideoFileMetadata.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleVideoFileMetadata._(
      videoDuration: _optionalString(value, 'videoDuration'),
      extensions: JsonObject(_without(value, {'videoDuration'})),
      raw: json,
    );
  }

  /// Protobuf duration string for the video.
  final String? videoDuration;

  /// Fields outside the pinned metadata snapshot.
  final JsonObject extensions;

  /// Complete native metadata payload.
  final JsonObject raw;
}

/// One file uploaded to or managed by the Gemini Developer API.
final class GoogleFile {
  GoogleFile._({
    required this.name,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
    required this.createTime,
    required this.updateTime,
    required this.expirationTime,
    required this.sha256Hash,
    required this.uri,
    required this.downloadUri,
    required this.state,
    required this.source,
    required this.error,
    required this.videoMetadata,
    required this.extensions,
    required this.raw,
  });

  /// Decodes the official Files schema snapshot from 2026-09-12.
  factory GoogleFile.fromJson(JsonObject json) {
    final value = json.toDart();
    final sizeBytes = _optionalString(value, 'sizeBytes');
    if (sizeBytes != null && int.tryParse(sizeBytes) == null) {
      throw const FormatException('sizeBytes must be an int64 string.');
    }
    final error = value['error'];
    if (error != null && error is! Map<String, Object?>) {
      throw const FormatException('error must be an object.');
    }
    final videoMetadata = value['videoMetadata'];
    if (videoMetadata != null && videoMetadata is! Map<String, Object?>) {
      throw const FormatException('videoMetadata must be an object.');
    }
    final state = _optionalString(value, 'state');
    final source = _optionalString(value, 'source');
    return GoogleFile._(
      name: _fileName(_requiredString(value, 'name')),
      displayName: _optionalString(value, 'displayName'),
      mimeType: _optionalString(value, 'mimeType'),
      sizeBytes: sizeBytes == null ? null : int.parse(sizeBytes),
      createTime: _optionalString(value, 'createTime'),
      updateTime: _optionalString(value, 'updateTime'),
      expirationTime: _optionalString(value, 'expirationTime'),
      sha256Hash: _optionalString(value, 'sha256Hash'),
      uri: _optionalString(value, 'uri'),
      downloadUri: _optionalString(value, 'downloadUri'),
      state: state == null ? null : GoogleFileState.fromJson(state),
      source: source == null ? null : GoogleFileSource.fromJson(source),
      error: error is Map<String, Object?> ? GoogleFileError.fromJson(JsonObject(error)) : null,
      videoMetadata: videoMetadata is Map<String, Object?>
          ? GoogleVideoFileMetadata.fromJson(JsonObject(videoMetadata))
          : null,
      extensions: JsonObject(
        _without(value, {
          'name',
          'displayName',
          'mimeType',
          'sizeBytes',
          'createTime',
          'updateTime',
          'expirationTime',
          'sha256Hash',
          'uri',
          'downloadUri',
          'state',
          'source',
          'error',
          'videoMetadata',
        }),
      ),
      raw: json,
    );
  }

  /// Authoritative `files/{id}` resource name.
  final String name;

  /// Human-readable display name.
  final String? displayName;

  /// Media MIME type reported by Google.
  final String? mimeType;

  /// File length decoded from Google's int64 string.
  final int? sizeBytes;

  /// RFC 3339 creation timestamp as returned by Google.
  final String? createTime;

  /// RFC 3339 update timestamp as returned by Google.
  final String? updateTime;

  /// RFC 3339 automatic deletion timestamp, when scheduled.
  final String? expirationTime;

  /// Base64-encoded SHA-256 digest.
  final String? sha256Hash;

  /// URI accepted by Gemini file-data parts.
  final String? uri;

  /// Download URI, when supplied by Google.
  final String? downloadUri;

  /// Processing state, with unknown values retained.
  final GoogleFileState? state;

  /// Native file origin, with unknown values retained.
  final GoogleFileSource? source;

  /// Processing error for a failed file.
  final GoogleFileError? error;

  /// Video metadata when this is a video file.
  final GoogleVideoFileMetadata? videoMetadata;

  /// File fields outside the pinned snapshot.
  final JsonObject extensions;

  /// Complete native file payload.
  final JsonObject raw;

  /// Creates a common media source for a generation or embedding input.
  ///
  /// Google must have returned both [uri] and [mimeType].
  ProviderFileSource asMediaSource() {
    final fileUri = uri;
    final type = mimeType;
    if (fileUri == null || type == null) {
      throw StateError('A Google file reference requires both uri and mimeType.');
    }
    return ProviderFileSource(
      providerId: 'google',
      api: 'files',
      reference: fileUri,
      mimeType: type,
    );
  }
}

/// One explicitly requested page of Google files.
final class GoogleFilePage {
  GoogleFilePage._({
    required this.files,
    required this.nextPageToken,
    required this.extensions,
    required this.raw,
  });

  /// Decodes a file page while retaining unknown page fields.
  factory GoogleFilePage.fromJson(JsonObject json) {
    final value = json.toDart();
    final files = value['files'];
    if (files != null && files is! List<Object?>) {
      throw const FormatException('files must be an array.');
    }
    final pageFiles = files as List<Object?>? ?? const [];
    if (pageFiles.any((file) => file is! Map<String, Object?>)) {
      throw const FormatException('files must contain objects.');
    }
    return GoogleFilePage._(
      files: List.unmodifiable(
        pageFiles.cast<Map<String, Object?>>().map(
          (file) => GoogleFile.fromJson(JsonObject(file)),
        ),
      ),
      nextPageToken: _optionalString(value, 'nextPageToken'),
      extensions: JsonObject(_without(value, {'files', 'nextPageToken'})),
      raw: json,
    );
  }

  /// Files returned on this page.
  final List<GoogleFile> files;

  /// Explicit cursor for a caller-selected next request.
  final String? nextPageToken;

  /// Page fields outside the pinned snapshot.
  final JsonObject extensions;

  /// Complete native page payload.
  final JsonObject raw;
}

String _requiredString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

String _fileName(String name) {
  if (!name.startsWith('files/') || name.length == 6 || name.substring(6).contains('/')) {
    throw const FormatException('name must have the format files/{id}.');
  }
  return name;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

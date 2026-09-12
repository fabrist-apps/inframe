import 'package:artificer_core/json.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:artificer_google/src/generate_content/tool_models.dart';

/// An explicit request to create immutable cached inference content.
final class GoogleCreateCachedContentRequest {
  /// Creates a request pinned to the 2026-09-12 CachedContent schema.
  GoogleCreateCachedContentRequest({
    required String model,
    Iterable<GoogleContent> contents = const [],
    Iterable<GoogleToolDefinition> tools = const [],
    this.systemInstruction,
    this.toolConfig,
    this.displayName,
    this.ttl,
    this.expireTime,
  }) : model = _modelName(model),
       contents = List.unmodifiable(contents),
       tools = List.unmodifiable(tools) {
    _expiration(ttl, expireTime, requireOne: false);
    if (displayName != null && displayName!.runes.length > 128) {
      throw ArgumentError.value(displayName, 'displayName', 'must be at most 128 characters');
    }
  }

  /// Authoritative `models/{id}` resource name.
  final String model;

  /// Ordered immutable content stored in the cache.
  final List<GoogleContent> contents;

  /// Immutable native tools stored in the cache.
  final List<GoogleToolDefinition> tools;

  /// Immutable system instruction.
  final GoogleContent? systemInstruction;

  /// Immutable native tool configuration.
  final GoogleToolConfig? toolConfig;

  /// Caller-readable cache label.
  final String? displayName;

  /// Protobuf duration used for the initial expiration.
  final String? ttl;

  /// RFC 3339 timestamp used for the initial expiration.
  final String? expireTime;

  /// Encodes the native create body.
  JsonObject toJson() => JsonObject({
    'model': model,
    if (contents.isNotEmpty)
      'contents': contents.map((content) => content.toJson().toDart()).toList(),
    if (tools.isNotEmpty) 'tools': tools.map((tool) => tool.toJson().toDart()).toList(),
    if (systemInstruction case final value?) 'systemInstruction': value.toJson().toDart(),
    if (toolConfig case final value?) 'toolConfig': value.toJson().toDart(),
    'displayName': ?displayName,
    'ttl': ?ttl,
    'expireTime': ?expireTime,
  });
}

/// An expiration-only update for an existing cached-content resource.
final class GoogleCachedContentExpirationUpdate {
  /// Creates an update containing exactly one native expiration field.
  GoogleCachedContentExpirationUpdate({this.ttl, this.expireTime}) {
    _expiration(ttl, expireTime, requireOne: true);
  }

  /// Protobuf duration replacement.
  final String? ttl;

  /// RFC 3339 expiration timestamp replacement.
  final String? expireTime;

  /// Field-mask path derived from the chosen union member.
  String get updateMask => ttl == null ? 'expireTime' : 'ttl';

  /// Encodes only the chosen expiration field.
  JsonObject toJson() => JsonObject({'ttl': ?ttl, 'expireTime': ?expireTime});
}

/// Token usage recorded for cached content.
final class GoogleCachedContentUsageMetadata {
  GoogleCachedContentUsageMetadata._({
    required this.totalTokenCount,
    required this.extensions,
    required this.raw,
  });

  /// Decodes cache usage while retaining future fields.
  factory GoogleCachedContentUsageMetadata.fromJson(JsonObject json) {
    final value = json.toDart();
    return GoogleCachedContentUsageMetadata._(
      totalTokenCount: _optionalInt(value, 'totalTokenCount'),
      extensions: JsonObject(_without(value, {'totalTokenCount'})),
      raw: json,
    );
  }

  /// Total tokens stored by the cache.
  final int? totalTokenCount;

  /// Fields outside the pinned snapshot.
  final JsonObject extensions;

  /// Complete native usage payload.
  final JsonObject raw;
}

/// Metadata for one explicit Gemini cached-content resource.
final class GoogleCachedContent {
  GoogleCachedContent._({
    required this.name,
    required this.model,
    required this.displayName,
    required this.createTime,
    required this.updateTime,
    required this.expireTime,
    required this.usageMetadata,
    required this.contents,
    required this.tools,
    required this.systemInstruction,
    required this.toolConfig,
    required this.extensions,
    required this.raw,
  });

  /// Decodes the official CachedContent schema snapshot from 2026-09-12.
  factory GoogleCachedContent.fromJson(JsonObject json) {
    final value = json.toDart();
    final contents = _optionalList(value, 'contents');
    final tools = _optionalList(value, 'tools');
    return GoogleCachedContent._(
      name: _decodedCacheName(_requiredString(value, 'name')),
      model: _decodedModelName(_requiredString(value, 'model')),
      displayName: _optionalString(value, 'displayName'),
      createTime: _optionalString(value, 'createTime'),
      updateTime: _optionalString(value, 'updateTime'),
      expireTime: _optionalString(value, 'expireTime'),
      usageMetadata: switch (value['usageMetadata']) {
        null => null,
        final Map<String, Object?> usage => GoogleCachedContentUsageMetadata.fromJson(
          JsonObject(usage),
        ),
        _ => throw const FormatException('usageMetadata must be an object.'),
      },
      contents: List.unmodifiable(
        contents.map((content) => GoogleContent.fromJson(JsonObject.fromDart(content))),
      ),
      tools: List.unmodifiable(tools.map(JsonObject.fromDart)),
      systemInstruction: switch (value['systemInstruction']) {
        null => null,
        final Map<String, Object?> instruction => GoogleContent.fromJson(JsonObject(instruction)),
        _ => throw const FormatException('systemInstruction must be an object.'),
      },
      toolConfig: switch (value['toolConfig']) {
        null => null,
        final Map<String, Object?> config => JsonObject(config),
        _ => throw const FormatException('toolConfig must be an object.'),
      },
      extensions: JsonObject(
        _without(value, {
          'name',
          'model',
          'displayName',
          'createTime',
          'updateTime',
          'expireTime',
          'ttl',
          'usageMetadata',
          'contents',
          'tools',
          'systemInstruction',
          'toolConfig',
        }),
      ),
      raw: json,
    );
  }

  /// Authoritative `cachedContents/{id}` resource name.
  final String name;

  /// Authoritative model resource name.
  final String model;

  /// Caller-readable cache label.
  final String? displayName;

  /// RFC 3339 creation time.
  final String? createTime;

  /// RFC 3339 last-update time.
  final String? updateTime;

  /// RFC 3339 expiration time returned by Google.
  final String? expireTime;

  /// Token usage recorded for the cached content.
  final GoogleCachedContentUsageMetadata? usageMetadata;

  /// Input-only content when present in a native response fixture.
  final List<GoogleContent> contents;

  /// Input-only native tool objects when present in a response fixture.
  final List<JsonObject> tools;

  /// Input-only system instruction when present in a response fixture.
  final GoogleContent? systemInstruction;

  /// Input-only tool configuration when present in a response fixture.
  final JsonObject? toolConfig;

  /// Fields outside the pinned snapshot.
  final JsonObject extensions;

  /// Complete native cache payload.
  final JsonObject raw;
}

/// One explicitly fetched page of cached-content metadata.
final class GoogleCachedContentPage {
  GoogleCachedContentPage._({
    required this.cachedContents,
    required this.nextPageToken,
    required this.extensions,
    required this.raw,
  });

  /// Decodes one page without following its cursor.
  factory GoogleCachedContentPage.fromJson(JsonObject json) {
    final value = json.toDart();
    final items = _optionalList(value, 'cachedContents');
    return GoogleCachedContentPage._(
      cachedContents: List.unmodifiable(
        items.map((item) => GoogleCachedContent.fromJson(JsonObject.fromDart(item))),
      ),
      nextPageToken: _optionalString(value, 'nextPageToken'),
      extensions: JsonObject(_without(value, {'cachedContents', 'nextPageToken'})),
      raw: json,
    );
  }

  /// Cache metadata in native order.
  final List<GoogleCachedContent> cachedContents;

  /// Explicit cursor for a caller-selected next request.
  final String? nextPageToken;

  /// Fields outside the pinned snapshot.
  final JsonObject extensions;

  /// Complete native page payload.
  final JsonObject raw;
}

void _expiration(String? ttl, String? expireTime, {required bool requireOne}) {
  if ((ttl == null) == (expireTime == null)) {
    if (!requireOne && ttl == null) return;
    throw ArgumentError('Exactly one of ttl or expireTime must be supplied.');
  }
  if (ttl != null && !RegExp(r'^\d+(?:\.\d{1,9})?s$').hasMatch(ttl)) {
    throw ArgumentError.value(ttl, 'ttl', 'must be a nonnegative protobuf duration');
  }
  if (expireTime != null &&
      (!RegExp(r'(?:Z|[+-]\d\d:\d\d)$').hasMatch(expireTime) ||
          DateTime.tryParse(expireTime) == null)) {
    throw ArgumentError.value(expireTime, 'expireTime', 'must be an RFC 3339 timestamp');
  }
}

String _decodedCacheName(String value) {
  if (!_isCacheName(value)) {
    throw const FormatException('name must have the format cachedContents/{id}.');
  }
  return value;
}

bool _isCacheName(String value) =>
    value.startsWith('cachedContents/') &&
    value.length > 'cachedContents/'.length &&
    !value.substring('cachedContents/'.length).contains('/');

String _modelName(String value) {
  if (!_isModelName(value)) {
    throw ArgumentError.value(value, 'model', 'must have the format models/{id}');
  }
  return value;
}

String _decodedModelName(String value) {
  if (!_isModelName(value)) {
    throw const FormatException('model must have the format models/{id}.');
  }
  return value;
}

bool _isModelName(String value) =>
    value.startsWith('models/') &&
    value.length > 'models/'.length &&
    !value.substring('models/'.length).contains('/');

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

List<Object?> _optionalList(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return const [];
  if (field is! List<Object?>) throw FormatException('$key must be an array.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> keys) =>
    Map.fromEntries(value.entries.where((entry) => !keys.contains(entry.key)));

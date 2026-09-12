import 'package:artificer_core/src/json/json_value.dart';

/// Complete native JSON retained beside a normalized result.
final class NativePayload {
  /// Creates a [NativePayload].
  NativePayload({
    required String providerId,
    required String api,
    required String modelId,
    required JsonValue json,
  }) : providerId = _nonEmpty(providerId, 'providerId'),
       api = _nonEmpty(api, 'api'),
       modelId = _nonEmpty(modelId, 'modelId'),
       _value = json;

  /// Deserializes and validates a schema-versioned value.
  factory NativePayload.fromJson(JsonObject json) {
    final value = json.toDart();
    _requireVersion(value);
    return NativePayload(
      providerId: _requiredString(value, 'providerId'),
      api: _requiredString(value, 'api'),
      modelId: _requiredString(value, 'modelId'),
      json: JsonValue.fromDart(value['json']),
    );
  }

  /// The stable provider identifier used in diagnostics and replay data.
  final String providerId;

  /// The native API or dialect identifier.
  final String api;

  /// The provider-local model identifier.
  final String modelId;

  final JsonValue _value;

  /// The immutable native JSON value.
  JsonValue get value => _value;

  /// The immutable native JSON object for object-based APIs.
  ///
  /// Use [value] for APIs whose response root can also be an array or scalar.
  JsonObject get json {
    final value = _value;
    if (value is! JsonObject) {
      throw StateError('This native payload does not contain a JSON object.');
    }
    return value;
  }

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'providerId': providerId,
    'api': api,
    'modelId': modelId,
    'json': _value.toDart(),
  });
}

/// HTTP metadata safe for explicit inspection.
final class ResponseMetadata {
  /// Creates a [ResponseMetadata].
  ResponseMetadata({
    required this.statusCode,
    this.requestId,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);

  /// Deserializes and validates a schema-versioned value.
  factory ResponseMetadata.fromJson(JsonObject json) {
    final value = json.toDart();
    _requireVersion(value);
    final headers = value['headers'];
    if (headers is! Map<String, Object?>) {
      throw const FormatException('headers must be an object.');
    }
    return ResponseMetadata(
      statusCode: _requiredInt(value, 'statusCode'),
      requestId: value['requestId'] as String?,
      headers: headers.map((key, value) {
        if (value is! String) throw const FormatException('header values must be strings.');
        return MapEntry(key, value);
      }),
    );
  }

  /// The HTTP status code, when available.
  final int statusCode;

  /// The provider request identifier, when available.
  final String? requestId;

  /// The immutable response headers.
  final Map<String, String> headers;

  /// Serializes this value using schema version 1.
  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'statusCode': statusCode,
    'requestId': ?requestId,
    'headers': headers,
  });

  @override
  String toString() => 'ResponseMetadata(statusCode: $statusCode, requestId: $requestId)';
}

/// A decoded native value together with its raw payload and HTTP metadata.
final class NativeResponse<T> {
  /// Creates a [NativeResponse].
  const NativeResponse({
    required this.value,
    required this.payload,
    required this.metadata,
  });

  /// The typed value.
  final T value;

  /// The retained native JSON payload.
  final NativePayload payload;

  /// The HTTP response metadata.
  final ResponseMetadata metadata;
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}

void _requireVersion(Map<String, Object?> value) {
  if (value['schemaVersion'] != 1) {
    throw FormatException('Unsupported schema version: ${value['schemaVersion']}');
  }
}

String _requiredString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int _requiredInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

import 'json/json_value.dart';

/// Complete native JSON retained beside a normalized result.
final class NativePayload {
  NativePayload({
    required String providerId,
    required String api,
    required String modelId,
    required this.json,
  }) : providerId = _nonEmpty(providerId, 'providerId'),
       api = _nonEmpty(api, 'api'),
       modelId = _nonEmpty(modelId, 'modelId');

  final String providerId;
  final String api;
  final String modelId;
  final JsonObject json;

  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'providerId': providerId,
    'api': api,
    'modelId': modelId,
    'json': json.toDart(),
  });

  static NativePayload fromJson(JsonObject json) {
    final value = json.toDart();
    _requireVersion(value);
    return NativePayload(
      providerId: _requiredString(value, 'providerId'),
      api: _requiredString(value, 'api'),
      modelId: _requiredString(value, 'modelId'),
      json: JsonObject.fromDart(value['json']),
    );
  }
}

/// HTTP metadata safe for explicit inspection.
final class ResponseMetadata {
  ResponseMetadata({
    required this.statusCode,
    this.requestId,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);

  final int statusCode;
  final String? requestId;
  final Map<String, String> headers;

  JsonObject toJson() => JsonObject({
    'schemaVersion': 1,
    'statusCode': statusCode,
    if (requestId case final requestId?) 'requestId': requestId,
    'headers': headers,
  });

  static ResponseMetadata fromJson(JsonObject json) {
    final value = json.toDart();
    _requireVersion(value);
    final headers = value['headers'];
    if (headers is! Map<String, Object?>) {
      throw const FormatException('headers must be an object.');
    }
    return ResponseMetadata(
      statusCode: value['statusCode'] as int,
      requestId: value['requestId'] as String?,
      headers: headers.map((key, value) {
        if (value is! String) throw const FormatException('header values must be strings.');
        return MapEntry(key, value);
      }),
    );
  }

  @override
  String toString() => 'ResponseMetadata(statusCode: $statusCode, requestId: $requestId)';
}

/// A decoded native value together with its raw payload and HTTP metadata.
final class NativeResponse<T> {
  const NativeResponse({
    required this.value,
    required this.payload,
    required this.metadata,
  });

  final T value;
  final NativePayload payload;
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

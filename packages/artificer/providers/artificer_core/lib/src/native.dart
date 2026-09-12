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

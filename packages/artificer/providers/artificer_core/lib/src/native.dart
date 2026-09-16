import 'package:artificer_core/src/json/json_value_hook.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'native.mapper.dart';

/// HTTP metadata retained for explicit inspection, never diagnostic logging.
@MappableClass()
final class ResponseMetadata with ResponseMetadataMappable {
  /// Creates a [ResponseMetadata] retaining the supplied values.
  const ResponseMetadata({required this.statusCode, this.requestId, this.headers = const {}});

  /// HTTP status when a response began.
  final int statusCode;

  /// Provider request identifier when supplied.
  final String? requestId;

  /// Raw response headers; never included in default diagnostics.
  final Map<String, List<String>> headers;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = ResponseMetadataMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = ResponseMetadataMapper.fromJson;
}

/// Complete provider JSON and the target that produced it.
@MappableClass()
final class NativePayload with NativePayloadMappable {
  /// Creates a [NativePayload] retaining the supplied values.
  const NativePayload({
    required this.providerId,
    required this.api,
    required this.modelId,
    required this.data,
    this.unknownEvents = const [],
  });

  /// Stable provider identity.
  final String providerId;

  /// API or dialect identity.
  final String api;

  /// Nonempty provider-local model identifier.
  final String modelId;

  /// Complete JSON value, including unknown nested fields.
  @MappableField(hook: JsonValueHook())
  final Object? data;

  /// Unknown stream records retained separately from the assembled native response.
  @MappableField(hook: JsonValueHook())
  final List<Map<String, Object?>> unknownEvents;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = NativePayloadMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = NativePayloadMapper.fromJson;
}

/// Typed and complete raw views of the same inference response.
@MappableClass()
final class NativeResponse<T> with NativeResponseMappable<T> {
  /// Creates a [NativeResponse] retaining the supplied values.
  const NativeResponse({required this.value, required this.raw, required this.metadata});

  /// Typed view of the native response.
  final T value;

  /// Full JSON paired with the typed view.
  final NativePayload raw;

  /// HTTP response metadata for explicit inspection.
  final ResponseMetadata metadata;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = NativeResponseMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = NativeResponseMapper.fromJson;
}

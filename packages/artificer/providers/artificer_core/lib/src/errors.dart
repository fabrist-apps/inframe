import 'package:dart_mappable/dart_mappable.dart';

part 'errors.mapper.dart';

/// Conservative delivery state; it is never a retry recommendation.
@MappableEnum()
enum DeliveryState {
  /// Not sent.
  notSent,

  /// May have reached provider.
  mayHaveReachedProvider,

  /// Response started.
  responseStarted,
}

/// Expected provider failure data. Diagnostic strings deliberately omit payloads.
@MappableClass(
  discriminatorKey: 'type',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
sealed class AiError with AiErrorMappable {
  /// Creates a [AiError] retaining the supplied values.
  const AiError(this.message);

  /// Human-readable detail, available only through explicit inspection.
  final String message;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = AiErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = AiErrorMapper.fromJson;
  @override
  String toString() => 'AiError';
}

/// InvalidRequest failure with inspectable details.
@MappableClass(
  discriminatorValue: 'InvalidRequestError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class InvalidRequestError extends AiError with InvalidRequestErrorMappable {
  /// Creates a [InvalidRequestError] retaining the supplied values.
  const InvalidRequestError(super.message);

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = InvalidRequestErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = InvalidRequestErrorMapper.fromJson;
}

/// UnsupportedFeature failure with inspectable details.
@MappableClass(
  discriminatorValue: 'UnsupportedFeatureError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class UnsupportedFeatureError extends AiError with UnsupportedFeatureErrorMappable {
  /// Creates a [UnsupportedFeatureError] retaining the supplied values.
  const UnsupportedFeatureError(super.message, {this.feature});

  /// Feature.
  final String? feature;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = UnsupportedFeatureErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = UnsupportedFeatureErrorMapper.fromJson;
}

/// Provider failure with inspectable details.
@MappableClass(
  discriminatorValue: 'ProviderError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ProviderError extends AiError with ProviderErrorMappable {
  /// Creates a [ProviderError] retaining the supplied values.
  const ProviderError(
    super.message, {
    this.statusCode,
    this.code,
    this.details,
    this.requestId,
    this.retryAfter,
    this.partialOutput,
  });

  /// HTTP status when a response began.
  final int? statusCode;

  /// Code.
  final String? code;

  /// Complete native error details, including unknown fields.
  final Object? details;

  /// Provider request identifier when supplied.
  final String? requestId;

  /// Unmodified Retry-After header value.
  final String? retryAfter;

  /// Output received before failure, when available.
  final Object? partialOutput;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = ProviderErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = ProviderErrorMapper.fromJson;
}

/// Transport failure with inspectable details.
@MappableClass(
  discriminatorValue: 'TransportError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class TransportError extends AiError with TransportErrorMappable {
  /// Creates a [TransportError] retaining the supplied values.
  const TransportError(super.message, {this.deliveryState = DeliveryState.notSent});

  /// Conservative delivery state observed at failure.
  final DeliveryState deliveryState;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = TransportErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = TransportErrorMapper.fromJson;
}

/// Protocol failure with inspectable details.
@MappableClass(
  discriminatorValue: 'ProtocolError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ProtocolError extends AiError with ProtocolErrorMappable {
  /// Creates a [ProtocolError] retaining the supplied values.
  const ProtocolError(super.message, {this.partialOutput});

  /// Output received before failure, when available.
  final Object? partialOutput;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = ProtocolErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = ProtocolErrorMapper.fromJson;
}

/// ResponseLimit failure with inspectable details.
@MappableClass(
  discriminatorValue: 'ResponseLimitError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ResponseLimitError extends AiError with ResponseLimitErrorMappable {
  /// Creates a [ResponseLimitError] retaining the supplied values.
  const ResponseLimitError(super.message, {this.limit, this.partialOutput});

  /// Limit.
  final int? limit;

  /// Output received before failure, when available.
  final Object? partialOutput;

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = ResponseLimitErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = ResponseLimitErrorMapper.fromJson;
}

/// Work attempted after provider shutdown began.
@MappableClass(
  discriminatorValue: 'ClientClosedError',
  generateMethods: GenerateMethods.encode | GenerateMethods.decode,
)
final class ClientClosedError extends AiError with ClientClosedErrorMappable {
  /// Creates a [ClientClosedError] retaining the supplied values.
  const ClientClosedError([super.message = 'Provider client is closed.']);

  /// Decodes a map using the shipped generated mapper.
  static const fromMap = ClientClosedErrorMapper.fromMap;

  /// Decodes a JSON string using the shipped generated mapper.
  static const fromJson = ClientClosedErrorMapper.fromJson;
}

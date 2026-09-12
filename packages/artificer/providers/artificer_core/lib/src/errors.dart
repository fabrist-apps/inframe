import 'package:artificer_core/src/json/json_value.dart';

/// A typed failure expected while preparing or executing an AI operation.
sealed class AiError implements Exception {
  const AiError(this.message);

  /// The human-readable failure or result message.
  final String message;

  @override
  String toString() =>
      '${switch (this) {
        InvalidRequestError() => 'InvalidRequestError',
        UnsupportedFeatureError() => 'UnsupportedFeatureError',
        ProviderError() => 'ProviderError',
        TransportError() => 'TransportError',
        ProtocolError() => 'ProtocolError',
        ResponseLimitError() => 'ResponseLimitError',
        ClientClosedError() => 'ClientClosedError',
      }}: $message';
}

/// The caller supplied an invalid request.
final class InvalidRequestError extends AiError {
  /// Creates an [InvalidRequestError].
  const InvalidRequestError(super.message, {this.remoteResourceId});

  /// The remote resource allocated before the failure, when known.
  final String? remoteResourceId;
}

/// The selected model is known not to support a requested feature.
final class UnsupportedFeatureError extends AiError {
  /// Creates an [UnsupportedFeatureError].
  const UnsupportedFeatureError(super.message, {this.feature});

  /// The unsupported feature identifier, when known.
  final String? feature;
}

/// A service returned a native error response.
final class ProviderError extends AiError {
  /// Creates a [ProviderError].
  const ProviderError(
    super.message, {
    this.statusCode,
    this.code,
    this.details,
    this.requestId,
    this.retryAfter,
    this.rawRetryAfter,
    this.partialOutput,
    this.remoteResourceId,
  });

  /// The HTTP status code, when available.
  final int? statusCode;

  /// The native provider error code, when available.
  final String? code;

  /// The retained native error details, when available.
  final JsonValue? details;

  /// The provider request identifier, when available.
  final String? requestId;

  /// The parsed retry delay, when available.
  final Duration? retryAfter;

  /// The original Retry-After value when it could not be parsed.
  final String? rawRetryAfter;

  /// The immutable output assembled before the failure.
  final Object? partialOutput;

  /// The remote resource allocated before the failure, when known.
  final String? remoteResourceId;
}

/// How far an HTTP request may have progressed before transport failure.
enum RequestDeliveryState {
  /// No request bytes are known to have reached the provider.
  notSent,

  /// The request may have reached the provider before the failure.
  mayHaveReachedProvider,

  /// Response headers or body bytes arrived before the failure.
  responseStarted,
}

/// A network or HTTP client failure.
final class TransportError extends AiError {
  /// Creates a [TransportError].
  const TransportError(
    super.message, {
    required this.deliveryState,
    this.partialOutput,
    this.remoteResourceId,
  });

  /// The conservative request delivery state.
  final RequestDeliveryState deliveryState;

  /// The immutable output assembled before the failure.
  final Object? partialOutput;

  /// The remote resource allocated before the failure, when known.
  final String? remoteResourceId;
}

/// A native payload did not satisfy its protocol.
final class ProtocolError extends AiError {
  /// Creates a [ProtocolError].
  const ProtocolError(super.message, {this.partialOutput, this.remoteResourceId});

  /// The immutable output assembled before the failure.
  final Object? partialOutput;

  /// The remote resource allocated before the failure, when known.
  final String? remoteResourceId;
}

/// A configured response or event byte limit was exceeded.
final class ResponseLimitError extends AiError {
  /// Creates a [ResponseLimitError].
  const ResponseLimitError(
    super.message, {
    required this.limit,
    required this.actual,
    this.partialOutput,
    this.remoteResourceId,
  });

  /// The configured byte limit.
  final int limit;

  /// The observed byte count.
  final int actual;

  /// The immutable output assembled before the failure.
  final Object? partialOutput;

  /// The remote resource allocated before the failure, when known.
  final String? remoteResourceId;
}

/// A provider client is closing or closed.
final class ClientClosedError extends AiError {
  /// Creates a [ClientClosedError].
  const ClientClosedError() : super('The provider client is closed.');
}

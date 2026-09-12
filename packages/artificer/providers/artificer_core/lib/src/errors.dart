import 'json/json_value.dart';

/// A typed failure expected while preparing or executing an AI operation.
sealed class AiError {
  const AiError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The caller supplied an invalid request.
final class InvalidRequestError extends AiError {
  const InvalidRequestError(super.message, {this.remoteResourceId});

  final String? remoteResourceId;
}

/// The selected model is known not to support a requested feature.
final class UnsupportedFeatureError extends AiError {
  const UnsupportedFeatureError(super.message, {this.feature});

  final String? feature;
}

/// A service returned a native error response.
final class ProviderError extends AiError {
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

  final int? statusCode;
  final String? code;
  final JsonValue? details;
  final String? requestId;
  final Duration? retryAfter;
  final String? rawRetryAfter;
  final Object? partialOutput;
  final String? remoteResourceId;
}

/// How far an HTTP request may have progressed before transport failure.
enum RequestDeliveryState { notSent, mayHaveReachedProvider, responseStarted }

/// A network or HTTP client failure.
final class TransportError extends AiError {
  const TransportError(
    super.message, {
    required this.deliveryState,
    this.remoteResourceId,
  });

  final RequestDeliveryState deliveryState;
  final String? remoteResourceId;
}

/// A native payload did not satisfy its protocol.
final class ProtocolError extends AiError {
  const ProtocolError(super.message, {this.partialOutput, this.remoteResourceId});

  final Object? partialOutput;
  final String? remoteResourceId;
}

/// A configured response or event byte limit was exceeded.
final class ResponseLimitError extends AiError {
  const ResponseLimitError(
    super.message, {
    required this.limit,
    required this.actual,
    this.partialOutput,
    this.remoteResourceId,
  });

  final int limit;
  final int actual;
  final Object? partialOutput;
  final String? remoteResourceId;
}

/// A provider client is closing or closed.
final class ClientClosedError extends AiError {
  const ClientClosedError() : super('The provider client is closed.');
}

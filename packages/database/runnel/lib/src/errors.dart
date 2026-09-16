import 'package:conflux/option.dart';
import 'package:runnel/src/connection/legacy_errors.dart' show RedisDeliveryStatus;

export 'connection/legacy_errors.dart' show RedisDeliveryStatus;

/// Expected Runnel failures. Cancellation and unexpected defects use Conflux Cause.
sealed class RunnelError {
  const RunnelError(
    this.message, {
    this.deliveryStatus = const None(),
    this.cause,
    this.stackTrace,
  });

  /// Diagnostic detail with endpoint credentials removed.
  final String message;

  /// Applicable submission uncertainty; absent for a conclusive server reply.
  final Option<RedisDeliveryStatus> deliveryStatus;

  /// Original known failure and its captured stack, when available.
  final Object? cause;

  /// Stack captured where the underlying failure occurred.
  final StackTrace? stackTrace;

  @override
  String toString() => message;
}

/// Invalid configuration or command input.
final class RunnelInputError extends RunnelError {
  /// Creates this expected failure.
  const RunnelInputError(super.message, {super.cause, super.stackTrace})
    : super(deliveryStatus: const Some(RedisDeliveryStatus.notSent));
}

/// A socket connection failed.
final class RunnelTransportError extends RunnelError {
  /// Creates this expected failure.
  const RunnelTransportError(
    super.message, {
    required super.deliveryStatus,
    super.cause,
    super.stackTrace,
  });
}

/// The operation deadline expired.
final class RunnelTimeoutError extends RunnelError {
  /// Creates this expected failure.
  const RunnelTimeoutError(
    super.message, {
    required super.deliveryStatus,
    super.cause,
    super.stackTrace,
  });
}

/// Received bytes violated the RESP contract.
final class RunnelProtocolError extends RunnelError {
  /// Creates this expected failure.
  const RunnelProtocolError(
    super.message, {
    required super.deliveryStatus,
    super.cause,
    super.stackTrace,
  });
}

/// A configured resource bound was exceeded.
final class RunnelLimitError extends RunnelError {
  /// Creates this expected failure.
  const RunnelLimitError(
    super.message, {
    required this.limit,
    required super.deliveryStatus,
    super.cause,
    super.stackTrace,
  });

  /// Configured boundary exceeded by this operation.
  final int limit;
}

/// The resource no longer accepts work.
final class RunnelClosedError extends RunnelError {
  /// Creates this expected failure.
  const RunnelClosedError(
    super.message, {
    super.deliveryStatus = const Some(RedisDeliveryStatus.notSent),
    super.cause,
    super.stackTrace,
  });
}

/// Redis returned a conclusive error reply.
final class RunnelServerError extends RunnelError {
  /// Creates this expected failure.
  const RunnelServerError(super.message, {required this.code, super.cause, super.stackTrace});

  /// Redis error prefix, such as NOSCRIPT or NOAUTH.
  final String code;
}

/// A transaction could not produce command results.
final class RunnelTransactionError extends RunnelError {
  /// Creates this expected failure.
  const RunnelTransactionError(super.message, {super.cause, super.stackTrace});
}

/// A later subscription change superseded this operation.
final class RunnelSubscriptionError extends RunnelError {
  /// Creates this expected failure.
  const RunnelSubscriptionError(super.message, {super.cause, super.stackTrace});
}

/// A built-in reply shape or text encoding was invalid.
final class RunnelDecodingError extends RunnelError {
  /// Creates this expected failure.
  const RunnelDecodingError(super.message, {super.cause, super.stackTrace});
}

/// The operation conflicts with resource usage rules.
final class RunnelUsageError extends RunnelError {
  /// Creates this expected failure.
  const RunnelUsageError(super.message, {super.cause, super.stackTrace})
    : super(deliveryStatus: const Some(RedisDeliveryStatus.notSent));
}

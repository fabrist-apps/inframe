/// Whether an unsuccessful command could have reached Redis.
enum RedisDeliveryStatus {
  /// No bytes belonging to the command were submitted.
  notSent,

  /// Some or all command bytes were submitted without a conclusive reply.
  outcomeUnknown,
}

/// Stable categories for failures produced by Runnel.
enum RedisFailureCategory {
  /// Invalid client configuration or command input.
  configuration,

  /// Socket, DNS, or TLS transport failure.
  transport,

  /// Operation deadline expiry.
  timeout,

  /// Malformed or unsupported protocol data.
  protocol,

  /// Configured resource limit exceeded.
  resourceLimit,

  /// Work attempted after shutdown.
  closed,
}

/// Base class for client-side Runnel failures.
sealed class RunnelException implements Exception {
  const RunnelException({
    required this.message,
    required this.category,
    required this.deliveryStatus,
    this.cause,
  });

  /// Human-readable detail with credentials removed.
  final String message;

  /// Failure category, independent of delivery uncertainty.
  final RedisFailureCategory category;

  /// Whether command delivery can be ruled out.
  final RedisDeliveryStatus deliveryStatus;

  /// Underlying failure when one exists.
  final Object? cause;

  @override
  String toString() => message;
}

/// A transport connection failed or was interrupted.
final class RedisTransportException extends RunnelException {
  /// Creates a transport failure.
  const RedisTransportException({
    required super.message,
    required super.deliveryStatus,
    super.cause,
  }) : super(category: RedisFailureCategory.transport);
}

/// A client operation exceeded its deadline.
final class RedisTimeoutException extends RunnelException {
  /// Creates a deadline failure.
  const RedisTimeoutException({
    required super.message,
    required super.deliveryStatus,
    super.cause,
  }) : super(category: RedisFailureCategory.timeout);
}

/// Incoming bytes violated the RESP contract.
final class RedisProtocolException extends RunnelException {
  /// Creates a malformed-protocol failure.
  const RedisProtocolException({
    required super.message,
    super.cause,
    super.deliveryStatus = RedisDeliveryStatus.outcomeUnknown,
  }) : super(
         category: RedisFailureCategory.protocol,
       );
}

/// A connection or client has already closed.
final class RedisClosedException extends RunnelException {
  /// Creates a failure for work rejected after close.
  const RedisClosedException({
    required super.message,
    super.deliveryStatus = RedisDeliveryStatus.notSent,
  }) : super(category: RedisFailureCategory.closed);
}

/// A configured command or protocol resource budget was exceeded.
final class RedisLimitException extends RunnelException {
  /// Creates a resource-limit failure.
  const RedisLimitException({
    required super.message,
    required super.deliveryStatus,
    required this.limit,
  }) : super(category: RedisFailureCategory.resourceLimit);

  /// Boundary that the operation exceeded.
  final int limit;
}

/// A Redis error reply.
final class RedisServerException implements Exception {
  /// Creates an error returned by Redis.
  const RedisServerException({required this.code, required this.message});

  /// Redis error prefix, such as `ERR` or `NOAUTH`.
  final String code;

  /// Redis error detail without the prefix.
  final String message;

  @override
  String toString() => '$code $message';
}

/// A MULTI/EXEC transaction was rejected before it produced command results.
final class RedisTransactionException implements Exception {
  /// Creates a transaction-level rejection.
  const RedisTransactionException(this.message, {this.cause});

  /// Human-readable rejection detail.
  final String message;

  /// The underlying Redis or protocol failure when one exists.
  final Object? cause;

  @override
  String toString() => message;
}

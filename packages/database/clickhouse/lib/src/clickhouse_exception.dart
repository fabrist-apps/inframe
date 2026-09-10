/// Whether a failed request was definitely local or may have reached ClickHouse.
enum ClickHouseRequestState {
  /// The client established that no request bytes were transmitted.
  notSent,

  /// The server may have received some or all of the request.
  mayHaveReachedServer,
}

/// The direction in which a configured payload limit was exceeded.
enum ClickHouseSizeLimitDirection {
  /// The encoded request body was too large.
  request,

  /// The decompressed response body was too large.
  response,
}

/// Base class for failures reported by ClickHouse operations.
sealed class ClickHouseException implements Exception {
  const ClickHouseException({
    required this.message,
    required this.requestState,
    this.queryId,
  });

  /// Human-readable failure description.
  final String message;

  /// The query identifier returned by ClickHouse, when available.
  final String? queryId;

  /// Whether the operation may have reached ClickHouse.
  final ClickHouseRequestState requestState;

  @override
  String toString() => message;
}

/// A rejection or recognized error reported by ClickHouse.
final class ClickHouseServerException extends ClickHouseException {
  /// Creates an exception for a server-reported failure.
  const ClickHouseServerException({
    required super.message,
    required super.requestState,
    super.queryId,
    this.statusCode,
    this.clickHouseCode,
  });

  /// The HTTP response status, when a response was received.
  final int? statusCode;

  /// The ClickHouse error code parsed from the response, when available.
  final int? clickHouseCode;
}

/// A connection or response-transfer failure.
final class ClickHouseTransportException extends ClickHouseException {
  /// Creates an exception for an HTTP transport failure.
  const ClickHouseTransportException({
    required super.message,
    required super.requestState,
    required this.cause,
    super.queryId,
  });

  /// The transport failure reported by `dart:io`.
  final Object cause;
}

/// An operation whose deadline expired.
final class ClickHouseTimeoutException extends ClickHouseException {
  /// Creates an exception for an expired operation deadline.
  const ClickHouseTimeoutException({
    required super.message,
    required super.requestState,
    super.queryId,
  });
}

/// A response that did not satisfy the ClickHouse wire contract.
final class ClickHouseProtocolException extends ClickHouseException {
  /// Creates an exception for an invalid response.
  const ClickHouseProtocolException({
    required super.message,
    required super.requestState,
    super.queryId,
  });
}

/// A request or response that exceeded a configured byte limit.
final class ClickHouseSizeLimitException extends ClickHouseException {
  /// Creates an exception for an exceeded payload limit.
  const ClickHouseSizeLimitException({
    required super.message,
    required super.requestState,
    required this.direction,
    required this.limit,
    super.queryId,
  });

  /// Which payload exceeded its limit.
  final ClickHouseSizeLimitDirection direction;

  /// The configured maximum payload size in bytes.
  final int limit;
}

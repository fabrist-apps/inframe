import 'dart:io';

import 'package:inlet/src/request.dart';
import 'package:inlet/src/response.dart';

/// Maps expected client failures to 4xx and other failures to 500.
Response defaultErrorResponse(Object error) => switch (error) {
  WebSocketHandshakeRejected() => Response.empty(status: HttpStatus.badRequest),
  MalformedBodyException() => Response.empty(status: HttpStatus.badRequest),
  BodyLimitExceededException() => Response.empty(
    status: HttpStatus.requestEntityTooLarge,
  ),
  _ => Response.empty(status: HttpStatus.internalServerError),
};

/// Whether a failure needs reporting beyond the client response.
bool isUnexpected(Object error) =>
    error is! WebSocketHandshakeRejected &&
    error is! MalformedBodyException &&
    error is! BodyLimitExceededException;

/// Whether continuation validation already reported this failure.
bool wasReported(Object error) => error is ContinuationStateError && error.wasReported;

/// Invalid middleware continuation use with report deduplication.
final class ContinuationStateError extends StateError {
  /// Records whether the dispatch reporter has already observed the error.
  ContinuationStateError(super.message, {this.wasReported = false});

  /// Prevents reporting the same continuation violation during recovery.
  final bool wasReported;
}

/// A malformed upgrade request that can still receive a 400 response.
final class WebSocketHandshakeRejected extends WebSocketException {
  /// Describes the rejected handshake field or negotiation.
  const WebSocketHandshakeRejected(super.message);
}

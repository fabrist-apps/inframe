import 'dart:async';

import 'package:clickhouse/src/exception.dart';

/// Tracks the remaining time for one internal ClickHouse operation.
final class ClickHouseDeadline {
  /// Starts a deadline for [operation].
  ClickHouseDeadline(String operation, Duration timeout)
    : _operation = operation,
      _timeout = timeout,
      _stopwatch = (Stopwatch()..start());

  final String _operation;
  final Duration _timeout;
  final Stopwatch _stopwatch;

  /// Throws when no time remains for the operation.
  void check(ClickHouseRequestState requestState, {String? queryId}) {
    if (_stopwatch.elapsed >= _timeout) {
      throw timeoutException(requestState, queryId: queryId);
    }
  }

  /// Returns the remaining time or throws when the deadline has expired.
  Duration remaining(ClickHouseRequestState requestState, {String? queryId}) {
    final value = _timeout - _stopwatch.elapsed;
    if (value <= Duration.zero) {
      throw timeoutException(requestState, queryId: queryId);
    }
    return value;
  }

  /// Creates the timeout exception for the operation's current phase.
  ClickHouseTimeoutException timeoutException(
    ClickHouseRequestState requestState, {
    String? queryId,
  }) => ClickHouseTimeoutException(
    message: 'ClickHouse $_operation exceeded its ${_timeout.inMicroseconds} microsecond deadline.',
    requestState: requestState,
    queryId: queryId,
  );

  /// Waits for [future] within the operation's remaining time.
  Future<T> wait<T>(
    Future<T> future,
    ClickHouseRequestState requestState, {
    void Function()? onTimeout,
    void Function(T value)? onLateValue,
    String? queryId,
  }) {
    void handleLateValue(T value) {
      try {
        onLateValue?.call(value);
      } on Object {
        // Cleanup must not create an unhandled asynchronous error.
      }
    }

    late final Duration timeLeft;
    try {
      timeLeft = remaining(requestState, queryId: queryId);
    } on ClickHouseTimeoutException {
      unawaited(
        future.then<void>(
          handleLateValue,
          onError: (Object _, StackTrace _) {},
        ),
      );
      rethrow;
    }

    final completer = Completer<T>();
    final timer = Timer(timeLeft, () {
      try {
        onTimeout?.call();
      } on Object {
        // Preserve the timeout when local cleanup also fails.
      } finally {
        completer.completeError(timeoutException(requestState, queryId: queryId));
      }
    });
    unawaited(
      future.then(
        (value) {
          if (completer.isCompleted) {
            handleLateValue(value);
            return;
          }
          timer.cancel();
          completer.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (completer.isCompleted) {
            return;
          }
          timer.cancel();
          completer.completeError(error, stackTrace);
        },
      ),
    );
    return completer.future;
  }
}

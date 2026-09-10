part of 'clickhouse_client.dart';

final class _Deadline {
  _Deadline(this.operation, this.timeout) : _stopwatch = (Stopwatch()..start());

  final String operation;
  final Duration timeout;
  final Stopwatch _stopwatch;

  void check(ClickHouseRequestState requestState, {String? queryId}) {
    if (_stopwatch.elapsed >= timeout) {
      throw exception(requestState, queryId: queryId);
    }
  }

  Duration remaining(ClickHouseRequestState requestState, {String? queryId}) {
    final value = timeout - _stopwatch.elapsed;
    if (value <= Duration.zero) {
      throw exception(requestState, queryId: queryId);
    }
    return value;
  }

  ClickHouseTimeoutException exception(
    ClickHouseRequestState requestState, {
    String? queryId,
  }) => ClickHouseTimeoutException(
    message: 'ClickHouse $operation exceeded its ${timeout.inMicroseconds} microsecond deadline.',
    requestState: requestState,
    queryId: queryId,
  );

  Future<T> wait<T>(
    Future<T> future,
    ClickHouseRequestState requestState, {
    void Function()? onTimeout,
    void Function(T value)? onLateValue,
    String? queryId,
  }) {
    final completer = Completer<T>();
    final timer = Timer(remaining(requestState, queryId: queryId), () {
      try {
        onTimeout?.call();
      } finally {
        completer.completeError(exception(requestState, queryId: queryId));
      }
    });
    unawaited(
      future.then(
        (value) {
          if (completer.isCompleted) {
            onLateValue?.call(value);
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

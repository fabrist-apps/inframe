import 'dart:async';

/// One elapsed-time budget shared by connection and transaction phases.
final class ConnectionDeadline {
  /// Starts the budget immediately.
  ConnectionDeadline(this.duration) : _stopwatch = Stopwatch()..start();

  /// Original total budget.
  final Duration duration;
  final Stopwatch _stopwatch;

  /// Remaining budget, or a timeout once it is exhausted.
  Duration get remaining {
    final value = duration - _stopwatch.elapsed;
    if (value <= Duration.zero) throw TimeoutException('The connection deadline expired.');
    return value;
  }
}

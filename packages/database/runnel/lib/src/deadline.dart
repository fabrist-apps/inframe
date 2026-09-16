import 'dart:async';

/// One monotonic time budget shared by every phase of an operation.
final class Deadline {
  /// Starts the budget immediately; construction belongs inside Effect execution.
  Deadline(this.duration) : _stopwatch = Stopwatch()..start();

  /// Original total budget.
  final Duration duration;
  final Stopwatch _stopwatch;

  /// Remaining time, which may be zero or negative after expiry.
  Duration get timeLeft => duration - _stopwatch.elapsed;

  /// Whether synchronous work has exhausted the budget.
  bool get isExpired => timeLeft <= Duration.zero;

  /// Positive remaining time for a foreign wait, or a timeout after expiry.
  Duration get remaining {
    final value = timeLeft;
    if (value <= Duration.zero) throw TimeoutException('The operation deadline expired.');
    return value;
  }
}

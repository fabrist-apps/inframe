/// Terminal formatting for elapsed request durations.
extension DurationFormat on Duration {
  /// Formats elapsed time in microseconds, milliseconds, or seconds.
  String get logText {
    if (inMicroseconds < Duration.microsecondsPerMillisecond) return '$inMicroseconds µs';
    if (inMicroseconds < Duration.microsecondsPerSecond) {
      return '${(inMicroseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(2)} ms';
    }
    return '${(inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)} s';
  }
}

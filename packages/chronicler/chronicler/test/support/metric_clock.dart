/// Independently controlled wall and monotonic readings for metric tests.
final class MetricClock {
  DateTime now = DateTime.utc(2026, 9, 12);
  Duration elapsed = Duration.zero;

  void advance(Duration duration) {
    now = now.add(duration);
    elapsed += duration;
  }

  void rewindWall(Duration duration) {
    now = now.subtract(duration);
  }
}

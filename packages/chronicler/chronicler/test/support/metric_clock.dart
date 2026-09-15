import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';

import 'moments.dart';

/// Independently controlled wall and monotonic readings for metric tests.
final class MetricClock {
  Moment now = utcMoment(2026, 9, 12);
  Duration elapsed = Duration.zero;

  void advance(Duration duration) {
    now = now.addDuration(duration).getOrThrowWith((error) => StateError('$error'));
    elapsed += duration;
  }

  void rewindWall(Duration duration) {
    now = now.subtractDuration(duration).getOrThrowWith((error) => StateError('$error'));
  }
}

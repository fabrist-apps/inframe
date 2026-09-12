import 'dart:math';

/// Full-jitter reconnect backoff capped at five seconds.
final class ReconnectBackoff {
  /// Creates a policy. [randomBelow] returns a value below its positive argument.
  ReconnectBackoff({int Function(int upperBound)? randomBelow})
    : _randomBelow = randomBelow ?? Random().nextInt;

  final int Function(int upperBound) _randomBelow;
  var _attempt = 0;

  /// Returns the next zero-to-cap delay and advances the attempt counter.
  Duration next() {
    final exponent = _attempt.clamp(0, 30);
    final capMilliseconds = min(5000, 100 * (1 << exponent));
    _attempt++;
    return Duration(milliseconds: _randomBelow(capMilliseconds + 1));
  }

  /// Restarts the sequence after a complete successful handshake.
  void reset() => _attempt = 0;
}

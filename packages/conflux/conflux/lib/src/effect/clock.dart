import 'dart:async';

import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';

/// A cancellable registration created by [Clock.sleep].
abstract interface class CancellableWait {
  /// Completes when the wait expires or its registration is cancelled.
  Future<void> get completed;

  /// Removes the underlying wait registration and awaits its shutdown.
  Future<void> cancel();
}

/// Supplies wall time, monotonic elapsed time, and cancellable waiting.
abstract interface class Clock {
  /// The current instant in UTC, without requiring IANA initialization.
  UtcMoment wallTime();

  /// Time elapsed since this clock's monotonic origin.
  Duration monotonic();

  /// Registers a wait that can be removed through [CancellableWait.cancel].
  CancellableWait sleep(Duration duration);
}

/// A [Clock] backed by the Dart runtime.
final class SystemClock implements Clock {
  /// Creates a system clock with a fresh monotonic origin.
  SystemClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  @override
  UtcMoment wallTime() =>
      Moment.fromDateTime(DateTime.now()).getOrThrowWith((error) => StateError(error.message));

  @override
  Duration monotonic() => _stopwatch.elapsed;

  @override
  CancellableWait sleep(Duration duration) => _TimerWait(duration);
}

final class _TimerWait implements CancellableWait {
  _TimerWait(Duration duration) {
    if (duration <= Duration.zero) {
      _completer.complete();
    } else {
      _timer = Timer(duration, _completer.complete);
    }
  }

  final _completer = Completer<void>();
  Timer? _timer;

  @override
  Future<void> get completed => _completer.future;

  @override
  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    if (!_completer.isCompleted) _completer.complete();
  }
}

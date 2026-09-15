import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';

import 'moments.dart';

/// Independently controlled wall and monotonic readings for metric tests.
final class MetricClock implements Clock {
  Moment now = utcMoment(2026, 9, 12);
  Duration elapsed = Duration.zero;
  final _waits = <_MetricWait>{};

  int get activeWaits => _waits.length;

  @override
  UtcMoment wallTime() => now.toUtc();

  @override
  Duration monotonic() => elapsed;

  @override
  CancellableWait sleep(Duration duration) {
    final wait = _MetricWait(elapsed + duration, _waits.remove);
    _waits.add(wait);
    wait.completeIfDue(elapsed);
    return wait;
  }

  void advance(Duration duration) {
    now = now.addDuration(duration).getOrThrowWith((error) => StateError('$error'));
    elapsed += duration;
    for (final wait in _waits.toList()) {
      wait.completeIfDue(elapsed);
    }
  }

  void rewindWall(Duration duration) {
    now = now.subtractDuration(duration).getOrThrowWith((error) => StateError('$error'));
  }
}

final class _MetricWait implements CancellableWait {
  _MetricWait(this.deadline, this._remove);

  final Duration deadline;
  final void Function(_MetricWait) _remove;
  final _completion = Completer<void>();

  @override
  Future<void> get completed => _completion.future;

  void completeIfDue(Duration now) {
    if (!_completion.isCompleted && now >= deadline) {
      _remove(this);
      _completion.complete();
    }
  }

  @override
  Future<void> cancel() async {
    _remove(this);
    if (!_completion.isCompleted) _completion.complete();
  }
}

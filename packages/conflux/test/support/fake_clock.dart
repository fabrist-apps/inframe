import 'dart:async';

import 'package:conflux/conflux.dart';

final class FakeClock implements Clock {
  FakeClock({DateTime? wallTime}) : _wallTime = wallTime ?? DateTime.utc(2026);

  DateTime _wallTime;
  Duration _monotonic = Duration.zero;
  final _waits = <_FakeWait>{};

  int get activeWaits => _waits.length;

  void advance(Duration duration) {
    _wallTime = _wallTime.add(duration);
    _monotonic += duration;
    for (final wait in List.of(_waits)) {
      wait.completeIfDue(_monotonic);
    }
  }

  void adjustWall(Duration duration) {
    _wallTime = _wallTime.add(duration);
  }

  void advanceMonotonic(Duration duration) {
    _monotonic += duration;
    for (final wait in List.of(_waits)) {
      wait.completeIfDue(_monotonic);
    }
  }

  @override
  DateTime wallTime() => _wallTime;

  @override
  Duration monotonic() => _monotonic;

  @override
  CancellableWait sleep(Duration duration) {
    final wait = _FakeWait(_monotonic + duration, _remove);
    if (duration <= Duration.zero) {
      wait.completeIfDue(_monotonic);
    } else {
      _waits.add(wait);
    }
    return wait;
  }

  void _remove(_FakeWait wait) => _waits.remove(wait);
}

final class _FakeWait implements CancellableWait {
  _FakeWait(this.deadline, this._remove);

  final Duration deadline;
  final void Function(_FakeWait wait) _remove;
  final _completion = Completer<void>();

  @override
  Future<void> get completed => _completion.future;

  void completeIfDue(Duration now) {
    if (_completion.isCompleted || now < deadline) return;
    _remove(this);
    _completion.complete();
  }

  @override
  Future<void> cancel() async {
    if (_completion.isCompleted) return;
    _remove(this);
    _completion.complete();
  }
}

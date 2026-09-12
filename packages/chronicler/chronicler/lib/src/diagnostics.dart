import 'dart:async';
import 'dart:collection';

import 'package:chronicler/src/configuration.dart';

final class DiagnosticChannel {
  DiagnosticChannel(this.options);

  final DiagnosticOptions options;
  final _counts = <DiagnosticReason, BigInt>{};
  final _pending = <DiagnosticReason, BigInt>{};
  final _lastNotification = <DiagnosticReason, Duration>{};
  final _timers = <DiagnosticReason, Timer>{};
  final _elapsed = Stopwatch()..start();
  bool insideCallback = false;
  bool closed = false;

  Map<DiagnosticReason, BigInt> get counts => UnmodifiableMapView(Map.of(_counts));

  void record(DiagnosticReason reason) {
    _counts.update(reason, (count) => count + BigInt.one, ifAbsent: () => BigInt.one);
    _pending.update(reason, (count) => count + BigInt.one, ifAbsent: () => BigInt.one);
    if (options.onDiagnostic == null || closed || insideCallback || _timers.containsKey(reason)) {
      return;
    }
    final last = _lastNotification[reason];
    final elapsed = last == null ? options.notificationInterval : _elapsed.elapsed - last;
    final delay = elapsed >= options.notificationInterval
        ? Duration.zero
        : options.notificationInterval - elapsed;
    _timers[reason] = Timer(delay, () => _notify(reason));
  }

  void close() {
    closed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _notify(DiagnosticReason reason) {
    _timers.remove(reason);
    if (closed) return;
    final count = _pending.remove(reason);
    if (count == null) return;
    _lastNotification[reason] = _elapsed.elapsed;
    insideCallback = true;
    try {
      options.onDiagnostic?.call(ChroniclerDiagnostic(reason: reason, count: count));
    } on Object {
      // Diagnostics cannot diagnose their own callback.
    } finally {
      insideCallback = false;
    }
  }
}

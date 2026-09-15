import 'dart:async';
import 'dart:collection';

import 'package:chronicler/src/configuration.dart';
import 'package:conflux/effect.dart';

/// Counts runtime diagnostics and rate-limits payload-free notifications.
final class DiagnosticChannel {
  /// Creates a channel using [options].
  ///
  /// Notifications use [runtime]'s clock and root task ownership. [close]
  /// interrupts this channel's tasks without closing a supplied runtime.
  DiagnosticChannel(this.options, {Runtime? runtime}) : _runtime = runtime ?? Runtime();

  /// Notification behavior for this channel.
  final DiagnosticOptions options;
  final _counts = <DiagnosticReason, BigInt>{};
  final _pending = <DiagnosticReason, BigInt>{};
  final _lastNotification = <DiagnosticReason, Duration>{};
  final Runtime _runtime;
  final _notifications = <DiagnosticReason, Fiber<void, Never>>{};

  /// Whether the channel is currently invoking the application callback.
  bool insideCallback = false;

  /// Whether the channel has stopped scheduling notifications.
  bool closed = false;

  /// An immutable snapshot of exact lifetime counts by reason.
  Map<DiagnosticReason, BigInt> get counts => UnmodifiableMapView(Map.of(_counts));

  /// Increments [reason] and schedules an eligible notification.
  void record(DiagnosticReason reason) {
    _counts.update(reason, (count) => count + BigInt.one, ifAbsent: () => BigInt.one);
    _pending.update(reason, (count) => count + BigInt.one, ifAbsent: () => BigInt.one);
    if (options.onDiagnostic == null ||
        closed ||
        insideCallback ||
        _notifications.containsKey(reason)) {
      return;
    }
    final last = _lastNotification[reason];
    final elapsed = last == null ? options.notificationInterval : _runtime.clock.monotonic() - last;
    final delay = elapsed >= options.notificationInterval
        ? Duration.zero
        : options.notificationInterval - elapsed;
    final deadline = _runtime.clock.monotonic() + delay;
    _notifications[reason] = _runtime.fork(
      Effect.defer<void, Never>((_) {
        final remaining = deadline - _runtime.clock.monotonic();
        return Effect.sleep(remaining.isNegative ? Duration.zero : remaining);
      }).map((_, _) => _notify(reason)),
    );
  }

  /// Cancels delayed notifications and emits notifications already eligible.
  void close() {
    if (closed) return;
    final now = _runtime.clock.monotonic();
    final eligible = _notifications.keys.where((reason) {
      final last = _lastNotification[reason];
      return last == null || now - last >= options.notificationInterval;
    }).toList();
    for (final notification in _notifications.values) {
      unawaited(notification.interrupt());
    }
    _notifications.clear();
    eligible.forEach(_notify);
    closed = true;
  }

  void _notify(DiagnosticReason reason) {
    _notifications.remove(reason);
    // Interruption settles asynchronously; closing must suppress callbacks now.
    if (closed) return;
    final count = _pending.remove(reason);
    if (count == null) return;
    _lastNotification[reason] = _runtime.clock.monotonic();
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

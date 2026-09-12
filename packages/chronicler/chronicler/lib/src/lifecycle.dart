import 'dart:collection';

/// Why a lifecycle operation discarded a record.
enum DropReason {
  invalidRecord,
  recordTooLarge,
  queueFull,
  collectionDisabled,
  sampledOut,
  hookDropped,
  hookFailed,
  exportRejected,
  attemptsExhausted,
  shutdown,
  runtimeClosed,
}

/// The Chronicler lifecycle state when an operation completed.
enum ChroniclerRuntimeState { running, closing, closed }

/// Immutable delivery accounting for one flush or close snapshot.
final class DeliveryReport {
  DeliveryReport({
    required this.accepted,
    required Map<DropReason, int> dropped,
    required this.pending,
    required this.uncertainDropped,
    required this.timedOut,
    required this.runtimeState,
    required this.cleanupIncomplete,
  }) : dropped = UnmodifiableMapView(Map.of(dropped));

  /// Records acknowledged by the destination.
  final int accepted;

  /// Terminal records grouped by their discard reason.
  final Map<DropReason, int> dropped;

  /// Records still owned by the runtime when the operation completed.
  final int pending;

  /// Dropped records for which an earlier attempt may have delivered data.
  final int uncertainDropped;

  /// Whether this operation exhausted its own deadline.
  final bool timedOut;

  /// Runtime state when this report was created.
  final ChroniclerRuntimeState runtimeState;

  /// Whether shutdown left exporter work or resources unfinished.
  final bool cleanupIncomplete;
}

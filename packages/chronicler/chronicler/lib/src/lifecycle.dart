import 'dart:collection';

/// Why a lifecycle operation discarded a record.
enum DropReason {
  /// The record failed schema or field validation.
  invalidRecord,

  /// The final encoded record exceeded its byte limit.
  recordTooLarge,

  /// The bounded pending queue had no remaining capacity.
  queueFull,

  /// Collection was disabled before the record became terminal.
  collectionDisabled,

  /// The configured sampling policy excluded the record.
  sampledOut,

  /// The capture hook explicitly returned no record.
  hookDropped,

  /// The capture hook threw while processing the record.
  hookFailed,

  /// The exporter permanently rejected the record.
  exportRejected,

  /// The record consumed its configured delivery attempts.
  attemptsExhausted,

  /// Shutdown ended before the record reached a destination outcome.
  shutdown,

  /// Recording occurred after shutdown started.
  runtimeClosed,
}

/// The Chronicler lifecycle state when an operation completed.
enum ChroniclerRuntimeState {
  /// The runtime accepts records and configuration changes.
  running,

  /// The runtime is draining final work and releasing its exporter.
  closing,

  /// The runtime has finished shutdown.
  closed,
}

/// Immutable delivery accounting for one flush or close snapshot.
final class DeliveryReport {
  /// Creates immutable accounting for one lifecycle snapshot.
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

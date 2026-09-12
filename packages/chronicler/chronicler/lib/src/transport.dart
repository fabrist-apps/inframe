import 'package:chronicler/src/models.dart';

/// The disposition of one submitted record.
enum ExportDisposition {
  /// The destination acknowledged the record.
  accepted,

  /// The exporter recommends another delivery attempt.
  retryable,

  /// The destination permanently refused the record.
  rejected,
}

/// The result of one export operation.
sealed class ExportResult {
  /// Creates the base type for an export result.
  const ExportResult();

  /// Applies an accepted disposition to the whole batch.
  const factory ExportResult.accepted() = WholeBatchExportResult.accepted;

  /// Applies a retryable disposition to the whole batch.
  const factory ExportResult.retryable() = WholeBatchExportResult.retryable;

  /// Applies a rejected disposition to the whole batch.
  const factory ExportResult.rejected() = WholeBatchExportResult.rejected;

  /// Matches [outcomes] to submitted records by event ID.
  factory ExportResult.perRecord(List<RecordExportOutcome> outcomes) = RecordExportResult;
}

/// Applies one disposition to the complete submitted batch.
final class WholeBatchExportResult extends ExportResult {
  /// Creates a result that accepts every submitted record.
  const WholeBatchExportResult.accepted() : disposition = ExportDisposition.accepted;

  /// Creates a result that retries every submitted record.
  const WholeBatchExportResult.retryable() : disposition = ExportDisposition.retryable;

  /// Creates a result that rejects every submitted record.
  const WholeBatchExportResult.rejected() : disposition = ExportDisposition.rejected;

  /// The disposition applied to every record in the batch.
  final ExportDisposition disposition;
}

/// Matches dispositions to submitted event IDs.
final class RecordExportResult extends ExportResult {
  /// Creates an immutable result from event-ID keyed [outcomes].
  RecordExportResult(List<RecordExportOutcome> outcomes) : outcomes = List.unmodifiable(outcomes);

  /// The outcome for each submitted event ID.
  final List<RecordExportOutcome> outcomes;
}

/// One event-ID keyed disposition in a partial export result.
final class RecordExportOutcome {
  /// Creates one outcome for [eventId].
  const RecordExportOutcome({required this.eventId, required this.disposition});

  /// The submitted record's event ID.
  final String eventId;

  /// The destination's disposition for the record.
  final ExportDisposition disposition;
}

/// A cancelable export operation.
abstract interface class ExportAttempt {
  /// Completes only after this attempt's transport work has stopped.
  ///
  /// Cancellation must stop the transport and settle this future. Until it
  /// settles, Chronicler retains the concurrency slot and record capacity to
  /// prevent overlapping attempts. If the transport cannot stop, capacity stays
  /// occupied until the runtime's bounded shutdown completes.
  Future<ExportResult> get result;

  /// Promptly and idempotently requests cancellation.
  void cancel();
}

/// Application-supplied transport for Chronicler batches.
abstract interface class ChroniclerExporter {
  /// Starts one export attempt for [batch].
  ExportAttempt export(ChroniclerBatch batch);

  /// Releases resources owned by the exporter.
  ///
  /// Must abort remaining I/O even when cancellation requests have not settled.
  /// Complete only after resources are released. Chronicler bounds its wait by
  /// the total shutdown deadline and reports unfinished cleanup separately.
  Future<void> close();
}

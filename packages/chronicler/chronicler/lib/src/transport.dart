import 'package:chronicler/src/models.dart';

/// The disposition of one submitted record.
enum ExportDisposition { accepted, retryable, rejected }

/// The result of one export operation.
sealed class ExportResult {
  const ExportResult();

  const factory ExportResult.accepted() = WholeBatchExportResult.accepted;
  const factory ExportResult.retryable() = WholeBatchExportResult.retryable;
  const factory ExportResult.rejected() = WholeBatchExportResult.rejected;
  factory ExportResult.records(Iterable<RecordExportOutcome> outcomes) = RecordExportResult;
}

/// Applies one disposition to the complete submitted batch.
final class WholeBatchExportResult extends ExportResult {
  const WholeBatchExportResult.accepted() : disposition = ExportDisposition.accepted;
  const WholeBatchExportResult.retryable() : disposition = ExportDisposition.retryable;
  const WholeBatchExportResult.rejected() : disposition = ExportDisposition.rejected;

  final ExportDisposition disposition;
}

/// Matches dispositions to submitted event IDs.
final class RecordExportResult extends ExportResult {
  RecordExportResult(Iterable<RecordExportOutcome> outcomes)
    : outcomes = List.unmodifiable(outcomes);

  final List<RecordExportOutcome> outcomes;
}

/// One event-ID keyed disposition in a partial export result.
final class RecordExportOutcome {
  const RecordExportOutcome({required this.eventId, required this.disposition});

  final String eventId;
  final ExportDisposition disposition;
}

/// A cancelable export operation.
abstract interface class ExportAttempt {
  /// Completes only after this attempt's transport work has stopped.
  Future<ExportResult> get result;

  /// Promptly and idempotently requests cancellation.
  void cancel();
}

/// Application-supplied transport for Chronicler batches.
abstract interface class ChroniclerExporter {
  ExportAttempt export(ChroniclerBatch batch);
  Future<void> close();
}

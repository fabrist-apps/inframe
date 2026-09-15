import 'package:chronicler/chronicler.dart';

final class MemoryExporter implements ChroniclerExporter {
  final records = <ChroniclerRecord>[];

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    records.addAll(batch.records);
    return const _AcceptedAttempt();
  }

  @override
  Future<void> close() async {}
}

final class _AcceptedAttempt implements ExportAttempt {
  const _AcceptedAttempt();

  @override
  Future<ExportResult> get result async => const ExportResult.accepted();

  @override
  void cancel() {}
}

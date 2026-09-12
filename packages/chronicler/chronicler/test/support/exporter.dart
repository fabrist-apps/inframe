import 'dart:async';

import 'package:chronicler/chronicler.dart';

final class TestExporter implements ChroniclerExporter {
  final batches = <ChroniclerBatch>[];
  final attempts = <TestExportAttempt>[];
  final _nextBatch = StreamController<ChroniclerBatch>.broadcast(sync: true);
  int closeCount = 0;

  Stream<ChroniclerBatch> get exportedBatches => _nextBatch.stream;

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    batches.add(batch);
    _nextBatch.add(batch);
    final attempt = TestExportAttempt();
    attempts.add(attempt);
    return attempt;
  }

  @override
  Future<void> close() async {
    closeCount++;
    await _nextBatch.close();
  }
}

final class TestExportAttempt implements ExportAttempt {
  final completer = Completer<ExportResult>();
  int cancelCount = 0;

  @override
  Future<ExportResult> get result => completer.future;

  @override
  void cancel() => cancelCount++;
}

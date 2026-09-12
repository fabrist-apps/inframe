import 'dart:async';
import 'dart:collection';

import 'package:chronicler/chronicler.dart';

final class TestExporter implements ChroniclerExporter {
  TestExporter({this.acceptImmediately = false});

  final bool acceptImmediately;
  bool _acceptRemaining = false;
  final batches = <ChroniclerBatch>[];
  final attempts = <TestExportAttempt>[];
  final _nextBatch = StreamController<ChroniclerBatch>.broadcast(sync: true);
  final _exportFailures = Queue<Exception>();
  int closeCount = 0;
  Completer<void>? closeCompleter;
  Exception? closeError;

  Stream<ChroniclerBatch> get exportedBatches => _nextBatch.stream;

  void failNextExport(Exception error) => _exportFailures.add(error);

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    batches.add(batch);
    _nextBatch.add(batch);
    if (_exportFailures.isNotEmpty) throw _exportFailures.removeFirst();
    final attempt = TestExportAttempt();
    attempts.add(attempt);
    if (acceptImmediately || _acceptRemaining) {
      attempt.completer.complete(const ExportResult.accepted());
    }
    return attempt;
  }

  /// Resolves deliberate test backpressure before teardown closes the runtime.
  void acceptRemaining() {
    _acceptRemaining = true;
    for (final attempt in attempts) {
      if (!attempt.completer.isCompleted) {
        attempt.completer.complete(const ExportResult.accepted());
      }
    }
  }

  @override
  Future<void> close() {
    closeCount++;
    final error = closeError;
    if (error != null) throw error;
    return (closeCompleter?.future ?? Future.value()).whenComplete(
      _nextBatch.close,
    );
  }
}

final class TestExportAttempt implements ExportAttempt {
  final completer = Completer<ExportResult>();
  int cancelCount = 0;
  Exception? cancelError;

  @override
  Future<ExportResult> get result => completer.future;

  @override
  void cancel() {
    cancelCount++;
    final error = cancelError;
    if (error != null) throw error;
  }
}

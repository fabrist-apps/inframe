import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/exporter.dart';
import 'support/runtime.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Chronicler flush', () {
    test('reports accepted, rejected, and exhausted records exactly once', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxBatchRecords: 3,
        maxAttempts: 1,
      );
      Context().withChronicler(chronicler.recorder).logs
        ..info('accepted')
        ..info('rejected')
        ..info('exhausted');
      final reportFuture = chronicler.flush();
      await waitForCondition(() => exporter.attempts.length == 1);
      final records = exporter.batches.single.records;
      exporter.attempts.single.completer.complete(
        ExportResult.perRecord([
          RecordExportOutcome(
            eventId: records[2].envelope.eventId,
            disposition: ExportDisposition.retryable,
          ),
          RecordExportOutcome(
            eventId: records[0].envelope.eventId,
            disposition: ExportDisposition.accepted,
          ),
          RecordExportOutcome(
            eventId: records[1].envelope.eventId,
            disposition: ExportDisposition.rejected,
          ),
        ]),
      );

      final report = await reportFuture;
      expect(report.accepted, 1);
      expect(report.dropped, {
        DropReason.exportRejected: 1,
        DropReason.attemptsExhausted: 1,
      });
      expect(report.pending, 0);
      expect(report.uncertainDropped, 1);
      expect(report.timedOut, isFalse);
      expect(report.runtimeState, ChroniclerRuntimeState.running);
      expect(report.cleanupIncomplete, isFalse);
      _expectCompleteAccounting(report, 3);
      expect(
        () => report.dropped[DropReason.shutdown] = 1,
        throwsUnsupportedError,
      );
    });

    test('preserves uncertainty from a failed attempt before rejection', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxAttempts: 2);
      Context().withChronicler(chronicler.recorder).logs.info('uncertain');
      final reportFuture = chronicler.flush();
      await waitForCondition(() => exporter.attempts.length == 1);
      exporter.attempts.single.completer.completeError(Exception('failed'));
      await waitForCondition(() => exporter.attempts.length == 2);
      exporter.attempts.last.completer.complete(const ExportResult.rejected());

      final report = await reportFuture;
      expect(report.dropped, {DropReason.exportRejected: 1});
      expect(report.uncertainDropped, 1);
      _expectCompleteAccounting(report, 1);
    });

    test('does not include records captured after its snapshot', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final logs = Context().withChronicler(chronicler.recorder).logs..info('snapshot');
      final reportFuture = chronicler.flush();
      await waitForCondition(() => exporter.attempts.length == 1);

      logs.info('later');
      exporter.attempts.first.completer.complete(const ExportResult.accepted());
      final report = await reportFuture;

      expect(report.accepted, 1);
      expect(report.pending, 0);
      await waitForCondition(() => exporter.attempts.length == 2);
    });

    test('keeps independent concurrent snapshots and deadlines', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final logs = Context().withChronicler(chronicler.recorder).logs..info('first');
      final first = chronicler.flush(timeout: const Duration(milliseconds: 5));
      await waitForCondition(() => exporter.attempts.length == 1);
      logs.info('second');
      final second = chronicler.flush(timeout: const Duration(milliseconds: 100));

      final firstReport = await first;
      expect(firstReport.pending, 1);
      expect(firstReport.timedOut, isTrue);
      exporter.attempts.first.completer.complete(const ExportResult.accepted());
      await waitForCondition(() => exporter.attempts.length == 2);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      final secondReport = await second;

      expect(secondReport.accepted, 2);
      expect(secondReport.timedOut, isFalse);
      expect(exporter.batches, hasLength(2));
      final subsequent = await chronicler.flush();
      _expectCompleteAccounting(subsequent, 0);
      expect(subsequent.timedOut, isFalse);
    });

    test('timeout leaves records queued and freezes its report', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      Context().withChronicler(chronicler.recorder).logs.info('pending');
      final report = await chronicler.flush(
        timeout: const Duration(milliseconds: 3),
      );

      expect(report.pending, 1);
      expect(report.timedOut, isTrue);
      _expectCompleteAccounting(report, 1);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      await settleAsync();
      expect(report.pending, 1);
      expect(report.accepted, 0);
      final subsequent = await chronicler.flush();
      _expectCompleteAccounting(subsequent, 0);
      expect(subsequent.timedOut, isFalse);
    });

    test('includes records and immediate drops finalized by that call', () async {
      final exporter = TestExporter();
      final chronicler = closeAfterTest(
        Chronicler(
          appId: 'app',
          release: 'release',
          source: ChroniclerSource.server,
          exporter: exporter,
          options: ChroniclerOptions(
            delivery: const DeliveryOptions(maxBatchRecords: 10),
            redaction: RedactionOptions(
              beforeRecord: (record) =>
                  record is MetricRecord && record.payload.name == 'discarded' ? null : record,
            ),
          ),
        ),
        exporter,
      );
      chronicler.recorder.metrics.counter('accepted').add(1);
      chronicler.recorder.metrics.counter('discarded').add(1);

      final reportFuture = chronicler.flush();
      await waitForCondition(() => exporter.attempts.length == 1);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      final report = await reportFuture;

      expect(report.accepted, 1);
      expect(report.dropped, {DropReason.hookDropped: 1});
      expect(report.pending, 0);
      _expectCompleteAccounting(report, 2);
    });

    test('includes every metric interval finalized by that call', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      chronicler.recorder.metrics.counter('first').add(1);
      chronicler.recorder.metrics.counter('second').add(2);

      final reportFuture = chronicler.flush();
      await waitForCondition(() => exporter.attempts.isNotEmpty);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      final report = await reportFuture;

      expect(report.accepted, 2);
      _expectCompleteAccounting(report, 2);
      expect(
        exporter.batches.single.records.cast<MetricRecord>().map((record) => record.payload.name),
        ['first', 'second'],
      );
    });

    test('returns an empty snapshot and rejects non-positive overrides', () async {
      final chronicler = _chronicler(TestExporter());

      final report = await chronicler.flush();

      _expectCompleteAccounting(report, 0);
      expect(report.timedOut, isFalse);
      expect(
        () => chronicler.flush(timeout: Duration.zero),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  int maxBatchRecords = 1,
  int maxAttempts = 5,
}) => closeAfterTest(
  Chronicler(
    appId: 'app',
    release: 'release',
    source: ChroniclerSource.server,
    exporter: exporter,
    options: ChroniclerOptions(
      delivery: DeliveryOptions(
        maxBatchRecords: maxBatchRecords,
        maxAttempts: maxAttempts,
        initialRetryDelay: const Duration(microseconds: 1),
      ),
    ),
  ),
  exporter,
);

void _expectCompleteAccounting(DeliveryReport report, int original) {
  expect(
    report.accepted +
        report.dropped.values.fold<int>(0, (sum, count) => sum + count) +
        report.pending,
    original,
  );
  expect(
    report.uncertainDropped,
    lessThanOrEqualTo(report.dropped.values.fold<int>(0, (a, b) => a + b)),
  );
}

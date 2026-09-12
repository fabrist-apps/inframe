import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerDeliveryFixture;
import 'package:chrono_id/chrono_id.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
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
      await _waitFor(() => exporter.attempts.length == 1);
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
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (_, _) => Duration.zero);
      Context().withChronicler(chronicler.recorder).logs.info('uncertain');
      final reportFuture = chronicler.flush();
      await _waitFor(() => exporter.attempts.length == 1);
      exporter.attempts.single.completer.completeError(Exception('failed'));
      await _waitFor(() => exporter.attempts.length == 2);
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
      await _waitFor(() => exporter.attempts.length == 1);

      logs.info('later');
      exporter.attempts.first.completer.complete(const ExportResult.accepted());
      final report = await reportFuture;

      expect(report.accepted, 1);
      expect(report.pending, 0);
      await _waitFor(() => exporter.attempts.length == 2);
    });

    test('keeps independent concurrent snapshots and deadlines', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);
      final logs = Context().withChronicler(chronicler.recorder).logs..info('first');
      final first = chronicler.flush(timeout: const Duration(milliseconds: 5));
      await _waitFor(() => exporter.attempts.length == 1);
      logs.info('second');
      final second = chronicler.flush(timeout: const Duration(milliseconds: 100));

      final firstReport = await first;
      expect(firstReport.pending, 1);
      expect(firstReport.timedOut, isTrue);
      exporter.attempts.first.completer.complete(const ExportResult.accepted());
      await _waitFor(() => exporter.attempts.length == 2);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      final secondReport = await second;

      expect(secondReport.accepted, 2);
      expect(secondReport.timedOut, isFalse);
      expect(exporter.batches, hasLength(2));
      expect(ChroniclerDeliveryFixture.activeFlushes(chronicler), 0);
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
      await _settle();
      expect(report.pending, 1);
      expect(report.accepted, 0);
      expect(ChroniclerDeliveryFixture.activeFlushes(chronicler), 0);
    });

    test('includes records and immediate drops finalized by that call', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter)
        ..setCollectionEnabled(ChroniclerSignal.metrics, false);
      ChroniclerDeliveryFixture.finalizeOnNextFlush(chronicler, [
        _logRecord('finalized'),
        _metricRecord(),
      ]);

      final reportFuture = chronicler.flush();
      await _waitFor(() => exporter.attempts.length == 1);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      final report = await reportFuture;

      expect(report.accepted, 1);
      expect(report.dropped, {DropReason.collectionDisabled: 1});
      expect(report.pending, 0);
      _expectCompleteAccounting(report, 2);
    });

    test('includes every internal finalization batch queued for that call', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      ChroniclerDeliveryFixture.finalizeOnNextFlush(chronicler, [
        _logRecord('first'),
      ]);
      ChroniclerDeliveryFixture.finalizeOnNextFlush(chronicler, [
        _logRecord('second'),
      ]);

      final reportFuture = chronicler.flush();
      await _waitFor(() => exporter.attempts.isNotEmpty);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      final report = await reportFuture;

      expect(report.accepted, 2);
      _expectCompleteAccounting(report, 2);
      expect(
        exporter.batches.single.records.cast<LogRecord>().map((record) => record.payload.message),
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
}) => Chronicler(
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
);

LogRecord _logRecord(String message) => LogRecord(
  envelope: _envelope(),
  payload: LogPayload(severity: LogSeverity.info, message: message),
);

MetricRecord _metricRecord() {
  final now = DateTime.now().toUtc();
  return MetricRecord(
    envelope: _envelope(),
    payload: MetricPayload(
      name: 'count',
      instrument: MetricInstrument.counter,
      unit: '1',
      intervalStart: now,
      intervalEnd: now,
      durationMicros: 0,
      observationCount: 1,
      temporality: MetricTemporality.delta,
      sum: 1,
    ),
  );
}

RecordEnvelope _envelope() => RecordEnvelope(
  eventId: ChronoID.generate(prefix: 'evt'),
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  timestamp: DateTime.now().toUtc(),
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

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 4));

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition was not met before timeout.');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

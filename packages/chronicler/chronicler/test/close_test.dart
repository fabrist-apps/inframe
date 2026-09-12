import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerDeliveryFixture;
import 'package:chrono_id/chrono_id.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('Chronicler close', () {
    test('shares one future and closes the exporter once', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter);

      final first = chronicler.close();
      final second = chronicler.close();

      expect(identical(first, second), isTrue);
      expect((await first).runtimeState, ChroniclerRuntimeState.closed);
      expect(exporter.closeCount, 1);
    });

    test('seals finalization after blocking recording and configuration', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(exporter, maxBatchRecords: 10)
        ..setCollectionEnabled(ChroniclerSignal.metrics, false);
      Context().withChronicler(chronicler.recorder).logs.info('queued');
      ChroniclerDeliveryFixture.finalizeOnNextFlush(chronicler, [
        _logRecord('finalized'),
        _metricRecord(),
      ]);

      final closeFuture = chronicler.close();
      Context().withChronicler(chronicler.recorder).logs.info('blocked');
      expect(
        () => chronicler.setPropagationEnabled(false),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      await _waitFor(() => exporter.attempts.length == 1);
      expect(exporter.batches.single.records, hasLength(2));
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      final report = await closeFuture;

      expect(report.accepted, 2);
      expect(report.dropped, {DropReason.collectionDisabled: 1});
      expect(report.runtimeState, ChroniclerRuntimeState.closed);
      expect(chronicler.diagnosticCounts[DiagnosticReason.runtimeClosed], BigInt.one);
      expect(exporter.closeCount, 1);
    });

    test('starts cleanup early and gives it the remaining total budget', () async {
      final exporter = TestExporter()..closeCompleter = Completer<void>();
      final chronicler = _chronicler(exporter);
      Context().withChronicler(chronicler.recorder).logs.info('record');
      await _waitFor(() => exporter.attempts.length == 1);
      final closeFuture = chronicler.close();
      exporter.attempts.single.completer.complete(const ExportResult.accepted());

      await _waitFor(() => exporter.closeCount == 1);
      exporter.closeCompleter!.complete();
      final report = await closeFuture;

      expect(report.accepted, 1);
      expect(report.timedOut, isFalse);
      expect(report.cleanupIncomplete, isFalse);
    });

    test('bounds unresolved cancellation and cleanup by one total deadline', () async {
      final exporter = TestExporter()..closeCompleter = Completer<void>();
      final chronicler = _chronicler(
        exporter,
        closeTimeout: const Duration(milliseconds: 20),
        cleanupReserve: const Duration(milliseconds: 10),
      );
      Context().withChronicler(chronicler.recorder).logs.info('unresolved');
      await _waitFor(() => exporter.attempts.length == 1);
      final elapsed = Stopwatch()..start();

      final report = await chronicler.close();
      elapsed.stop();

      expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 250)));
      expect(exporter.attempts.single.cancelCount, 1);
      expect(exporter.closeCount, 1);
      expect(report.dropped, {DropReason.shutdown: 1});
      expect(report.uncertainDropped, 1);
      expect(report.timedOut, isTrue);
      expect(report.cleanupIncomplete, isTrue);
      exporter.attempts.single.completer.completeError(Exception('late failure'));
      exporter.closeCompleter!.complete();
      await _settle();
      expect(report.dropped, {DropReason.shutdown: 1});
    });

    test('contains cancellation and exporter cleanup failures', () async {
      final exporter = TestExporter()..closeError = Exception('cleanup failed');
      final chronicler = _chronicler(exporter);

      final report = await chronicler.close();

      expect(report.timedOut, isFalse);
      expect(report.cleanupIncomplete, isTrue);
      expect(exporter.closeCount, 1);
      expect(
        chronicler.diagnosticCounts[DiagnosticReason.exportCleanupFailed],
        BigInt.one,
      );

      final cancelExporter = TestExporter();
      final cancelChronicler = _chronicler(
        cancelExporter,
        closeTimeout: const Duration(milliseconds: 15),
        cleanupReserve: const Duration(milliseconds: 5),
      );
      Context().withChronicler(cancelChronicler.recorder).logs.info('cancel');
      await _waitFor(() => cancelExporter.attempts.length == 1);
      cancelExporter.attempts.single.cancelError = Exception('cancel failed');

      await cancelChronicler.close();

      expect(
        cancelChronicler.diagnosticCounts[DiagnosticReason.exportCancellationFailed],
        BigInt.one,
      );
    });

    test('accepts a late result during cleanup without hiding delivery timeout', () async {
      final exporter = TestExporter()..closeCompleter = Completer<void>();
      final chronicler = _chronicler(
        exporter,
        closeTimeout: const Duration(milliseconds: 60),
        cleanupReserve: const Duration(milliseconds: 45),
      );
      Context().withChronicler(chronicler.recorder).logs.info('late accepted');
      await _waitFor(() => exporter.attempts.length == 1);
      final closeFuture = chronicler.close();
      await _waitFor(() => exporter.attempts.single.cancelCount == 1);

      exporter.attempts.single.completer.complete(const ExportResult.accepted());
      exporter.closeCompleter!.complete();
      final report = await closeFuture;

      expect(report.accepted, 1);
      expect(report.dropped, isEmpty);
      expect(report.timedOut, isTrue);
      expect(report.cleanupIncomplete, isFalse);
    });

    test('finishes an existing flush when shutdown resolves its snapshot', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        closeTimeout: const Duration(milliseconds: 15),
        cleanupReserve: const Duration(milliseconds: 5),
      );
      Context().withChronicler(chronicler.recorder).logs.info('flush');
      final flushFuture = chronicler.flush(timeout: const Duration(seconds: 1));
      await _waitFor(() => exporter.attempts.length == 1);

      final closeFuture = chronicler.close();
      final flushReport = await flushFuture;
      final closeReport = await closeFuture;

      expect(flushReport.dropped, {DropReason.shutdown: 1});
      expect(flushReport.runtimeState, ChroniclerRuntimeState.closing);
      expect(flushReport.timedOut, isFalse);
      expect(closeReport.runtimeState, ChroniclerRuntimeState.closed);
    });

    test('flush during and after shutdown returns immediately without work', () async {
      final exporter = TestExporter()..closeCompleter = Completer<void>();
      final chronicler = _chronicler(exporter);
      final closeFuture = chronicler.close();
      await _waitFor(() => exporter.closeCount == 1);

      final closing = await chronicler.flush();
      expect(closing.runtimeState, ChroniclerRuntimeState.closing);
      expect(exporter.batches, isEmpty);
      exporter.closeCompleter!.complete();
      await closeFuture;
      final closed = await chronicler.flush();

      expect(closed.runtimeState, ChroniclerRuntimeState.closed);
      expect(exporter.batches, isEmpty);
    });

    test('allows zero cleanup reserve and keeps documented defaults', () async {
      const defaults = DeliveryOptions();
      expect(defaults.flushTimeout, const Duration(seconds: 10));
      expect(defaults.closeTimeout, const Duration(seconds: 10));
      expect(defaults.cleanupReserve, const Duration(seconds: 2));

      final report = await _chronicler(
        TestExporter(),
        closeTimeout: const Duration(milliseconds: 20),
        cleanupReserve: Duration.zero,
      ).close();
      expect(report.cleanupIncomplete, isFalse);
    });

    test('cancels delayed diagnostics but emits an already-eligible one', () async {
      final notifications = <ChroniclerDiagnostic>[];
      final chronicler = _chronicler(
        TestExporter(),
        diagnostics: DiagnosticOptions(
          onDiagnostic: notifications.add,
        ),
      );
      Context()
          .withChronicler(chronicler.recorder)
          .logs
          .info('invalid', attributes: {'bad': Object()});
      await _settle();
      expect(notifications, hasLength(1));
      Context()
          .withChronicler(chronicler.recorder)
          .logs
          .info('invalid again', attributes: {'bad': Object()});

      await chronicler.close();
      await _settle();

      expect(notifications, hasLength(1));
      expect(
        chronicler.diagnosticCounts[DiagnosticReason.invalidRecord],
        BigInt.two,
      );

      final eligible = <ChroniclerDiagnostic>[];
      final immediate = _chronicler(
        TestExporter(),
        diagnostics: DiagnosticOptions(onDiagnostic: eligible.add),
      );
      Context()
          .withChronicler(immediate.recorder)
          .logs
          .info('invalid', attributes: {'bad': Object()});
      await immediate.close();
      expect(eligible, hasLength(1));
    });

    test('rejects close invoked from the capture hook', () async {
      final exporter = TestExporter();
      late Chronicler chronicler;
      chronicler = _chronicler(
        exporter,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            unawaited(chronicler.close());
            return record;
          },
        ),
      );

      Context().withChronicler(chronicler.recorder).logs.info('hook');
      final report = await chronicler.close();

      expect(report.accepted, 0);
      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.hookFailed], BigInt.one);
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  int maxBatchRecords = 1,
  Duration closeTimeout = const Duration(milliseconds: 100),
  Duration cleanupReserve = const Duration(milliseconds: 20),
  DiagnosticOptions diagnostics = const DiagnosticOptions(),
  RedactionOptions redaction = const RedactionOptions(),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(
      maxBatchRecords: maxBatchRecords,
      closeTimeout: closeTimeout,
      cleanupReserve: cleanupReserve,
      initialRetryDelay: const Duration(microseconds: 1),
    ),
    diagnostics: diagnostics,
    redaction: redaction,
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

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 4));

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition was not met before timeout.');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

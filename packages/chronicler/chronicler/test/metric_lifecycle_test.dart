import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart'
    show ChroniclerDeliveryFixture, ChroniclerMetricFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('Chronicler metric lifecycle', () {
    test('should seal a partial interval into the calling flush snapshot', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter);
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(2);
      final firstFlush = chronicler.flush();
      counter.add(3);

      final firstReport = await firstFlush;
      expect(firstReport.accepted, 1);
      expect(_sums(exporter), [2]);

      final secondReport = await chronicler.flush();
      expect(secondReport.accepted, 1);
      expect(_sums(exporter), [2, 3]);

      await chronicler.close();
    });

    test('should restart the full interval after a partial flush', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter,
        metricInterval: const Duration(milliseconds: 100),
      );
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests');

      await Future<void>.delayed(const Duration(milliseconds: 40));
      counter.add(1);
      await chronicler.flush();
      counter.add(2);
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(_sums(exporter), [1]);
      await _waitFor(() => _sums(exporter).length == 2);
      expect(_sums(exporter), [1, 2]);

      await chronicler.close();
    });

    test('should discard unfinished and queued metrics while retaining handles', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter,
        maxBatchRecords: 10,
        batchInterval: const Duration(minutes: 1),
      );
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      final counter = metrics.counter('requests')..add(1);
      ChroniclerMetricFixture.rotate(chronicler);
      counter.add(5);

      chronicler.setCollectionEnabled(ChroniclerSignal.metrics, false);
      counter.add(10);
      chronicler.setCollectionEnabled(ChroniclerSignal.metrics, true);
      expect(identical(metrics.counter('requests'), counter), isTrue);
      counter.add(2);
      final report = await chronicler.flush();

      expect(report.accepted, 1);
      expect(_sums(exporter), [2]);
      expect(
        chronicler.diagnosticCounts[DiagnosticReason.collectionDisabled],
        BigInt.from(2),
      );
      await chronicler.close();
    });

    test('should seal pending metrics during close after blocking new recording', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter);
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(4);

      final close = chronicler.close();
      counter.add(8);
      final report = await close;

      expect(report.accepted, 1);
      expect(report.runtimeState, ChroniclerRuntimeState.closed);
      expect(_sums(exporter), [4]);
      expect(chronicler.diagnosticCounts[DiagnosticReason.runtimeClosed], BigInt.one);
    });

    test('should include an immediately dropped aggregate in flush accounting', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter,
        maxPendingRecords: 1,
        batchInterval: const Duration(minutes: 1),
      );
      final context = Context().withChronicler(chronicler.recorder);
      context.logs.info('occupies queue');
      context.metrics.counter('requests').add(1);

      final report = await chronicler.flush();

      expect(report.accepted, 1);
      expect(report.dropped, {DropReason.queueFull: 1});
      expect(report.pending, 0);
      expect(report.accepted + report.dropped.values.single + report.pending, 2);
      await chronicler.close();
    });

    test('should retry immutable aggregates while newer measurements accumulate', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxAttempts: 2,
        retryDelay: const Duration(milliseconds: 1),
      );
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (_, _) => Duration.zero);
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(1);

      final firstFlush = chronicler.flush();
      await _waitFor(() => exporter.attempts.isNotEmpty);
      final original = exporter.batches.single.records.single as MetricRecord;
      counter.add(9);
      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await _waitFor(() => exporter.attempts.length == 2);

      final retry = exporter.batches.last.records.single as MetricRecord;
      expect(retry.envelope.eventId, original.envelope.eventId);
      expect(retry.payload, original.payload);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      expect((await firstFlush).accepted, 1);

      final secondFlush = chronicler.flush();
      await _waitFor(() => exporter.attempts.length == 3);
      expect(
        (exporter.batches.last.records.single as MetricRecord).payload.sum,
        9,
      );
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      expect((await secondFlush).accepted, 1);
      await chronicler.close();
    });

    test('should reject hooks that rewrite metric interval identity', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            final metric = record as MetricRecord;
            return metric.copyWith(
              payload: metric.payload.copyWith(name: 'rewritten'),
            );
          },
        ),
      );
      Context().withChronicler(chronicler.recorder).metrics.counter('requests').add(1);

      final report = await chronicler.flush();

      expect(report.accepted, 0);
      expect(report.dropped, {DropReason.invalidRecord: 1});
      expect(exporter.batches, isEmpty);
      await chronicler.close();
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  Duration batchInterval = const Duration(seconds: 5),
  int maxAttempts = 5,
  int maxBatchRecords = 1,
  int maxPendingRecords = 5000,
  Duration metricInterval = const Duration(minutes: 1),
  RedactionOptions redaction = const RedactionOptions(),
  Duration retryDelay = const Duration(seconds: 1),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(
      maxAttempts: maxAttempts,
      maxBatchRecords: maxBatchRecords,
      maxPendingRecords: maxPendingRecords,
      batchInterval: batchInterval,
      initialRetryDelay: retryDelay,
      maxRetryDelay: retryDelay,
    ),
    metrics: MetricOptions(interval: metricInterval),
    redaction: redaction,
  ),
);

List<double?> _sums(TestExporter exporter) => exporter.batches
    .expand((batch) => batch.records)
    .cast<MetricRecord>()
    .map((record) => record.payload.sum)
    .toList();

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/async.dart';
import 'support/exporter.dart';
import 'support/metric_aggregation.dart';
import 'support/metric_clock.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Chronicler metric lifecycle', () {
    test('should reject oversized dimensions before retaining a series', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxRecordBytes: 1024),
          metrics: MetricOptions(maxSeries: 1, maxSeriesPerInstrument: 1),
        ),
      );
      addTearDown(chronicler.close);
      chronicler.recorder.metrics.counter('requests')
        ..add(1, attributes: {'route': 'x' * 1024})
        ..add(2, attributes: {'route': '/orders'});

      final report = await chronicler.flush();

      expect(report.accepted, 1);
      expect(_sums(exporter), [2]);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidMeasurement], BigInt.one);
      expect(chronicler.diagnosticCounts[DiagnosticReason.seriesLimitReached], isNull);
    });

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
      final clock = MetricClock();
      final chronicler = _chronicler(
        exporter,
        clock: clock,
        metricInterval: const Duration(milliseconds: 100),
      );
      final counter = chronicler.recorder.metrics.counter('requests')..add(1);
      clock.advance(const Duration(milliseconds: 50));
      await chronicler.flush();
      counter.add(2);

      clock.advance(const Duration(milliseconds: 50));
      await settleAsync();
      expect(_sums(exporter), [1]);

      clock.advance(const Duration(milliseconds: 50));
      await waitForCondition(() => _sums(exporter).length == 2);
      expect(_sums(exporter), [1, 2]);
      await chronicler.close();
    });

    test('should discard unfinished and queued metrics while retaining handles', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      const interval = Duration(seconds: 17);
      final chronicler = _chronicler(
        exporter,
        clock: clock,
        maxBatchRecords: 10,
        batchInterval: const Duration(minutes: 1),
        metricInterval: interval,
      );
      final metrics = chronicler.recorder.metrics;
      final counter = metrics.counter('requests')..add(1);
      clock.advance(interval);
      await settleAsync();
      counter.add(5);

      chronicler.setCollectionEnabled(ChroniclerSignal.metrics, enabled: false);
      counter.add(10);
      chronicler.setCollectionEnabled(ChroniclerSignal.metrics, enabled: true);
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
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(1);

      final firstFlush = chronicler.flush();
      await waitForCondition(() => exporter.attempts.isNotEmpty);
      final original = exporter.batches.single.records.single as MetricRecord;
      counter.add(9);
      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await waitForCondition(() => exporter.attempts.length == 2);

      final retry = exporter.batches.last.records.single as MetricRecord;
      expect(retry.envelope.eventId, original.envelope.eventId);
      expect(retry.payload, original.payload);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      expect((await firstFlush).accepted, 1);

      final secondFlush = chronicler.flush();
      await waitForCondition(() => exporter.attempts.length == 3);
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

    test('should contain record construction failures and start a fresh interval', () {
      var fail = true;
      final harness = MetricHarness(
        createRecord: (payload) {
          if (fail) {
            fail = false;
            throw StateError('record construction failed');
          }
          return MetricHarness.record(payload);
        },
      );
      final counter = harness.metrics.counter('requests')..add(1);
      expect(harness.seal(), isEmpty);
      counter.add(2);
      expect(harness.seal().single.payload.sum, 2);
      expect(harness.reasons, [DiagnosticReason.invalidRecord]);
    });

    test('should validate finalized dimensions with the metric attribute limit', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          metrics: MetricOptions(maxAttributes: 2),
        ),
      );
      chronicler.recorder.metrics
          .counter('requests')
          .add(
            1,
            attributes: {'route': '/orders', 'method': 'GET'},
          );

      final report = await chronicler.flush();

      expect(report.accepted, 1);
      expect(report.dropped, isEmpty);
      await chronicler.close();
    });

    for (final invalid in <String, MetricPayload Function(MetricPayload)>{
      'negative counter sum': (payload) => payload.copyWith(sum: -1),
      'nested dimension': (payload) => payload.copyWith(
        attributes: {
          'nested': {'value': 1},
        },
      ),
      'null dimension': (payload) => payload.copyWith(attributes: {'missing': null}),
    }.entries) {
      test('should reject a hook-created ${invalid.key}', () async {
        final exporter = TestExporter(acceptImmediately: true);
        final chronicler = _chronicler(
          exporter,
          redaction: RedactionOptions(
            beforeRecord: (record) {
              final metric = record as MetricRecord;
              return metric.copyWith(payload: invalid.value(metric.payload));
            },
          ),
        );
        chronicler.recorder.metrics.counter('requests').add(1);
        final report = await chronicler.flush();
        expect(report.accepted, 0);
        expect(report.dropped, {DropReason.invalidRecord: 1});
        expect(exporter.batches, isEmpty);
        await chronicler.close();
      });
    }

    test('should keep interval scheduling paused while metrics are disabled', () async {
      final clock = MetricClock();
      final chronicler = _disabledMetrics(clock);
      chronicler.recorder.metrics.counter('requests');
      await chronicler.flush();
      clock.advance(const Duration(seconds: 30));
      await settleAsync();

      expect(clock.activeWaits, 0);
      await chronicler.close();
    });

    test('should retain only one active wait when first enabled', () async {
      final clock = MetricClock();
      final chronicler = _disabledMetrics(clock)
        ..setCollectionEnabled(ChroniclerSignal.metrics, enabled: true);
      await settleAsync();

      expect(clock.activeWaits, 1);
      await chronicler.close();
      expect(clock.activeWaits, 0);
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  MetricClock? clock,
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
  clock: clock,
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

Chronicler _disabledMetrics(MetricClock clock) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: TestExporter(acceptImmediately: true),
  clock: clock,
  options: const ChroniclerOptions(
    enabledSignals: {
      ChroniclerSignal.logs,
      ChroniclerSignal.events,
      ChroniclerSignal.traces,
      ChroniclerSignal.errors,
    },
  ),
);

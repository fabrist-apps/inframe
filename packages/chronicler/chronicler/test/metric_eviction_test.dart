import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';
import 'support/metric_aggregation.dart';

void main() {
  group('Chronicler metric idle eviction', () {
    test('should finalize an expired series before admitting its replacement', () async {
      final harness = MetricHarness(
        options: const MetricOptions(
          maxSeries: 1,
          maxSeriesPerInstrument: 1,
          idleTimeout: Duration(seconds: 10),
        ),
      );
      final clock = harness.clock;
      final counter = harness.metrics.counter('requests')..add(1, attributes: {'route': 'old'});
      clock.advance(const Duration(seconds: 10));
      counter.add(2, attributes: {'route': 'new'});
      harness.seal();

      final payloads = harness.records.map((record) => record.payload).toList();
      expect(payloads, hasLength(2));
      expect(payloads.map((payload) => payload.sum), [1, 2]);
      expect(payloads.map((payload) => payload.attributes['route']), ['old', 'new']);
    });

    test('should not refresh idle time for rejected measurements or lookup', () async {
      final harness = MetricHarness(
        options: const MetricOptions(
          maxSeries: 1,
          maxSeriesPerInstrument: 1,
          idleTimeout: Duration(seconds: 10),
        ),
      );
      final clock = harness.clock;
      final metrics = harness.metrics;
      final counter = metrics.counter('requests')..add(1, attributes: {'route': 'old'});

      clock.advance(const Duration(seconds: 9));
      counter.add(-1, attributes: {'route': 'old'});
      expect(identical(metrics.counter('requests'), counter), isTrue);
      clock
        ..rewindWall(const Duration(days: 1))
        ..advance(const Duration(seconds: 1));
      counter.add(2, attributes: {'route': 'new'});
      harness.seal();

      expect(
        harness.records.map((record) => record.payload.sum),
        [1, 2],
      );
      expect(harness.reasons, [DiagnosticReason.invalidMeasurement]);
    });

    test('should retain active series and reclaim empty state at an interval boundary', () async {
      final harness = MetricHarness(
        options: const MetricOptions(
          maxSeries: 1,
          maxSeriesPerInstrument: 1,
          idleTimeout: Duration(seconds: 10),
        ),
      );
      final clock = harness.clock;
      final counter = harness.metrics.counter('requests')..add(1, attributes: {'route': 'active'});

      clock.advance(const Duration(seconds: 9));
      counter.add(1, attributes: {'route': 'active'});
      clock.advance(const Duration(seconds: 1));
      counter.add(5, attributes: {'route': 'blocked'});
      harness.seal();
      expect(harness.reasons, [DiagnosticReason.seriesLimitReached]);
      expect(
        harness.records.single.payload.sum,
        2,
      );

      clock.advance(const Duration(seconds: 9));
      harness.seal();
      counter.add(3, attributes: {'route': 'replacement'});
      harness.seal();
      expect(
        harness.records.last.payload.sum,
        3,
      );
    });

    test('should reclaim capacity even when final delivery rejects the expired record', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(
        exporter,
        batchInterval: const Duration(minutes: 1),
        maxPendingRecords: 1,
        maxBatchRecords: 10,
      );
      final context = Context().withChronicler(chronicler.recorder);
      context.logs.info('occupies queue');
      final counter = context.metrics.counter('requests')..add(1, attributes: {'route': 'expired'});

      await Future<void>.delayed(const Duration(milliseconds: 2));
      counter.add(2, attributes: {'route': 'replacement'});
      chronicler.setCollectionEnabled(ChroniclerSignal.logs, enabled: false);
      await chronicler.flush();

      expect(chronicler.diagnosticCounts[DiagnosticReason.queueFull], BigInt.one);
      expect(
        (exporter.batches.single.records.single as MetricRecord).payload.attributes['route'],
        'replacement',
      );
      await chronicler.close();
    });

    test('should use the common idle store for every instrument kind', () async {
      final harness = MetricHarness(
        options: const MetricOptions(
          maxSeries: 1,
          maxSeriesPerInstrument: 1,
          idleTimeout: Duration(seconds: 10),
        ),
      );
      final clock = harness.clock;
      final metrics = harness.metrics;
      metrics.histogram('latency', boundaries: [10]).record(4);
      harness.seal();

      clock.advance(const Duration(seconds: 10));
      harness.seal();
      metrics.gauge('depth').set(7);
      harness.seal();

      expect(
        harness.records.last.payload.instrument,
        MetricInstrument.gauge,
      );
      expect(const MetricOptions().idleTimeout, const Duration(minutes: 5));
    });

    test('should contain instrument lookup from a finalization hook', () async {
      final exporter = TestExporter(acceptImmediately: true);
      late Chronicler chronicler;
      chronicler = _chronicler(
        exporter,
        redaction: RedactionOptions(
          beforeRecord: (record) {
            chronicler.recorder.metrics.counter('inside.hook').add(1);
            return record;
          },
        ),
      );
      final counter = chronicler.recorder.metrics.counter('requests')
        ..add(1, attributes: {'route': 'old'});
      await Future<void>.delayed(const Duration(milliseconds: 2));

      expect(
        () => counter.add(2, attributes: {'route': 'replacement'}),
        returnsNormally,
      );
      await chronicler.flush();

      expect(
        exporter.batches
            .expand((batch) => batch.records)
            .cast<MetricRecord>()
            .map((record) => record.payload.sum),
        [1, 2],
      );
      expect(chronicler.diagnosticCounts[DiagnosticReason.reentrantRecording], BigInt.two);
      await chronicler.close();
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  Duration batchInterval = const Duration(seconds: 5),
  int maxPendingRecords = 5000,
  int maxBatchRecords = 1,
  RedactionOptions redaction = const RedactionOptions(),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(
      batchInterval: batchInterval,
      maxBatchRecords: maxBatchRecords,
      maxPendingRecords: maxPendingRecords,
    ),
    metrics: const MetricOptions(
      maxSeries: 1,
      maxSeriesPerInstrument: 1,
      idleTimeout: Duration(microseconds: 1),
    ),
    redaction: redaction,
  ),
);

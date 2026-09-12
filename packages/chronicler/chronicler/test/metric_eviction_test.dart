import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart' show ChroniclerMetricFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';
import 'support/metric_clock.dart';

void main() {
  group('Chronicler metric idle eviction', () {
    test('should finalize an expired series before admitting its replacement', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(1, attributes: {'route': 'old'});
      clock.advance(const Duration(seconds: 10));
      counter.add(2, attributes: {'route': 'new'});
      await chronicler.flush();

      final payloads = exporter.batches
          .expand((batch) => batch.records)
          .cast<MetricRecord>()
          .map((record) => record.payload)
          .toList();
      expect(payloads, hasLength(2));
      expect(payloads.map((payload) => payload.sum), [1, 2]);
      expect(payloads.map((payload) => payload.attributes['route']), ['old', 'new']);

      await chronicler.close();
    });

    test('should not refresh idle time for rejected measurements or lookup', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      final counter = metrics.counter('requests')..add(1, attributes: {'route': 'old'});

      clock.advance(const Duration(seconds: 9));
      counter.add(-1, attributes: {'route': 'old'});
      expect(identical(metrics.counter('requests'), counter), isTrue);
      clock.rewindWall(const Duration(days: 1));
      // Reuse this clock after the intervening observation and lookup.
      // ignore: cascade_invocations
      clock.advance(const Duration(seconds: 1));
      counter.add(2, attributes: {'route': 'new'});
      await chronicler.flush();

      expect(
        exporter.batches
            .expand((batch) => batch.records)
            .cast<MetricRecord>()
            .map((record) => record.payload.sum),
        [1, 2],
      );
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidMeasurement], BigInt.one);
      await chronicler.close();
    });

    test('should retain active series and reclaim empty state at an interval boundary', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final counter = Context().withChronicler(chronicler.recorder).metrics.counter('requests')
        ..add(1, attributes: {'route': 'active'});

      clock.advance(const Duration(seconds: 9));
      counter.add(1, attributes: {'route': 'active'});
      clock.advance(const Duration(seconds: 1));
      counter.add(5, attributes: {'route': 'blocked'});
      await chronicler.flush();
      expect(chronicler.diagnosticCounts[DiagnosticReason.seriesLimitReached], BigInt.one);
      expect(
        (exporter.batches.single.records.single as MetricRecord).payload.sum,
        2,
      );

      clock.advance(const Duration(seconds: 9));
      ChroniclerMetricFixture.rotate(chronicler);
      counter.add(3, attributes: {'route': 'replacement'});
      await chronicler.flush();
      expect(
        (exporter.batches.last.records.single as MetricRecord).payload.sum,
        3,
      );
      await chronicler.close();
    });

    test('should reclaim capacity even when final delivery rejects the expired record', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(
        exporter,
        batchInterval: const Duration(minutes: 1),
        maxPendingRecords: 1,
      );
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final context = Context().withChronicler(chronicler.recorder);
      context.logs.info('occupies queue');
      final counter = context.metrics.counter('requests')..add(1, attributes: {'route': 'expired'});

      clock.advance(const Duration(seconds: 10));
      counter.add(2, attributes: {'route': 'replacement'});
      chronicler.setCollectionEnabled(ChroniclerSignal.logs, false);
      await chronicler.flush();

      expect(chronicler.diagnosticCounts[DiagnosticReason.queueFull], BigInt.one);
      expect(
        (exporter.batches.single.records.single as MetricRecord).payload.attributes['route'],
        'replacement',
      );
      await chronicler.close();
    });

    test('should use the common idle store for every instrument kind', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      metrics.histogram('latency', boundaries: [10]).record(4);
      await chronicler.flush();

      clock.advance(const Duration(seconds: 10));
      ChroniclerMetricFixture.rotate(chronicler);
      metrics.gauge('depth').set(7);
      await chronicler.flush();

      expect(
        (exporter.batches.last.records.single as MetricRecord).payload.instrument,
        MetricInstrument.gauge,
      );
      expect(const MetricOptions().idleTimeout, const Duration(minutes: 5));
      await chronicler.close();
    });

    test('should contain instrument lookup from a finalization hook', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = MetricClock();
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
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final counter = chronicler.recorder.metrics.counter('requests')
        ..add(1, attributes: {'route': 'old'});
      clock.advance(const Duration(seconds: 10));

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
  RedactionOptions redaction = const RedactionOptions(),
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(
      batchInterval: batchInterval,
      maxBatchRecords: 1,
      maxPendingRecords: maxPendingRecords,
    ),
    metrics: const MetricOptions(
      maxSeries: 1,
      maxSeriesPerInstrument: 1,
      idleTimeout: Duration(seconds: 10),
    ),
    redaction: redaction,
  ),
);

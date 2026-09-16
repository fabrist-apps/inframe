import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('ChroniclerHistogram', () {
    test('should export upper-inclusive buckets and distribution fields', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter);
      Context()
          .withChronicler(chronicler.recorder)
          .metrics
          .histogram(
            'request.duration',
            unit: 'ms',
            boundaries: [10, 50],
          )
        ..record(-1)
        ..record(10)
        ..record(11)
        ..record(50)
        ..record(51);
      await chronicler.flush();

      final payload = (exporter.batches.single.records.single as MetricRecord).payload;
      expect(payload.instrument, MetricInstrument.histogram);
      expect(payload.boundaries, [10, 50]);
      expect(payload.bucketCounts, [2, 2, 1]);
      expect(payload.count, 5);
      expect(payload.observationCount, 5);
      expect(payload.sum, 121);
      expect(payload.min, -1);
      expect(payload.max, 51);

      await chronicler.close();
    });

    test('should validate and snapshot boundaries after double conversion', () async {
      final boundaries = <num>[10, 50];
      final chronicler = _chronicler(TestExporter());
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      final histogram = metrics.histogram('latency', boundaries: boundaries);
      boundaries[0] = 20;
      final roundedBoundary = BigInt.parse('9007199254740992').toInt();

      expect(identical(histogram, metrics.histogram('latency', boundaries: [10.0, 50.0])), isTrue);
      for (final invalid in <List<num>>[
        [],
        [double.nan],
        [double.infinity],
        [10, 10],
        [50, 10],
        [roundedBoundary, roundedBoundary + 1],
      ]) {
        expect(
          () => metrics.histogram('invalid${invalid.length}', boundaries: invalid),
          throwsA(isA<ChroniclerConfigurationException>()),
        );
      }
      expect(
        () => metrics.histogram('latency', boundaries: [10, 100]),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      final limited = _chronicler(
        TestExporter(),
        maxHistogramBoundaries: 1,
      );
      expect(
        () => limited.recorder.metrics.histogram('too.many', boundaries: [1, 2]),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      await limited.close();
      await chronicler.close();
    });

    test('should reject invalid and overflowing observations without partial updates', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter);
      Context()
          .withChronicler(chronicler.recorder)
          .metrics
          .histogram('values', boundaries: [10, 50])
        ..record(double.maxFinite)
        ..record(double.nan)
        ..record(double.infinity)
        ..record(double.maxFinite);
      await chronicler.flush();

      final payloads = exporter.batches.single.records.cast<MetricRecord>().map(
        (record) => record.payload,
      );
      final payload = payloads.single;
      expect(payload.sum, double.maxFinite);
      expect(payload.bucketCounts, [0, 0, 1]);
      expect(payload.count, 1);
      expect(payload.min, double.maxFinite);
      expect(payload.max, double.maxFinite);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidMeasurement], BigInt.from(3));
      await chronicler.close();
    });

    test('should isolate intervals and retain immutable finalized buckets', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter);
      final histogram =
          Context().withChronicler(chronicler.recorder).metrics.histogram('values', boundaries: [0])
            ..record(0);

      await chronicler.flush();
      final first = exporter.batches.single.records.single as MetricRecord;
      expect(first.payload.bucketCounts, [1, 0]);
      expect(() => first.payload.bucketCounts!.add(1), throwsUnsupportedError);

      histogram.record(1);
      await chronicler.flush();
      final second = exporter.batches.last.records.single as MetricRecord;
      expect(first.payload.bucketCounts, [1, 0]);
      expect(second.payload.bucketCounts, [0, 1]);

      chronicler
        ..setCollectionEnabled(ChroniclerSignal.metrics, enabled: false)
        ..setCollectionEnabled(ChroniclerSignal.metrics, enabled: true);
      expect(
        identical(
          histogram,
          Context()
              .withChronicler(chronicler.recorder)
              .metrics
              .histogram('values', boundaries: [0]),
        ),
        isTrue,
      );
      await chronicler.close();
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  int maxBatchRecords = 1,
  int maxHistogramBoundaries = 64,
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(maxBatchRecords: maxBatchRecords),
    metrics: MetricOptions(maxHistogramBoundaries: maxHistogramBoundaries),
  ),
);

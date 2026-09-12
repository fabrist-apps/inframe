import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/runtime.dart'
    show ChroniclerDeliveryFixture, ChroniclerMetricFixture;
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('Chronicler up/down counters and gauges', () {
    test('should export signed net changes and the latest gauge observation', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 2),
        ),
      );
      final metrics = Context().withChronicler(chronicler.recorder).metrics;

      metrics.upDownCounter('connections.active')
        ..add(1)
        ..add(-1);
      metrics.gauge('queue.depth')
        ..set(10)
        ..set(-2);
      final report = await chronicler.flush();

      expect(report.accepted, 2);
      final payloads = exporter.batches.single.records
          .cast<MetricRecord>()
          .map((record) => record.payload)
          .toList();
      expect(
        payloads.singleWhere((payload) => payload.instrument == MetricInstrument.upDownCounter),
        isA<MetricPayload>()
            .having((payload) => payload.sum, 'sum', 0)
            .having((payload) => payload.observationCount, 'count', 2),
      );
      expect(
        payloads.singleWhere((payload) => payload.instrument == MetricInstrument.gauge),
        isA<MetricPayload>()
            .having((payload) => payload.value, 'value', -2)
            .having((payload) => payload.observationCount, 'count', 2)
            .having((payload) => payload.observedAt, 'observedAt', isNotNull),
      );

      await chronicler.close();
    });

    test('should reuse compatible handles and reject name conflicts across kinds', () async {
      final chronicler = _chronicler(TestExporter());
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      final changes = metrics.upDownCounter('connections', unit: 'connections');
      final depth = metrics.gauge('depth');

      expect(
        identical(changes, metrics.upDownCounter('connections', unit: 'connections')),
        isTrue,
      );
      expect(identical(depth, metrics.gauge('depth')), isTrue);
      expect(
        () => metrics.counter('connections', unit: 'connections'),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      expect(
        () => metrics.gauge('depth', unit: 'items'),
        throwsA(isA<ChroniclerConfigurationException>()),
      );
      await chronicler.close();
    });

    test('should keep the latest gauge timestamp and omit unobserved intervals', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final clock = _MetricClock();
      final chronicler = _chronicler(exporter);
      ChroniclerMetricFixture.overrideClocks(
        chronicler,
        now: () => clock.now,
        elapsed: () => clock.elapsed,
      );
      final gauge = Context().withChronicler(chronicler.recorder).metrics.gauge('depth')..set(1);
      clock.advance(const Duration(seconds: 2));
      gauge.set(-4);
      final first = await chronicler.flush();
      final second = await chronicler.flush();

      expect(first.accepted, 1);
      expect(second.accepted, 0);
      final payload = (exporter.batches.single.records.single as MetricRecord).payload;
      expect(payload.value, -4);
      expect(payload.observedAt, clock.now);
      expect(payload.temporality, isNull);
      await chronicler.close();
    });

    test('should reject invalid and overflowing updates atomically', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      final changes = metrics.upDownCounter('connections')..add(5);
      final gauge = metrics.gauge('depth')..set(7);

      changes
        ..add(double.nan)
        ..add(double.infinity);
      gauge
        ..set(double.nan)
        ..set(double.negativeInfinity);
      ChroniclerMetricFixture.setCounterAggregate(
        chronicler,
        name: 'connections',
        count: 1,
        sum: double.maxFinite,
      );
      changes.add(double.maxFinite);
      ChroniclerMetricFixture.setSeriesCount(
        chronicler,
        name: 'depth',
        count: 9007199254740991,
      );
      gauge.set(8);
      await chronicler.flush();

      final payloads = exporter.batches.single.records.cast<MetricRecord>().map(
        (record) => record.payload,
      );
      expect(
        payloads.singleWhere((payload) => payload.instrument == MetricInstrument.upDownCounter),
        isA<MetricPayload>()
            .having((payload) => payload.sum, 'sum', double.maxFinite)
            .having((payload) => payload.observationCount, 'count', 1),
      );
      expect(
        payloads.singleWhere((payload) => payload.instrument == MetricInstrument.gauge),
        isA<MetricPayload>()
            .having((payload) => payload.value, 'value', 7)
            .having(
              (payload) => payload.observationCount,
              'count',
              9007199254740991,
            ),
      );
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidMeasurement], BigInt.from(6));
      await chronicler.close();
    });

    test('should clear both kinds across metric collection changes', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      final changes = metrics.upDownCounter('connections')..add(4);
      final gauge = metrics.gauge('depth')..set(5);

      chronicler
        ..setCollectionEnabled(ChroniclerSignal.metrics, false)
        ..setCollectionEnabled(ChroniclerSignal.metrics, true);
      changes.add(-2);
      final first = await chronicler.flush();
      expect(first.accepted, 1);
      expect(
        (exporter.batches.single.records.single as MetricRecord).payload.sum,
        -2,
      );

      gauge.set(8);
      final second = await chronicler.flush();
      expect(second.accepted, 1);
      expect(
        (exporter.batches.last.records.single as MetricRecord).payload.value,
        8,
      );
      await chronicler.close();
    });

    test('should seal both kinds during shutdown', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = _chronicler(exporter, maxBatchRecords: 2);
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      metrics.upDownCounter('connections').add(-1);
      metrics.gauge('depth').set(-5);

      final report = await chronicler.close();

      expect(report.accepted, 2);
      expect(
        exporter.batches.single.records
            .cast<MetricRecord>()
            .map((record) => record.payload.instrument),
        containsAll([MetricInstrument.upDownCounter, MetricInstrument.gauge]),
      );
    });

    test('should preserve both finalized payloads across retry and codec round-trip', () async {
      final exporter = TestExporter();
      final chronicler = _chronicler(
        exporter,
        maxAttempts: 2,
        maxBatchRecords: 2,
      );
      ChroniclerDeliveryFixture.selectRetryDelay(chronicler, (_, _) => Duration.zero);
      final metrics = Context().withChronicler(chronicler.recorder).metrics;
      metrics.upDownCounter('connections').add(-3);
      metrics.gauge('depth').set(6);

      final flush = chronicler.flush();
      await _waitFor(() => exporter.attempts.isNotEmpty);
      final originals = exporter.batches.single.records;
      const codec = ChroniclerCodec();
      for (final record in originals) {
        final decoded = codec.decodeRecord(codec.encodeRecord(record));
        expect(decoded, isA<Decoded<ChroniclerRecord>>());
        expect((decoded as Decoded<ChroniclerRecord>).value, record);
      }
      exporter.attempts.single.completer.complete(const ExportResult.retryable());
      await _waitFor(() => exporter.attempts.length == 2);

      expect(exporter.batches.last.records, originals);
      exporter.attempts.last.completer.complete(const ExportResult.accepted());
      expect((await flush).accepted, 2);
      await chronicler.close();
    });
  });
}

Chronicler _chronicler(
  TestExporter exporter, {
  int maxAttempts = 5,
  int maxBatchRecords = 1,
}) => Chronicler(
  appId: 'app',
  release: 'release',
  source: ChroniclerSource.server,
  exporter: exporter,
  options: ChroniclerOptions(
    delivery: DeliveryOptions(
      maxAttempts: maxAttempts,
      maxBatchRecords: maxBatchRecords,
      initialRetryDelay: const Duration(milliseconds: 1),
      maxRetryDelay: const Duration(milliseconds: 1),
    ),
  ),
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _MetricClock {
  DateTime now = DateTime.utc(2026, 9, 12);
  Duration elapsed = Duration.zero;

  void advance(Duration duration) {
    now = now.add(duration);
    elapsed += duration;
  }
}
